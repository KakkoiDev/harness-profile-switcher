# PLAN — hps Profile Switcher Improvements

**Extracted from:** `PLAN-icm-focus-resilience.md` Phase C + relevant Phase B context  
**Repo:** `~/Code/claude-code-profiles/` (canonical: `harness-profile-switcher`)  
**Date:** 2026-06-12  
**Status:** Ready for implementation  
**Base:** hps v2.0.0 (harness-aware, pi support live)

---

## Scope

This plan covers **only** the `hps` (harness profile switcher) work. It does NOT cover the icm-runtime changes (Phase A, D, E of the parent plan). Those are in a separate repo (`~/Code/icm-runtime/`).

### What's already in hps v2.0.0

| Feature | Status |
|---------|--------|
| `--harness claude\|pi` selection | ✅ Done |
| `HPS_HARNESS` env var + auto-detection | ✅ Done |
| `hps <profile>` switch | ✅ Done |
| `hps list`, `current`, `init`, `create`, `clone`, `install` | ✅ Done |
| Pi `install` no-op | ✅ Done |
| Deprecation warnings for old env vars | ✅ Done |
| `_is_file_item()` helper | ✅ Done |
| `$CONFIG_DIR` / `$PROFILES_DIR` (harness-aware) | ✅ Done |
| Safety: refuse to overwrite non-symlinks | ✅ Done |

---

## 1. Command: `hps audit <profile>` — NEW

### 1.1 Purpose

Compare a target profile against all other profiles and report what's missing. Helps users discover skills/agents/extensions from other profiles that should be adapted.

### 1.2 Harness-Aware Design

The command must work for both `claude` and `pi` harnesses, checking different item types per harness.

| Harness | Compared items |
|---------|---------------|
| claude | `skills/`, `agents/`, `plugins/` |
| pi | `skills/`, `extensions/`, `prompts/`, `themes/` |

Shared items (`skills/`) are compared in both harnesses. Harness-specific items are only compared in their respective harness.

### 1.3 Implementation

Add to `hps` main dispatch (`case ... esac`):

```bash
audit)
    [ -z "${2:-}" ] && { echo "Usage: hps audit <profile> [--write-missing]"; exit 1; }
    if [ "${2:-}" = "--write-missing" ]; then
        echo "Usage: hps audit <profile> --write-missing"
        exit 1
    fi
    cmd_audit "$2"
    ;;
audit-write|audit--write-missing)
    # Handled via flag detection in cmd_audit or separate dispatch
    ;;
```

Better: detect `--write-missing` as a second argument within `cmd_audit`:

```bash
audit)
    local audit_profile="${2:-}"
    local write_missing=false
    [ "${3:-}" = "--write-missing" ] && write_missing=true
    [ -z "$audit_profile" ] && { echo "Usage: hps audit <profile> [--write-missing]"; exit 1; }
    cmd_audit "$audit_profile" "$write_missing"
    ;;
```

### 1.4 `cmd_audit()` — Harness-Aware Comparison

```bash
cmd_audit() {
    local profile="$1"
    local write_missing="${2:-false}"
    local target_dir="$PROFILES_DIR/$profile"
    [ -d "$target_dir" ] || { echo "Profile '$profile' not found" >&2; exit 1; }

    local output=""
    output+="hps audit $profile (harness: $HARNESS)\n\n"

    for other in "$PROFILES_DIR"/*/; do
        [ -d "$other" ] || continue
        other_name=$(basename "$other")
        [ "$other_name" = "$profile" ] && continue

        output+="## From '$other_name' profile\n\n"

        # ── Skills (both harnesses) ──
        _audit_skills "$target_dir" "$other" output

        case "$HARNESS" in
            claude)
                # ── Agents (claude only) ──
                _audit_dir_of_type "$target_dir/agents" "$other/agents" "md" "Agents" \
                    "candidate for skill conversion" output
                # ── Plugins (claude only) ──
                _audit_dir_of_type "$target_dir/plugins" "$other/plugins" "json" "Plugins" \
                    "reinstall with hps install" output
                ;;
            pi)
                # ── Extensions (pi only, .ts + .js) ──
                _audit_extensions "$target_dir" "$other" output
                # ── Prompts (pi only) ──
                _audit_dir_of_type "$target_dir/prompts" "$other/prompts" "md" "Prompts" \
                    "can be copied" output
                # ── Themes (pi only) ──
                _audit_dir_of_type "$target_dir/themes" "$other/themes" "json" "Themes" \
                    "can be copied" output
                ;;
        esac
    done

    output+="Run 'hps audit $profile --write-missing' to generate MISSING_SKILLS.md\n"
    printf '%b' "$output"

    if [ "$write_missing" = "true" ]; then
        _write_missing_skills "$profile" "$output"
    fi
}
```

### 1.5 Helper Functions

```bash
# Compare skills/ directories (shared across harnesses)
_audit_skills() {
    local target_dir="$1" other_dir="$2"
    local -n _out="$3"
    if [ -d "$other_dir/skills" ] && [ -d "$target_dir/skills" ]; then
        local missing=""
        for skill in "$other_dir/skills"/*/; do
            [ -d "$skill" ] || continue
            sname=$(basename "$skill")
            if [ ! -e "$target_dir/skills/$sname" ]; then
                local tag=""; [ -f "$skill/SKILL.md" ] && tag=" (ICM skill)" || tag=""
                missing+="  $sname$tag\n"
            fi
        done
        if [ -n "$missing" ]; then
            _out+="### Skills\n"
            _out+="$missing\n"
        fi
    fi
}

# Compare a directory of same-type files (agents/, prompts/, themes/, plugins/)
_audit_dir_of_type() {
    local target="$1" other="$2" ext="$3" label="$4" note="$5"
    local -n _out="$6"
    if [ -d "$other" ] && [ -d "$target" ]; then
        local missing=""
        for f in "$other"/*."$ext"; do
            [ -f "$f" ] 2>/dev/null || continue
            fname=$(basename "$f")
            if [ ! -f "$target/$fname" ]; then
                local name_no_ext="${fname%.$ext}"
                missing+="  $name_no_ext ($note)\n"
            fi
        done
        if [ -n "$missing" ]; then
            _out+="### $label\n"
            _out+="$missing\n"
        fi
    fi
}

# Compare extensions/ (pi only — .ts AND .js files)
_audit_extensions() {
    local target_dir="$1" other_dir="$2"
    local -n _out="$3"
    if [ -d "$other_dir/extensions" ] && [ -d "$target_dir/extensions" ]; then
        local missing=""
        for ext in "$other_dir/extensions"/*.ts "$other_dir/extensions"/*.js; do
            [ -f "$ext" ] 2>/dev/null || continue
            ename=$(basename "$ext")
            if [ ! -f "$target_dir/extensions/$ename" ]; then
                missing+="  $ename (extension — candidate for skill conversion)\n"
            fi
        done
        if [ -n "$missing" ]; then
            _out+="### Extensions\n"
            _out+="$missing\n"
        fi
    fi
}
```

### 1.6 Output Format

#### Claude harness example

```
hps audit icm-focus (harness: claude)

## From 'main' profile

### Skills
  refine-tickets (ICM skill)
  sprint-focus (ICM skill)
  todo-triage (ICM skill)

### Agents
  review (candidate for skill conversion)
  web-bot (candidate for skill conversion)

### Plugins
  installed_plugins.json (reinstall with hps install)

Run 'hps audit icm-focus --write-missing' to generate MISSING_SKILLS.md
```

#### Pi harness example

```
hps --harness pi audit icm-focus (harness: pi)

## From 'main' profile

### Skills
  ai-folder-research (ICM skill)

### Extensions
  doom.ts (extension — candidate for skill conversion)

### Prompts
  review.md (can be copied)

### Themes
  (none)

Run 'hps audit icm-focus --write-missing' to generate MISSING_SKILLS.md
```

---

## 2. Flag: `hps audit <profile> --write-missing` — NEW

### 2.1 Purpose

Write audit results to `<profile>/MISSING_SKILLS.md`. Preserves any manual notes after `## Adaptation Notes` section.

### 2.2 Implementation

```bash
_write_missing_skills() {
    local profile="$1"
    local audit_output="$2"
    local target_dir="$PROFILES_DIR/$profile"
    local outfile="$target_dir/MISSING_SKILLS.md"

    # Capture existing manual notes (after "## Adaptation Notes")
    local manual_notes=""
    if [ -f "$outfile" ]; then
        # Extract everything from "## Adaptation Notes" onwards
        manual_notes=$(sed -n '/^## Adaptation Notes/,$ p' "$outfile" 2>/dev/null)
    fi

    # Write header + generated audit
    {
        echo "# Missing Skills — $profile profile"
        echo ""
        echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Harness: $HARNESS"
        echo ""
        echo "This file tracks skills/agents/extensions that exist in other profiles"
        echo "and should be adapted for this profile."
        echo ""
        printf '%b' "$audit_output"
        echo ""
        if [ -n "$manual_notes" ]; then
            printf '%s\n' "$manual_notes"
        else
            echo "## Adaptation Notes"
            echo ""
            echo "(Add manual notes here. This section is preserved across regenerations.)"
        fi
    } > "$outfile"

    echo "Wrote MISSING_SKILLS.md to $outfile"
}
```

**Idempotency:** Running `--write-missing` multiple times produces the same generated section. User-added notes after `## Adaptation Notes` survive regenerations.

---

## 3. `hps install` — ICM Runtime Detection — UPDATE

### 3.1 Purpose

When installing plugins for a Claude Code profile that contains ICM skills, also ensure the ICM runtime is symlinked into `~/.agents/skills/`.

### 3.2 Implementation

Add after the existing plugin install loop in `cmd_install()`, before the "Done" message:

```bash
# ICM runtime detection (claude harness only)
if [ "$HAS_INSTALL" = "true" ]; then
    # Check if any skill in this profile uses ICM (has SKILL.md with stages/)
    local has_icm=false
    if [ -d "$PROFILES_DIR/$current/skills" ]; then
        for skill_dir in "$PROFILES_DIR/$current/skills"/*/; do
            if [ -f "$skill_dir/SKILL.md" ] && [ -d "$skill_dir/stages" ]; then
                has_icm=true
                break
            fi
        done
    fi

    if [ "$has_icm" = "true" ]; then
        local icm_installer="$HOME/Code/icm-runtime/installer.sh"
        if [ -f "$icm_installer" ]; then
            echo "  Installing ICM runtime..."
            bash "$icm_installer" 2>&1 || echo "    Warning: ICM installer failed"
        else
            echo "  Warning: ICM runtime installer not found at $icm_installer"
            echo "  Clone icm-runtime to ~/Code/icm-runtime for ICM skill support."
        fi
    fi
fi
```

**Pi harness:** No change. `cmd_install()` already no-ops for pi.

---

## 4. Profile Isolation Audit — UPDATE to `hps init` and `hps <profile>`

### 4.1 Purpose

Add integrity checks when switching profiles or running init:
- Verify managed item symlinks point into the correct profile
- Warn on orphaned items in config dir
- Detect cross-profile symlink sharing

### 4.2 Implementation

Add a `_verify_isolation()` function called at the end of `cmd_switch()` and `cmd_init()`:

```bash
_verify_isolation() {
    local profile_name="$1"
    local warnings=0

    # 1. Check each managed item is a symlink → correct profile
    for item in "${MANAGED_ITEMS[@]}"; do
        local target="$CONFIG_DIR/$item"
        if [ -L "$target" ]; then
            local resolved
            resolved=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$target" 2>/dev/null)
            local expected_dir
            expected_dir=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$PROFILES_DIR/$profile_name" 2>/dev/null)
            case "$resolved" in
                "$expected_dir"/*) ;;
                *)
                    echo "Warning: $target points outside profile '$profile_name' ($resolved)" >&2
                    warnings=$((warnings + 1))
                    ;;
            esac
        fi
    done

    # 2. Check for orphaned (non-managed) items in config dir
    for entry in "$CONFIG_DIR"/*; do
        [ -e "$entry" ] || continue
        local ename=$(basename "$entry")
        local is_managed=false
        for item in "${MANAGED_ITEMS[@]}"; do
            [ "$ename" = "$item" ] && is_managed=true && break
        done
        if [ "$is_managed" = "false" ]; then
            # Skip known non-managed items per harness
            case "$HARNESS:$ename" in
                claude:backups|claude:cache|claude:debug|claude:file-history|claude:history.jsonl|claude:.last-*|claude:hooks|claude:Code|claude:downloads) ;;
                pi:sessions|pi:git|pi:npm|pi:trust.json|pi:keybindings.json|pi:models.json) ;;
                *)
                    echo "Note: Non-managed item in $CONFIG_DIR: $ename" >&2
                    ;;
            esac
        fi
    done

    # 3. Check for cross-profile sharing (two different profile dirs sharing same target)
    # This requires comparing symlink targets across all profiles — heavy, skip by default.
    # Could be a separate `hps check` command later.

    # 4. Pi-specific: warn if ~/.agents/skills/ items shadow profile skills
    if [ "$HARNESS" = "pi" ] && [ -d "$HOME/.agents/skills" ]; then
        for shared_skill in "$HOME/.agents/skills"/*/; do
            [ -d "$shared_skill" ] || continue
            local ssname=$(basename "$shared_skill")
            if [ -d "$PROFILES_DIR/$profile_name/skills/$ssname" ]; then
                echo "Note: ~/.agents/skills/$ssname shadows profile skill (both active)" >&2
            fi
        done
    fi

    if [ $warnings -gt 0 ]; then
        echo "Run 'hps audit $profile_name' to compare against other profiles."
    fi
}
```

**Whitelist rationale:** Orphan warnings skip known non-managed config dir files (like Claude Code's `backups/`, `cache/`, `history.jsonl` and pi's `sessions/`, `git/`, `npm/`). These are harness-internal files that legitimately exist alongside managed symlinks.

---

## 5. Files Changed

| File | Section | Changes |
|------|---------|---------|
| `hps` | Main dispatch | Add `audit` case with `--write-missing` detection |
| `hps` | New function `cmd_audit()` | Harness-aware comparison of profiles |
| `hps` | New helpers `_audit_skills()`, `_audit_dir_of_type()`, `_audit_extensions()` | Reusable comparison logic |
| `hps` | New function `_write_missing_skills()` | Generate MISSING_SKILLS.md |
| `hps` | `cmd_install()` | Add ICM runtime detection (claude only) |
| `hps` | New function `_verify_isolation()` | Symlink integrity + orphan warnings |
| `hps` | `cmd_switch()` end | Call `_verify_isolation "$name"` |
| `hps` | `cmd_init()` end | Call `_verify_isolation main` |
| `hps` | `usage()` | Add `audit` and `audit --write-missing` to command list |
| `test_hps.sh` | New test blocks | See §6 |
| `README.md` | New section | Document `audit` + `MISSING_SKILLS.md` |
| `CONTRIBUTING.md` | Scope + tests | Add ICM scope note, pi audit test instructions |

---

## 6. Test Plan

### 6.1 New Test Blocks in `test_hps.sh`

All tests use `HPS_HARNESS` env var and/or `--harness` flag. Existing test infrastructure (`reset_env`, `assert_eq`, `assert_symlink`, etc.) is reused.

#### audit — claude harness

| Test | Description |
|------|-------------|
| `audit_lists_missing_skills` | Two profiles (full + empty), audit empty → lists missing skills |
| `audit_lists_missing_agents` | Full profile has agents, empty doesn't → listed as candidates |
| `audit_lists_missing_plugins` | Full profile has `installed_plugins.json`, empty doesn't → listed |
| `audit_skips_same_profile` | Audit profile against itself → no output for that profile |
| `audit_handles_empty_target` | Audit a profile with no skills/agents dirs → no crash |
| `audit_handles_single_profile` | Only one profile exists → says "nothing to compare" or outputs clean |
| `audit_nonexistent_profile` | `hps audit nope` → exits 1 with "not found" |

#### audit — pi harness

| Test | Description |
|------|-------------|
| `audit_pi_lists_missing_skills` | Two pi profiles, audit empty → lists missing skills |
| `audit_pi_lists_missing_extensions` | Profile has `.ts` extensions, target doesn't → listed |
| `audit_pi_lists_missing_prompts` | Profile has `.md` prompts, target doesn't → listed as "can be copied" |
| `audit_pi_lists_missing_themes` | Profile has `.json` themes, target doesn't → listed |

#### audit --write-missing

| Test | Description |
|------|-------------|
| `write_missing_creates_file` | `hps audit empty --write-missing` → file exists |
| `write_missing_preserves_notes` | Write once, add manual notes after `## Adaptation Notes`, write again → notes survive |
| `write_missing_idempotent` | Write twice → same generated content (no duplication) |

#### isolation audit

| Test | Description |
|------|-------------|
| `isolation_warns_if_symlink_outside_profile` | Symlink points to wrong profile → warning |
| `isolation_notes_orphaned_items` | Non-managed file in config dir → note |
| `isolation_skips_known_internals` | Known files (history.jsonl, sessions/, etc.) → no warning |
| `isolation_pi_warns_shadowed_skills` | Same skill in `~/.agents/skills/` and profile `skills/` → note |

#### ICM install (claude only)

| Test | Description |
|------|-------------|
| `install_detects_icm_skills` | Profile has skill with `stages/` dir → runs ICM installer |
| `install_skips_no_icm` | Profile has skills but no `stages/` dirs → no ICM installer run |
| `install_icm_installer_missing` | ICM installer not at `~/Code/icm-runtime/installer.sh` → warning, not crash |

### 6.2 Test Harness Setup

```bash
# Helper: create a profile with specific content
_create_test_profile() {
    local harness="$1" name="$2"
    HPS_HARNESS="$harness" "$HPS" create "$name" >/dev/null
    # Add test files...
}

# Helper: run audit and check output contains expected string
assert_audit_contains() {
    local label="$1" harness="$2" profile="$3" expected="$4"
    local out
    out=$(HPS_HARNESS="$harness" "$HPS" audit "$profile" 2>&1 || true)
    assert_eq "$label" "true" "$(echo "$out" | grep -q "$expected" && echo true || echo false)"
}

# Helper: run audit and check exit code
assert_audit_fails() {
    local label="$1" harness="$2" profile="$3"
    local out
    out=$(HPS_HARNESS="$harness" "$HPS" audit "$profile" 2>&1) && rc=0 || rc=$?
    assert_eq "$label" "1" "$rc"
}
```

---

## 7. Implementation Order

1. **Add helper functions first** (`_audit_skills`, `_audit_dir_of_type`, `_audit_extensions`) — they're used by `cmd_audit`
2. **Add `cmd_audit()`** — test with real profiles
3. **Add `--write-missing` support** — wired into `_write_missing_skills()`
4. **Add `_verify_isolation()`** — call from `cmd_switch` and `cmd_init`
5. **Add ICM install detection** — inside `cmd_install`
6. **Update usage** — add `audit` to help text for both harnesses
7. **Write tests** — run full `./test_hps.sh` before merging
8. **Update docs** — README.md, CONTRIBUTING.md

---

## 8. Constraints

| Constraint | Rationale |
|------------|-----------|
| No new dependencies | `hps` is bash + python3. Must stay that way. |
| No jq | Already avoided. Use grep/awk/sed for all JSON-flavored operations. |
| No performance regression on switch | `_verify_isolation()` runs at switch time. Keep it under 50ms. |
| Backward compat | Existing `hps` commands continue to work unchanged. `audit` is additive. |
| Harness-agnostic design | All new functions use `$HARNESS`, `$CONFIG_DIR`, `$PROFILES_DIR`, `${MANAGED_ITEMS[@]}` — never hardcode `~/.claude/` or `~/.pi/agent/`. |
| MISSING_SKILLS.md is plain markdown | No YAML frontmatter, no JSON. Editable by hand. |

---

## 9. Acceptance Criteria

1. `hps --harness claude audit icm-focus` lists skills and agents from `main` profile
2. `hps --harness pi audit pi-focus` lists skills, extensions, prompts, themes from `pi-main`
3. `hps audit profile --write-missing` generates `MISSING_SKILLS.md` preserving manual notes
4. `hps install` detects ICM skills and runs `~/Code/icm-runtime/installer.sh`
5. `hps <profile>` warns if symlink points outside expected profile dir
6. `hps <profile>` notes orphaned non-managed items in config dir
7. `hps <profile>` (pi) warns if `~/.agents/skills/` items shadow profile skills
8. All existing 80+ tests still pass
9. New tests (20+ cases from §6) pass
10. `shellcheck hps` clean

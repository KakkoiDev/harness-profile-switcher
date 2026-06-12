# Pi Harness Support Plan

**Goal:** Rename `claude-code-profiles` → `harness-profile-switcher`, add pi harness support, update all docs.

**Status:** Draft plan.

---

## Phase 0 — Rename (no behavior change yet)

### 0.1 Rename CLI script

| Old | New |
|-----|-----|
| `ccp` | `hps` (harness profile switcher) |

Keep `ccp` as a symlink or wrapper for backward compat (deprecation warning after 2 releases).

### 0.2 Rename files

| Old | New |
|-----|-----|
| `ccp` | `hps` |
| `test_ccp.sh` | `test_hps.sh` |
| `README.md` | (rewritten) |
| `CONTRIBUTING.md` | (rewritten) |
| `.gitignore` | add `ccp` symlink, keep `*.md` rule |

### 0.3 Rename in-file identifiers

| Old | New |
|-----|-----|
| `CCP_CLAUDE_DIR` | `HPS_CONFIG_DIR` |
| `CCP_PROFILES_DIR` | `HPS_PROFILES_DIR` |
| `~/.claude-profiles` | `~/.harness-profiles` (or `~/.${HARNESS}-profiles` per-harness) |
| `ccp` (CLI name in usage text) | `hps` |
| `claude-code-profiles` (project name) | `harness-profile-switcher` |
| `VERSION` bump | skip for now |

### 0.4 Rename install.sh URLs

- `https://raw.githubusercontent.com/KakkoiDev/claude-code-profiles/main/ccp` → `.../harness-profile-switcher/main/hps`
- Repo URL references in docs

---

## Phase 1 — Harness Abstraction

### 1.1 Architecture: harness registry in `hps`

Instead of if/else sprawl, use a harness definition table. Each harness defines:

```bash
declare -A HARNESS=(
  [config_dir]="$HOME/.claude"         # where symlinks live
  [profiles_dir]="$HOME/.claude-profiles"
  [profile_items]="agents skills plugins commands CLAUDE.md settings.json settings.local.json"
  [install_cmd]="claude plugin install"  # only claude has this
  [install_scope_arg]="--scope"
  [context_file]="CLAUDE.md"
)
```

Harness selection:
1. `HPS_HARNESS` env var (values: `claude`, `pi`)
2. `--harness <name>` CLI flag
3. Detection: if `~/.claude/` exists → claude; if `~/.pi/agent/` exists → pi; otherwise default `claude`

### 1.2 Harness definitions

#### Claude Code harness

| Key | Value |
|-----|-------|
| `config_dir` | `~/.claude/` |
| `profiles_dir` | `~/.claude-profiles/` |
| `profile_items` | `agents skills plugins commands CLAUDE.md settings.json settings.local.json` |
| `has_install` | `true` |
| `install_cmd` | `claude plugin install` |
| `install_scope_flag` | `--scope` |
| `context_file` | `CLAUDE.md` |

#### Pi harness

| Key | Value |
|-----|-------|
| `config_dir` | `~/.pi/agent/` |
| `profiles_dir` | `~/.pi-agent-profiles/` |
| `profile_items` | `extensions skills prompts themes AGENTS.md settings.json` |
| `has_install` | `false` |
| `install_cmd` | (none) |
| `install_scope_flag` | (none) |
| `context_file` | `AGENTS.md` |

**Pi-specific gotchas:**

- **No plugin install.** Pi extensions are TypeScript files in `~/.pi/agent/extensions/`, not installable by name. `hps install` with pi harness prints "pi has no plugin install — extensions are symlinked as files" and exits 0.
- **No `agents/` dir.** Pi has no `~/.pi/agent/agents/` concept.
- **No `commands/` dir.** Pi commands are registered by extensions, not seeded from a `commands/` directory.
- **No `settings.local.json`.** Pi uses `.pi/settings.json` (project) layered over `~/.pi/agent/settings.json` (global). No local overlay file in `~/.pi/agent/`.
- **Skills at multiple paths.** Pi loads skills from `~/.pi/agent/skills/`, `~/.agents/skills/`, `.pi/skills/`, `.agents/skills/`. Only `~/.pi/agent/skills/` is managed by hps — the rest are project-level and unaffected.
- **`AGENTS.md` vs `CLAUDE.md`.** Pi uses `AGENTS.md` for global context (also reads `CLAUDE.md` from project dirs). The managed item is `~/.pi/agent/AGENTS.md`.
- **Pi package installs.** If a pi profile uses packages (npm/git), the symlinked `settings.json` already contains the `packages` array. Pi auto-installs missing packages on startup after project trust. Nothing for hps to do.
- **No `install` step needed for pi.** The `hps install` command is Claude-only. Block or no-op it when harness=pi.
- **`prompts/`** — Pi prompt templates are `.md` files. Just symlinked like skills.
- **`themes/`** — Pi themes are `.json` files. Just symlinked.

### 1.3 What changes in each function

| Function | Change needed |
|----------|---------------|
| `usage()` | Show harness-specific managed items |
| `current_profile()` | Works as-is (uses `$PROFILE_ITEMS` array) |
| `cmd_list()` | Count agents vs extensions based on harness. For pi: count `.ts`/`.js` in extensions/, `.md` in prompts/, `.json` in themes/ |
| `cmd_current()` | No change |
| `cmd_init()` | Use `$CONFIG_DIR` instead of hardcoded `$CLAUDE_DIR` |
| `cmd_create()` | Touch harness-specific context file (CLAUDE.md or AGENTS.md) |
| `cmd_clone()` | No change (`cp -a` works for any harness) |
| `cmd_install()` | Guard: if pi harness, print "not applicable" and exit 0. Otherwise call `claude plugin install` as before. |
| `cmd_switch()` | Use `$PROFILE_ITEMS` array — already generic, just needs variable renaming |

---

## Phase 2 — Code Changes in `hps`

### 2.1 Top of file changes

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="2.0.0"

# Harness selection: env var > --harness flag > sniff > default
resolve_harness() {
    # 1. env var
    if [ -n "${HPS_HARNESS:-}" ]; then
        echo "$HPS_HARNESS"
        return
    fi
    # 2. sniff existing config dirs
    if [ -d "$HOME/.pi/agent" ] && [ ! -d "$HOME/.claude" ]; then
        echo "pi"
    elif [ -d "$HOME/.claude" ]; then
        echo "claude"
    else
        # default: claude (for backward compat)
        echo "claude"
    fi
}

HARNESS="${HPS_HARNESS:-$(resolve_harness)}"
# Allow --harness override (parsed early, before main case)
for arg in "$@"; do
    case "$arg" in
        --harness) shift; HARNESS="$1"; shift; break ;;
        --harness=*) HARNESS="${arg#*=}"; shift; break ;;
    esac
done

case "$HARNESS" in
    claude)
        CONFIG_DIR="${HPS_CONFIG_DIR:-$HOME/.claude}"
        PROFILES_DIR="${HPS_PROFILES_DIR:-$HOME/.claude-profiles}"
        MANAGED_ITEMS=(agents skills plugins commands CLAUDE.md settings.json settings.local.json)
        CONTEXT_FILE="CLAUDE.md"
        HAS_INSTALL=true
        ;;
    pi)
        CONFIG_DIR="${HPS_CONFIG_DIR:-$HOME/.pi/agent}"
        PROFILES_DIR="${HPS_PROFILES_DIR:-$HOME/.pi-agent-profiles}"
        MANAGED_ITEMS=(extensions skills prompts themes AGENTS.md settings.json)
        CONTEXT_FILE="AGENTS.md"
        HAS_INSTALL=false
        ;;
    *)
        echo "Unknown harness: $HARNESS (valid: claude, pi)"
        exit 1
        ;;
esac
```

### 2.2 cmd_create() change

```bash
cmd_create() {
    local name="$1"
    if [ -d "$PROFILES_DIR/$name" ]; then
        echo "Profile '$name' already exists."
        exit 1
    fi
    for item in "${MANAGED_ITEMS[@]}"; do
        if [[ "$item" != *.md && "$item" != *.json ]]; then
            mkdir -p "$PROFILES_DIR/$name/$item"
        fi
    done
    touch "$PROFILES_DIR/$name/$CONTEXT_FILE"
    echo "Created profile: $name"
    echo "  $PROFILES_DIR/$name/"
}
```

### 2.3 cmd_install() — pi no-op

```bash
cmd_install() {
    if [ "$HAS_INSTALL" != "true" ]; then
        echo "Profiles for '$HARNESS' harness don't use plugin installation."
        echo "Pi profiles: extensions, skills, prompts, themes are symlinked as files."
        echo "Pi auto-installs packages listed in settings.json on next startup."
        exit 0
    fi
    # ... existing claude plugin install logic ...
}
```

### 2.4 cmd_list() — harness-aware counting

For pi profiles: count `.ts`/`.js` files in `extensions/`, count subdirs in `skills/`, count `.md` in `prompts/`, count `.json` in `themes/`.

For claude profiles: count `.md` in `agents/`, count subdirs in `skills/` (unchanged).

### 2.5 env var renames

| Old env var | New env var | Notes |
|-------------|-------------|-------|
| `CCP_CLAUDE_DIR` | `HPS_CONFIG_DIR` | Overrides config dir |
| `CCP_PROFILES_DIR` | `HPS_PROFILES_DIR` | Overrides profiles dir |
| (none) | `HPS_HARNESS` | `claude` or `pi` |

Keep old env vars as fallbacks with deprecation warning for 2 releases.

### 2.6 Usage text update

Show harness-specific items. When harness=pi:
```
Managed items:
  extensions/  skills/  prompts/  themes/
  AGENTS.md  settings.json
```

When harness=claude: unchanged.

---

## Phase 3 — Test Suite Rename & Expansion (`test_hps.sh`)

### 3.1 Mechanical renames

- `$CCP` → `$HPS`
- `CCP_CLAUDE_DIR` → `HPS_CONFIG_DIR`
- `CCP_PROFILES_DIR` → `HPS_PROFILES_DIR`
- `TMPDIR_ROOT/claude` → `TMPDIR_ROOT/config`
- `TMPDIR_ROOT/profiles` → `TMPDIR_ROOT/profiles`
- `claude-code-profiles` string → `harness-profile-switcher`
- Every `CLAUDE.md` reference in test assertions becomes harness-aware (CLAUDE.md for claude, AGENTS.md for pi)

### 3.2 New test blocks (all paramaterized on harness)

| Test block | What it covers |
|------------|----------------|
| `test_pi_create` | `hps --harness pi create work` creates extensions/, skills/, prompts/, themes/, AGENTS.md |
| `test_pi_switch` | Switch between two pi profiles, verify extensions symlink repoints, AGENTS.md content changes |
| `test_pi_init_migration` | Init with existing `~/.pi/agent/` content migrates to `main` profile |
| `test_pi_safety` | Refuse to overwrite real `~/.pi/agent/extensions/` dir |
| `test_pi_list` | List shows extensions count, skills count, prompts count, themes count |
| `test_pi_install_noop` | `hps --harness pi install` prints "not applicable" |
| `test_pi_clone` | Clone copies all managed items |
| `test_pi_partial_items` | Profile with only `extensions/` — others skipped like claude's `minimal` test |
| `test_pi_harness_env` | `HPS_HARNESS=pi hps create` works |
| `test_default_claude` | Without `--harness`, defaults to claude (backward compat) |
| `test_harness_flag_override` | `--harness pi` overrides env `HPS_HARNESS=claude` |

### 3.3 Refactor existing tests

Keep all existing claude tests but switch to `--harness claude` explicitly where needed, or run them unchanged (they test the default harness which is claude).

### 3.4 Harness-aware assert helper

```bash
# Runs a test function for each harness in $HARNESSES
run_for_each_harness() {
    local test_func="$1"
    for h in $HARNESSES; do
        HPS_HARNESS="$h" reset_env
        "$test_func" "$h"
    done
}
```

Where `HARNESSES="claude pi"`.

---

## Phase 4 — install.sh Update

| Old | New |
|-----|-----|
| Downloads `ccp` | Downloads `hps` |
| Installs to `hps` | same |
| URL: `KakkoiDev/claude-code-profiles/main/ccp` | `KakkoiDev/harness-profile-switcher/main/hps` |
| Dependency check: `claude` CLI | Only check `claude` when installing for claude harness; skip for pi |
| Uninstall warns about `~/.claude-profiles` | Warn about `~/.harness-profiles` or both `~/.claude-profiles` and `~/.pi-agent-profiles` |

---

## Phase 5 — Docs Rewrite

### 5.1 README.md — full rewrite

- Title: `# harness-profile-switcher`
- Subtitle: "Switch Claude Code and pi coding agent configurations atomically"
- Two harness sections, parallel structure:
  - "With Claude Code" — explains `~/.claude/`, managed items, `claude plugin install`
  - "With pi" — explains `~/.pi/agent/`, managed items, no install phase, pi auto-installs packages
- "Why hps?" section grows to mention pi:
  - pi stores config in `~/.pi/agent/`, no built-in `--profile`, no context isolation
  - Neither Claude Code nor pi has built-in profile switching
- Installation: update URLs, mention `hps` binary name
- Usage: add `--harness pi` examples
  ```bash
  hps --harness pi create work
  hps --harness pi work
  hps --harness pi list
  ```
- How it works: show both directory trees side by side
  ```
  // Claude Code
  ~/.claude-profiles/work/{agents,skills,plugins,...}
  ~/.claude/* -> ~/.claude-profiles/work/*

  // pi
  ~/.pi-agent-profiles/work/{extensions,skills,prompts,themes,AGENTS.md,...}
  ~/.pi/agent/* -> ~/.pi-agent-profiles/work/*
  ```
- "With other tools": pi profiles versioned with git, pi packages in settings.json
- Environment: add `HPS_HARNESS`

### 5.2 CONTRIBUTING.md — update

- `claude-code-profiles` → `harness-profile-switcher`
- `test_ccp.sh` → `test_hps.sh`
- `ccp` → `hps`
- `CCP_CLAUDE_DIR` → `HPS_CONFIG_DIR`
- Add: "Testing with pi harness: `HPS_HARNESS=pi ./test_hps.sh`"
- Scope section: add pi-specific profile items
- Bug reports: `hps --version --harness pi`, `ls -la ~/.pi/agent ~/.pi-agent-profiles`

### 5.3 .gitignore — update

```
# Ignore all .md files by default
*.md

# Except these specific files
!README.md
!CONTRIBUTING.md
!PI-ADD-SUPPORT-PLAN.md

# Temporary files
*.tmp
*.log
.DS_Store

# Test scratch
/tmp/

# Backward compat symlink
ccp
```

---

## Phase 6 — Compatibility & Migration

### 6.1 Backward compatibility

- Default harness = `claude`. Existing users who just run `hps` (or `ccp`) get same behavior.
- Old env vars `CCP_CLAUDE_DIR` and `CCP_PROFILES_DIR` still work (with deprecation warning to stderr).
- `ccp` symlink in $PATH (created by install.sh) → points to `hps`. Print deprecation notice on stderr: "ccp is deprecated, use hps".

### 6.2 Migration path for existing ccp users

None needed. Old `~/.claude-profiles/` dir structure continues to work. The default harness is claude, same profiles dir, same items. No data migration. No breaking change.

### 6.3 Migration for pi users

Pi users start from scratch or point `HPS_CONFIG_DIR`/`HPS_PROFILES_DIR` to existing locations. First-time flow:

```bash
# Install hps
curl -fsSL https://raw.githubusercontent.com/KakkoiDev/harness-profile-switcher/main/install.sh | sh

# Create first pi profile (migrates existing ~/.pi/agent/ config)
hps --harness pi init            # moves current ~/.pi/agent/* into profile "main"

# Create additional profiles
hps --harness pi create work
hps --harness pi create personal

# Switch
hps --harness pi work
hps --harness pi current
```

---

## Phase 7 — Risks & Edge Cases

### 7.1 Pi skills loaded from multiple paths

Pi loads skills from 4 paths. Only `~/.pi/agent/skills/` is managed by hps. The other 3 (`~/.agents/skills/`, `.pi/skills/`, `.agents/skills/`) are project-level or user-level and unaffected by profile switching. **This is by design** — same as Claude Code's project-level `.claude/` not being touched.

Document this clearly: "hps manages only `~/.pi/agent/skills/`. Project-level `.pi/skills/` and `.agents/skills/` are unaffected."

### 7.2 Pi packages in settings.json

The symlinked `settings.json` contains the `packages` array. When switching to a profile that references packages not yet installed, pi auto-installs them on startup (after project trust). Nothing for hps to do. Document that new profiles with packages need one pi startup to auto-install.

### 7.3 `AGENTS.md` vs `CLAUDE.md` confusion

Pi reads both. `~/.pi/agent/AGENTS.md` is global, `./CLAUDE.md` and `./AGENTS.md` are project-level. hps manages the global one (`~/.pi/agent/AGENTS.md`). The project-level files are outside hps scope. Document this.

### 7.4 Pi extensions are TypeScript

Pi extensions are `.ts` (or `.js`) files. The `extensions/` dir in a profile contains raw files. No build step needed — pi loads them directly. But if an extension has npm dependencies, they need to be installed. This is outside hps scope, same as Claude Code plugins with dependencies.

### 7.5 `settings.local.json` does not exist in pi

Claude-specific item. Ignored when harness=pi. No migration path needed.

---

## Summary: What changes, what stays

| Element | Claude Code | pi |
|---------|-------------|-----|
| Config dir | `~/.claude/` | `~/.pi/agent/` |
| Profiles dir | `~/.claude-profiles/` | `~/.pi-agent-profiles/` |
| Managed items (dirs) | agents, skills, plugins, commands | extensions, skills, prompts, themes |
| Managed items (files) | CLAUDE.md, settings.json, settings.local.json | AGENTS.md, settings.json |
| Install command | `claude plugin install` | (none — no-op) |
| Context file | CLAUDE.md | AGENTS.md |
| Default state | Default harness | Explicit `--harness pi` |

**Unchanged across both:** symlink mechanism, safety checks, `create`/`clone`/`switch`/`list`/`current`/`init` commands, atomic guarantee, git compatibility.

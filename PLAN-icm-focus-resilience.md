# PLAN: ICM Focus Profile & Runtime Resilience

**Date:** 2026-06-12  
**Status:** Reviewed & corrected — ready for implementation  
**Reviewer:** Second agent (2026-06-12)  
**Context:** Discussion between human operator and coding agent about making
icm-runtime more resilient, improving the hps profile switcher, and building an
`icm-focus` Claude Code / pi profile.

**Note:** This plan was assessed after the PI-ADD-SUPPORT-PLAN was implemented.
The repo has been renamed to `harness-profile-switcher`, CLI is `hps` (not `ccp`),
and pi harness support is live. Corrections applied below.

---

## Table of Contents

1. [Vision Summary](#1-vision-summary)
2. [Current State](#2-current-state)
3. [Phase A: icm-runtime Resilience (repo: icm-runtime)](#3-phase-a-icm-runtime-resilience)
4. [Phase B: icm-focus Profile (repo: harness-profile-switcher)](#4-phase-b-icm-focus-profile)
5. [Phase C: Profile Switcher Improvements (repo: harness-profile-switcher)](#5-phase-c-profile-switcher-improvements)
6. [Phase D: Skill Auto-Audit (repo: icm-runtime)](#6-phase-d-skill-auto-audit)
7. [Phase E: Review-Agent-to-Skill Conversion](#7-phase-e-review-agent-to-skill-conversion)
8. [Implementation Order & Dependencies](#8-implementation-order--dependencies)
9. [Testing Strategy](#9-testing-strategy)

---

## 1. Vision Summary

**Goal:** A resilient ICM runtime where:

- Every ICM workflow is a **skill** (declarative, stage-based, with frozen contracts and deterministic tools).
- Every skill run is **fully observable**: token usage, model used, cost estimate, tool calls, stage durations — logged to project-level and global JSONL.
- Every skill is **auditable**: an auto-audit skill runs after each pipeline, flags deviations, and proposes human-reviewed improvements.
- Every tool call made by `icm.sh` is **logged** (args, cwd, exit code, stdout/stderr digest).
- A new `icm-focus` profile provides a **blank-slate** starting point with ICM conventions baked into its CLAUDE.md/AGENTS.md.
- The `hps` profile switcher ensures **complete profile isolation** and makes it easy to cross-reference missing skills from other profiles.

**Key principles (agreed after pushback):**

1. **Agents can become skills when they follow repeatable steps.** The review agent is a candidate for skill conversion — it always follows the same checks. Let the AI think freely within each step, but guarantee every step was executed.
2. **Haiku compatibility is not the target.** Determinism comes from shell scripts and gates. The model is glue between deterministic tools.
3. **Telemetry is JSONL, not OpenTelemetry.** Per-run logs live in `.icm/<ws>/<ts>/telemetry/`. Global aggregate lives at `~/.icm/telemetry/skill-runs.jsonl`.
4. **Auto-improvement means audit + report + human-reviewed proposal.** Never auto-apply changes.
5. **Skills are profile-scoped.** Shared skills will eventually live in a shared directory. For now, `icm` runtime skill is system-wide; workspace skills live in profiles.
6. **Missing skill tracking:** Each profile has a `MISSING_SKILLS.md` file where `hps audit` records which skills/agents/tools from other profiles should be adapted.

---

## 2. Current State

### icm-runtime repo (`~/Code/icm-runtime/`)

```
skills/
  icm/
    SKILL.md                      # internal-only skill, disable-model-invocation: true
    runtime/
      icm.sh                      # POSIX sh runtime (init, next, list, diff, stages, clean, gate-check, gate-status)
      gate-hook.sh                # Claude Code PreToolUse hook
      icm-gate.ts                 # pi tool_call extension
  jake-van-clief/
    ai-folder-research/
      SKILL.md                    # user-facing skill
      stages/
        01-research.md
        02-draft.md
        03-polish.md
installer.sh                       # symlink installer for ~/.agents/skills/ and ~/.claude/skills/
tests/
  gate.test.sh                     # 26 regression tests for gate enforcement
  pi-driver.ts                     # test harness for pi adapter
PLAN-gate-enforcement.md           # design record for gates (already implemented)
```

**Working features:**
- `icm.sh init` creates `.icm/<ws>/<ts>/<stage>/output/` and freezes stage contracts + checks
- `.manifest` file with sha256 hashes of frozen files → tamper evidence
- `<!-- ICM-GATE tools="..." run="..." -->` lines in stage contracts → runtime enforcement
- Gate enforcement adapters for both Claude Code (PreToolUse hook) and pi (tool_call extension)
- 26 tests passing

**Gaps (what this plan addresses):**
- No telemetry / observability
- No tool logging
- No `tools/` directory convention for deterministic scripts
- No audit command
- No auto-improvement skill
- No model/token tracking

### harness-profile-switcher repo (`~/Code/claude-code-profiles/` on disk, renamed from `claude-code-profiles`)

```
hps                                 # harness profile switcher v2.0.0 (bash + python3)
install.sh                          # installer (downloads hps, checks deps)
test_hps.sh                         # 80+ tests covering both harnesses
README.md, CONTRIBUTING.md          # updated for hps v2, pi harness
PI-ADD-SUPPORT-PLAN.md              # pi support plan (implemented — done)
LICENSE                             # MIT
```

**Working features (already implemented in hps v2.0.0):**
- Harness selection: `HPS_HARNESS` env var, `--harness claude|pi` flag, auto-detection
- Profile switching for Claude Code (`~/.claude/`): agents, skills, plugins, commands, CLAUDE.md, settings.json, settings.local.json
- Profile switching for pi (`~/.pi/agent/`): extensions, skills, prompts, themes, AGENTS.md, settings.json
- Commands: `hps <profile>`, `list`, `current`, `init`, `create`, `clone`, `install`
- Pi `install` no-ops with helpful message (no plugin system in pi)
- Deprecation warnings for old env vars (`CCP_CLAUDE_DIR`, `CCP_PROFILES_DIR`)
- `_is_file_item()` helper for distinguishing file items from dir items
- Atomic via symlinks, refuses to overwrite non-symlinks
- Safe migration from existing config

**NOT yet implemented (this plan covers):**
- `hps audit` command (Phase C.1)
- `hps audit --write-missing` (Phase C.2)
- ICM runtime detection in `hps install` (Phase C.3)
- Profile isolation audit (Phase C.5)

**Current profiles on disk:**
- `~/.claude-profiles/main/` — full profile with 15 agents, 23 skills, plugins, hooks, etc.
- `~/.claude-profiles/bare/` — only a CLAUDE.md
- No `icm-focus` profile yet

---

## 3. Phase A: icm-runtime Resilience

**Repo:** `~/Code/icm-runtime/`
**Goal:** Add observability, tool conventions, and audit capabilities to the ICM runtime.

### A.1 Tool Call Logging

Every `icm.sh` invocation must write a structured log entry.

**Implementation:**

Add a logging function in `icm.sh` (called at the top of main, before dispatch):

```bash
# Log every icm.sh invocation to project-local telemetry
ICM_TELEMETRY_DIR=".icm/telemetry"
ICM_LOG_FILE="$ICM_TELEMETRY_DIR/tool-calls.jsonl"

log_invocation() {
    [ -d "$ICM_TELEMETRY_DIR" ] || return 0  # only log if .icm/ exists (project has icm usage)
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local cwd="$PWD"
    local cmd_name="$1"; shift
    # Build JSON manually (no jq dependency in icm.sh)
    # Format: {"ts":"...","tool":"icm.sh","command":"init","args":["ai-folder-research"],"cwd":"...","pid":$$}
    printf '{"ts":"%s","tool":"icm.sh","command":"%s","args":%s,"cwd":"%s","pid":%s}\n' \
        "$ts" "$cmd_name" "$(printf '%s\n' "$@" | jq -R . | jq -s .)" "$cwd" "$$" \
        >> "$ICM_LOG_FILE" 2>/dev/null || true
}
```

Then at the end of every `cmd_*` function, log the exit code and stdout/stderr summary:

```bash
log_result() {
    [ -d "$ICM_TELEMETRY_DIR" ] || return 0
    local ts exit_code out_summary
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    exit_code=$1
    # Capture stdout/stderr from the run via a temp file or redirection wrapper
    # For simplicity, log the exit code only; tool output is in the run dir
    printf '{"ts":"%s","tool":"icm.sh","event":"result","exit_code":%s}\n' \
        "$ts" "$exit_code" >> "$ICM_LOG_FILE" 2>/dev/null || true
}
```

**Key design choices:**
- `icm.sh` remains **jq-free** (POSIX sh). Use `printf` for JSON construction with a proper escaping helper (see below).
- Log only when `.icm/telemetry/` exists (created by `cmd_init`). Don't pollute projects that don't use ICM.
- Each invocation writes **one line** at exit (timestamp, command, cwd, exit code). Duration is implicit (the log timestamp IS the exit time; compare with the `.icm/<ws>/<ts>/telemetry/run.json` `created` field for duration).

**JSON escaping helper (addresses concern #1 — printf brittle for special chars):**

```bash
# Escape a string for JSON string value (quotes, backslashes, control chars)
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}
```

**Recommended implementation:**

```bash
# At the top of main(), save original args for logging and capture start time
ORIGINAL_ARGS="$*"
MAIN_START=$(date -u +%s)

# json_escape() defined as above in the script's utility section

# At the end of main(), after dispatch, before exit:
if [ -d ".icm/telemetry" ]; then
    LOG_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ESCAPED_ARGS=$(json_escape "$ORIGINAL_ARGS")
    ESCAPED_CWD=$(json_escape "$PWD")
    printf '{"ts":"%s","tool":"icm.sh","command":"%s","args":"%s","cwd":"%s","exit_code":%s,"duration_s":%s}\n' \
        "$LOG_TS" "$1" "$ESCAPED_ARGS" "$ESCAPED_CWD" "$EXIT_CODE" "$(( $(date -u +%s) - MAIN_START ))" \
        >> "$LOG_FILE" 2>/dev/null || true
fi
```

**Why this fixes the brittleness:** The `json_escape()` function handles backslashes, double-quotes, tabs, newlines, and carriage returns. No jq dependency. `sed` is POSIX and available everywhere.

### A.2 Stage & Skill Telemetry

**Project-local** (in `.icm/<ws>/<ts>/telemetry/`):
- `run.json` — metadata about the run (workspace, timestamp, stages, model used)
- `stages.jsonl` — one line per stage with start/end timestamps, duration, tokens (if available)

**Global aggregate** (`~/.icm/telemetry/skill-runs.jsonl`):
- One line per completed ICM run with summary data
- Model info, token counts, cost estimate, duration, exit code

**Implementation in `cmd_init`:**

```bash
# After creating run_dir, create telemetry subdir:
mkdir -p "$run_dir/telemetry"

# Write run metadata
cat > "$run_dir/telemetry/run.json" <<EOF
{
  "workspace": "$ws",
  "run_id": "$ts",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stages": $(ls "$stages_dir"/*.md 2>/dev/null | wc -l | tr -d ' '),
  "cwd": "$PWD"
}
EOF
```

**Implementation for global aggregate:**

The global aggregate is written by the SKILL.md convention, NOT by `icm.sh` (since `icm.sh` doesn't know about models or tokens — that's harness-level info).

Add a new command to `icm.sh`:

```
icm.sh telemetry <workspace> --model <name> --tokens-in <N> --tokens-out <N> --cost <amount> [--cwd <dir>]
```

This writes one line to `~/.icm/telemetry/skill-runs.jsonl`. Workspace skills call it after completing a run.

```bash
cmd_telemetry() {
    ws=""; model=""; tokens_in=""; tokens_out=""; cost=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --tokens-in) tokens_in="$2"; shift 2 ;;
            --tokens-out) tokens_out="$2"; shift 2 ;;
            --cost) cost="$2"; shift 2 ;;
            --cwd) cd "$2"; shift 2 ;;
            *) ws="$1"; shift ;;
        esac
    done
    [ -n "$ws" ] || { echo "telemetry requires workspace name" >&2; exit 1; }
    local latest
    latest=$(latest_run "$ws")
    [ -n "$latest" ] || { echo "no runs for $ws" >&2; exit 1; }
    local ts="$latest"
    local global_dir="${HOME}/.icm/telemetry"
    mkdir -p "$global_dir"
    local global_file="$global_dir/skill-runs.jsonl"
    printf '{"ts":"%s","skill":"%s","run_id":"%s","model":"%s","tokens_in":%s,"tokens_out":%s,"cost_est":%s,"cwd":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ws" "$ts" "$model" "$tokens_in" "$tokens_out" "$cost" "$PWD" \
        >> "$global_file"
}
```

### A.3 Deterministic Tools Convention

Add a `tools/` directory to ICM skills, parallel to `stages/` and `checks/`.

**Convention:**

```
skills/namespace/skill-name/
  SKILL.md
  stages/           # stage contracts (existing)
    01-do-work.md
    02-publish.md
  checks/           # gate checker scripts (existing)
    verify.sh
  tools/            # NEW: deterministic stage tools
    search.sh       # wraps search_web, produces structured output
    analyze.sh      # processes inputs, produces analysis
    publish.sh      # validates and publishes output
```

**How skills use tools:**

A stage contract's process section says:

```markdown
## Process
1. Call `tools/search.sh "<query>"` to find sources
2. Based on search results, decide which URLs to fetch (AI decision point)
3. Call `tools/fetch.sh` for each chosen URL
4. Call `tools/synthesize.sh` to produce research-notes.md
5. Write output to `output/research-notes.md`
```

The model calls `bash <run_dir>/tools/search.sh "query"` instead of making raw `search_web` calls. The script:
- Is deterministic (same input → same output structure)
- Logs its own invocation
- Returns structured JSON/Markdown
- Fails with clear error messages

**Runtime support in `cmd_init`:**

```bash
# Freeze tools directory (like we freeze checks/)
if [ -d "$ws_dir/tools" ]; then
    cp -R "$ws_dir/tools" "$run_dir/tools"
    # Add tools/ to manifest for tamper evidence
    find tools -type f | sort | while IFS= read -r tf; do
        sha_file "$tf"
    done >> "$run_dir/.manifest"
fi
```

**Gate checkers can reference tools too** (same resolution as `checks/`):
```html
<!-- ICM-GATE tools="mcp__slack__send" run="tools/verify-before-send.sh" -->
```

### A.4 Audit Command

New `icm.sh` command: `audit <workspace> [--cwd <dir>]`

**What it does:**

1. Takes the latest completed run of a workspace
2. Reads each frozen stage contract
3. Extracts the expected tool calls from the Process section (via convention: `Call \`tools/...\`` lines)
4. Reads the actual tool calls from `.icm/telemetry/tool-calls.jsonl` (filtered by timestamp range)
5. Compares: expected vs actual
6. Produces a deviation report

**Output format:**

```
AUDIT: sprint-focus / 2026-06-12_09-15-00
==========================================

STAGE 04-send:
  EXPECTED: tools/check-preservation.sh
  ACTUAL:   NOT RUN
  SEVERITY: HIGH — gate was enforced but checker was skipped; gate denied on first attempt

STAGE 02-enrich:
  EXPECTED: tools/enrich-notion.sh
  ACTUAL:   bash tools/enrich-notion.sh --dry-run
  SEVERITY: LOW — script was run but with unexpected flag
```

Per-contract convention: a Process step that says `Call \`tools/X.sh\`` creates an audit expectation. Steps that say `Decide whether to...` or `Based on output...` are AI decision points and not audited.

**Implementation sketch:**

```bash
cmd_audit() {
    ws=$1
    latest=$(latest_run "$ws")
    [ -n "$latest" ] || { echo "no runs for $ws" >&2; exit 1; }
    run_dir=".icm/$ws/$latest"
    local telemetry=".icm/telemetry/tool-calls.jsonl"

    # Guard: telemetry must exist
    if [ ! -f "$telemetry" ]; then
        echo "ERROR: No telemetry available. Run 'icm.sh init' first to enable logging." >&2
        exit 2
    fi

    echo "AUDIT: $ws / $latest"
    echo "=========================================="
    echo ""

    # Get the run's time window from run.json
    local run_created=""
    [ -f "$run_dir/telemetry/run.json" ] && run_created=$(grep -o '"created":"[^"]*"' "$run_dir/telemetry/run.json" | head -1 | cut -d'"' -f4)
    local run_end=""
    # run_end = latest tool-call timestamp in tool-calls.jsonl within the run window
    if [ -n "$run_created" ]; then
        run_end=$(grep "$ws" "$telemetry" 2>/dev/null | tail -1 | grep -o '"ts":"[^"]*"' | cut -d'"' -f4)
    fi

    # Parse each frozen stage's process steps
    for stage_dir in "$run_dir"/[0-9]*/; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$stage_dir")
        ctx="$stage_dir/CONTEXT.md"
        [ -f "$ctx" ] || continue

        # Extract expected tool calls from Process section
        # Convention: lines matching "Call `tools/X.sh`" or "bash tools/X.sh"
        expected=$(grep -Eo '`?(bash )?tools/[^`" ]+`?' "$ctx" 2>/dev/null | tr -d '`' || true)

        if [ -n "$expected" ]; then
            echo "STAGE $stage_name:"
            printf '%s\n' "$expected" | while IFS= read -r tool; do
                local actual="NOT RUN"
                local severity="HIGH"
                # Look for this tool in telemetry within the run's time window
                if [ -n "$run_created" ] && [ -n "$run_end" ]; then
                    # Filter tool-calls.jsonl lines between run_created and run_end
                    # then grep for the tool name
                    local found
                    found=$(awk -v start="$run_created" -v end="$run_end" \
                        -v tool="$tool" \
                        'BEGIN { FS="\"" }
                         /"ts":/ { ts=$4 }
                         ts >= start && ts <= end && $0 ~ tool { print $0; exit }' \
                        "$telemetry" 2>/dev/null)
                    if [ -n "$found" ]; then
                        actual=$(echo "$found" | grep -o '"command":"[^"]*"' | cut -d'"' -f4)
                        severity="LOW"  # Tool was called; any deviation is args-level
                    fi
                fi
                echo "  EXPECTED: $tool"
                echo "  ACTUAL:   $actual"
                echo "  SEVERITY: $severity"
            done
            echo ""
        fi
    done

    echo "Audit complete. Use 'icm.sh telemetry' to add model/token info."
}
```

**How this fixes the placeholder:** The audit command now reads `tool-calls.jsonl` (produced by Phase A.1), filters lines within the run's time window, and matches tool names. If no telemetry exists, it exits with a clear error (exit code 2). The awk-based filter avoids jq dependency.

### A.5 Manifest Expansion

Currently `.manifest` hashes:
- `[0-9]*/CONTEXT.md` (stage contracts)
- `checks/*` (gate checker scripts)

Add to manifest:
- `tools/*` (deterministic scripts, see A.3)
- `telemetry/run.json` (run metadata, see A.2 — though this is written AFTER manifest, so include it only if run.json exists at manifest-write time; otherwise, gate-check should verify it separately or exclude it)

```bash
# In cmd_init, after writing tools:
if [ -d "$run_dir/tools" ]; then
    find "$run_dir/tools" -type f | sort | while IFS= read -r tf; do
        sha_file "$tf"
    done >> "$run_dir/.manifest"
fi
```

### A.6 Files Changed in Phase A

| File | Changes |
|------|---------|
| `skills/icm/runtime/icm.sh` | Add tool-call logging, `tools/` freezing, `telemetry` command, `audit` command, manifest expansion |
| `skills/icm/SKILL.md` | Document `telemetry` and `audit` commands, `tools/` convention |
| `README.md` | Document telemetry, tools convention, audit |
| `CHANGELOG.md` | New entry for 0.3.0 |
| `tests/gate.test.sh` | Add test cases for tool logging, tools freezing, manifest with tools, audit |
| `skills/jake-van-clief/ai-folder-research/` | Add `tools/` directory as reference implementation |
| `skills/jake-van-clief/ai-folder-research/SKILL.md` | Update to reference tools convention |
| `skills/jake-van-clief/ai-folder-research/stages/*.md` | Update Process sections to use tools convention |

---

## 4. Phase B: icm-focus Profile

**Repo:** `~/Code/claude-code-profiles/` (disk name; canonical: `harness-profile-switcher`) + `~/Code/icm-runtime/` (skill definitions)
**Goal:** Create a new profile that enforces ICM-first development.

### B.1 Profile Structure

```
~/.claude-profiles/icm-focus/
  CLAUDE.md                    # blank-slate ICM instructions
  settings.json                # model defaults, permissions
  settings.local.json          # empty or absent
  agents/                      # EMPTY - these will be skill-converted over time
  skills/                      # EMPTY (icm runtime is in ~/.agents/skills/, shared)
  plugins/                     # EMPTY
  commands/                    # EMPTY
  MISSING_SKILLS.md            # tracking file for skills to adapt from other profiles
```

### B.2 CLAUDE.md Content

```markdown
# ICM Focus Profile

You are operating in the **icm-focus** profile. This profile prioritizes
deterministic, auditable workflows over autonomous exploration.

## Core Rules

1. **Prefer skills over improvisation.** Every structured workflow should be an
   ICM skill with stages, frozen contracts, and verification gates.
2. **Use deterministic tools.** Every repeatable operation should be a shell
   script in a skill's `tools/` directory. The AI is the glue between scripts,
   making decisions only at explicit decision points.
3. **Log everything.** Every `icm.sh` invocation writes to `.icm/telemetry/`.
   Every completed run writes to `~/.icm/telemetry/skill-runs.jsonl`. Check
   telemetry after each run.
4. **Audit your own runs.** After completing an ICM pipeline, run
   `icm.sh audit <workspace>` and review the deviation report.
5. **When a workflow is repeated 3+ times, skill-ify it.** Create a new ICM
   skill with stages, checks, and tools.
6. **No agents.** This profile has an empty `agents/` directory. If you need
   an agent workflow, convert it to a skill or switch to another profile.

## Creating a New ICM Skill

1. Create a directory: `skills/<namespace>/<skill-name>/`
2. Create `SKILL.md` with frontmatter (name, description)
3. Create `stages/` with numbered `.md` contracts
4. Create `tools/` with deterministic shell scripts
5. Create `checks/` with gate verifier scripts
6. Test: run the skill, check telemetry, run audit

## ICM Runtime

The ICM runtime is installed globally at `~/.agents/skills/icm/runtime/icm.sh`.
All skills in this profile use it. Do not reinstall it.

## Observability

- Project-level telemetry: `.icm/telemetry/tool-calls.jsonl`
- Run-level telemetry: `.icm/<ws>/<ts>/telemetry/run.json`, `stages.jsonl`
- Global aggregate: `~/.icm/telemetry/skill-runs.jsonl`

After every skill run, call:
```bash
bash ~/.agents/skills/icm/runtime/icm.sh telemetry <workspace> \
  --model <current-model> --tokens-in <N> --tokens-out <N> --cost <amount>
```
```

### B.3 settings.json Content

```json
{
  "model": "claude-fable-5",
  "env": {
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  },
  "permissions": {
    "allow": [
      "Bash(bash ~/.agents/skills/icm/runtime/icm.sh *)",
      "Bash(find *)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(mv *)",
      "Bash(grep *)",
      "Bash(sed *)",
      "Bash(jq *)",
      "Bash(curl *)",
      "Bash(wc *)",
      "Bash(date *)",
      "Bash(echo *)",
      "Bash(which *)",
      "Bash(shellcheck *)",
      "Bash(command -v *)",
      "Bash(shasum *)",
      "Bash(sha256sum *)",
      "Bash(git *)"
    ]
  }
}
```

Keep permissions minimal. Add more as skills need them. Each new skill's SKILL.md should document required permissions.

### B.4 MISSING_SKILLS.md Template

```markdown
# Missing Skills — to adapt from other profiles

This file tracks agents/skills/tools that exist in other profiles and should
be adapted as ICM skills for this profile.

Format: `[ ] <source-profile>/<item-name> — <brief description> — <adaptation notes>`

## From `main` profile

[ ] main/review — Code review agent — always follows same steps (check PR requirements,
    security scan, architecture review, test coverage, style). Convert to ICM skill
    with stages: 01-ingest-pr → 02-requirements-check → 03-security-review →
    04-architecture-review → 05-test-coverage → 06-style → 07-publish-feedback.

[ ] main/web-bot — Web testing agent — bounded workflow that can be staged.

[ ] main/qa — QA agent — systematic checklist that maps well to ICM stages.

[ ] main/refine-tickets — Already an ICM skill! Should be symlinked/copied to this profile.

[ ] main/sprint-focus — Already an ICM skill! Should be symlinked/copied to this profile.

[ ] main/todo-triage — Already an ICM skill! Should be symlinked/copied to this profile.

[ ] main/routines-sync — Already an ICM skill! Should be symlinked/copied to this profile.

## From pi

[ ] (list pi-specific extensions/agents from ~/.pi/agent/extensions/ that should be skills)

## Adaptation Notes

- Review agent: largest conversion effort. Break into staged checks with tools/ for
  deterministic scanning (lint, test runs, security scanners). AI judgment only on the
  non-deterministic parts (architecture review, code style commentary).
- web-bot: can be an ICM skill with stages for navigation, capture, verification.
```

### B.5 Creating the Profile

```bash
# Create via hps (creates all managed items dirs + CLAUDE.md)
hps create icm-focus

# Then add the MISSING_SKILLS.md tracking file (not a managed item)
touch ~/.claude-profiles/icm-focus/MISSING_SKILLS.md

# Set default permissions (optional but recommended)
mkdir -p ~/.claude-profiles/icm-focus/settings.json
```

Then write the content from B.2 (CLAUDE.md), B.3 (settings.json), B.4 (MISSING_SKILLS.md).

**Alternative: pi harness variant**

```bash
hps --harness pi create icm-focus
# Creates: extensions/ skills/ prompts/ themes/ AGENTS.md settings.json
touch ~/.pi-agent-profiles/icm-focus/MISSING_SKILLS.md
# Then write B.2 content to AGENTS.md (not CLAUDE.md)
# settings.json uses pi schema, not claude schema
```

**DO NOT symlink or copy any agents/skills from main.** The icm-focus profile starts blank. Skills are added intentionally as they are needed or converted.

---

## 5. Phase C: Profile Switcher Improvements

**Repo:** `~/Code/claude-code-profiles/` (canonical: `harness-profile-switcher`)
**Goal:** Add profile auditing and skill cross-referencing to `hps`. Works for both Claude and pi harnesses.

### C.1 New Command: `hps audit <profile>`

Compares the target profile against all other profiles and reports:

1. **Skills present in other profiles but missing in target**
2. **Agents present in other profiles but missing in target** (candidates for skill conversion)
3. **Same-named items that differ** (potential drift)

**Output format (claude harness):**

```
hps audit icm-focus

hps audit icm-focus (harness: claude)

## From 'main' profile

### Skills
  refine-tickets          (ICM skill — can be copied)
  sprint-focus            (ICM skill — can be copied)
  todo-triage             (ICM skill — can be copied)
  routines-sync           (ICM skill — can be copied)
  ai-folder-research      (ICM skill — can be copied)
  skill-finalizer         (ICM skill — can be copied)

### Agents
  review                  (candidate for skill conversion)
  web-bot                 (candidate for skill conversion)
  qa                      (candidate for skill conversion)

### Plugins
  installed_plugins.json  (plugin — reinstall with hps install)

## Same items with differences
  (none — profiles are isolated)
```

**Output format (pi harness):**

```
hps --harness pi audit icm-focus

hps audit icm-focus (harness: pi)

## From 'main' profile

### Skills
  ai-folder-research      (ICM skill — can be copied)

### Extensions
  doom.ts                 (extension — candidate for skill conversion?)

### Prompts
  (none)

### Themes
  (none)
```

**Implementation:**

```bash
cmd_audit() {
    local profile="$1"
    local target_dir="$PROFILES_DIR/$profile"
    [ -d "$target_dir" ] || { echo "Profile '$profile' not found" >&2; exit 1; }

    echo "hps audit $profile (harness: $HARNESS)"
    echo ""

    for other in "$PROFILES_DIR"/*/; do
        [ -d "$other" ] || continue
        other_name=$(basename "$other")
        [ "$other_name" = "$profile" ] && continue

        echo "## From '$other_name' profile"
        echo ""

        # Only compare items valid for this harness
        case "$HARNESS" in
            claude)
                # Compare skills/
                if [ -d "$other/skills" ] && [ -d "$target_dir/skills" ]; then
                    local missing_skills=""
                    for skill in "$other/skills"/*/; do
                        [ -d "$skill" ] || continue
                        sname=$(basename "$skill")
                        if [ ! -e "$target_dir/skills/$sname" ]; then
                            local is_icm=""; [ -f "$skill/SKILL.md" ] && is_icm=" (ICM skill — can be copied)" || is_icm=""
                            missing_skills="$missing_skills  $sname$is_icm\n"
                        fi
                    done
                    if [ -n "$missing_skills" ]; then
                        echo "### Skills"
                        printf '%b' "$missing_skills"
                        echo ""
                    fi
                fi

                # Compare agents/ (claude only)
                if [ -d "$other/agents" ] && [ -d "$target_dir/agents" ]; then
                    local missing_agents=""
                    for agent in "$other/agents"/*.md; do
                        [ -f "$agent" ] || continue
                        aname=$(basename "$agent" .md)
                        if [ ! -f "$target_dir/agents/$aname.md" ]; then
                            missing_agents="$missing_agents  $aname (candidate for skill conversion)\n"
                        fi
                    done
                    if [ -n "$missing_agents" ]; then
                        echo "### Agents"
                        printf '%b' "$missing_agents"
                        echo ""
                    fi
                fi

                # Compare plugins/ (claude only)
                if [ -d "$other/plugins" ] && [ -d "$target_dir/plugins" ]; then
                    local missing_plugins=""
                    for plugin_json in "$other/plugins"/*.json; do
                        [ -f "$plugin_json" ] || continue
                        pname=$(basename "$plugin_json")
                        if [ ! -f "$target_dir/plugins/$pname" ]; then
                            missing_plugins="$missing_plugins  $pname (plugin — reinstall with hps install)\n"
                        fi
                    done
                    if [ -n "$missing_plugins" ]; then
                        echo "### Plugins"
                        printf '%b' "$missing_plugins"
                        echo ""
                    fi
                fi
                ;;

            pi)
                # Compare skills/
                if [ -d "$other/skills" ] && [ -d "$target_dir/skills" ]; then
                    local missing_skills=""
                    for skill in "$other/skills"/*/; do
                        [ -d "$skill" ] || continue
                        sname=$(basename "$skill")
                        if [ ! -e "$target_dir/skills/$sname" ]; then
                            local is_icm=""; [ -f "$skill/SKILL.md" ] && is_icm=" (ICM skill — can be copied)" || is_icm=""
                            missing_skills="$missing_skills  $sname$is_icm\n"
                        fi
                    done
                    if [ -n "$missing_skills" ]; then
                        echo "### Skills"
                        printf '%b' "$missing_skills"
                        echo ""
                    fi
                fi

                # Compare extensions/ (pi only — no agents dir)
                if [ -d "$other/extensions" ] && [ -d "$target_dir/extensions" ]; then
                    local missing_ext=""
                    for ext in "$other/extensions"/*.ts "$other/extensions"/*.js; do
                        [ -f "$ext" ] 2>/dev/null || continue
                        ename=$(basename "$ext")
                        if [ ! -f "$target_dir/extensions/$ename" ]; then
                            missing_ext="$missing_ext  $ename (extension — candidate for skill conversion?)\n"
                        fi
                    done
                    if [ -n "$missing_ext" ]; then
                        echo "### Extensions"
                        printf '%b' "$missing_ext"
                        echo ""
                    fi
                fi

                # Compare prompts/ (pi only)
                if [ -d "$other/prompts" ] && [ -d "$target_dir/prompts" ]; then
                    local missing_prompts=""
                    for prompt in "$other/prompts"/*.md; do
                        [ -f "$prompt" ] 2>/dev/null || continue
                        pname=$(basename "$prompt")
                        if [ ! -f "$target_dir/prompts/$pname" ]; then
                            missing_prompts="$missing_prompts  $pname (prompt template — can be copied)\n"
                        fi
                    done
                    if [ -n "$missing_prompts" ]; then
                        echo "### Prompts"
                        printf '%b' "$missing_prompts"
                        echo ""
                    fi
                fi

                # Compare themes/ (pi only)
                if [ -d "$other/themes" ] && [ -d "$target_dir/themes" ]; then
                    local missing_themes=""
                    for theme in "$other/themes"/*.json; do
                        [ -f "$theme" ] 2>/dev/null || continue
                        tname=$(basename "$theme")
                        if [ ! -f "$target_dir/themes/$tname" ]; then
                            missing_themes="$missing_themes  $tname (theme — can be copied)\n"
                        fi
                    done
                    if [ -n "$missing_themes" ]; then
                        echo "### Themes"
                        printf '%b' "$missing_themes"
                        echo ""
                    fi
                fi
                ;;
        esac
    done

    echo "Run 'hps audit $profile --write-missing' to generate MISSING_SKILLS.md"
}
```

### C.2 `hps audit --write-missing`

Writes the audit results to `<profile>/MISSING_SKILLS.md`:

```bash
cmd_audit_write() {
    local profile="$1"
    local target_dir="$PROFILES_DIR/$profile"
    local outfile="$target_dir/MISSING_SKILLS.md"

    # Generate header + audit results into MISSING_SKILLS.md
    # (same logic as cmd_audit but writes to file)
    # Preserve any existing manual notes (lines after "## Adaptation Notes")
    # by reading them before overwriting and appending after the generated content
}
```

### C.3 `hps install` Support for ICM Skills

Currently `hps install` only handles Claude Code plugins (pi harness no-ops). For the icm-focus profile (claude harness), add ICM runtime detection:

When a profile has ICM skills (detected by `SKILL.md` with ICM frontmatter in `$PROFILES_DIR/<profile>/skills/`), `hps install` should additionally:

1. Check if `~/Code/icm-runtime/installer.sh` exists
2. If yes, run it to symlink the icm runtime into `~/.agents/skills/`
3. Report: "ICM runtime installed" or "ICM runtime installer not found"

**Rationale:** The ICM runtime should be system-wide, not per-profile. `~/.agents/skills/icm/` is shared. Workspace skills (sprint-focus, etc.) live in the profile's `skills/` directory and are symlink-managed. `hps install` for ICM ensures the runtime is available.

**Pi harness note:** `hps --harness pi install` already no-ops with a helpful message. No ICM-specific logic needed for pi.

### C.4 Files Changed in Phase C

| File | Changes |
|------|---------|
| `hps` | Add `audit` command (harness-aware), `--write-missing` flag, `audit` case in main dispatch |
| `test_hps.sh` | Add tests: `audit` claude, `audit --harness pi`, `audit --write-missing`, audit with empty target, audit with single profile |
| `README.md` | Document `audit` command, `MISSING_SKILLS.md` convention |
| `CONTRIBUTING.md` | Add ICM-specific scope note, pi audit test instructions |

**Note:** `hps` already uses `$CONFIG_DIR` and `$PROFILES_DIR` (not `$CLAUDE_DIR`). No variable renaming needed for this phase.

### C.5 Profile Isolation Audit

Add an integrity check to `hps init` and `hps <profile>`:

- Verify that each managed item in `$CONFIG_DIR/` is a symlink (not a real file/dir)
- Verify that each symlink points into `$PROFILES_DIR/<profile>/` (correct profile)
- **Claude harness:** warn if orphaned items (non-managed) exist in `~/.claude/`
- **Pi harness:** warn if orphaned items exist in `~/.pi/agent/`
- Report if two profiles accidentally share content (same symlink target for different profiles)

**Pi-specific check:** Pi loads skills from 4 paths. The isolation audit should note if
`~/.agents/skills/` or project-level `.pi/skills/` contain items that shadow or conflict
with profile-managed skills in `~/.pi/agent/skills/`.

This is a safety net for the "every profile should be isolated" requirement.

---

## 6. Phase D: Skill Auto-Audit

**Repo:** `~/Code/icm-runtime/` (as a new workspace skill)
**Goal:** An ICM skill that audits completed ICM runs and proposes improvements.

**Pre-condition gate (addresses concern #3):** The skill-auditor requires Phase A.1-A.5 to be complete.
Stage 01 checks for required telemetry at startup and fails fast with a clear message if missing:

```markdown
## Pre-flight Checks

1. `.icm/telemetry/tool-calls.jsonl` must exist (Phase A.1)
2. `.icm/<ws>/<ts>/telemetry/run.json` must exist for the target run (Phase A.2)
3. `tools/` directories must be present in the skill source (Phase A.3)
4. `icm.sh audit` must be functional (Phase A.4)
5. `.manifest` must include `tools/*` and `telemetry/run.json` hashes (Phase A.5)

If any check fails, Stage 01 outputs a `BLOCKED.md` with the missing dependency and exits.
```

**Fallback mode:** If telemetry is partial (e.g., tool-calls.jsonl exists but run.json doesn't),
the skill-auditor runs in reduced mode — only comparing stage contracts against tool calls,
skipping model/token/cost analysis. The output notes "PARTIAL AUDIT — full telemetry not available."

### D.1 The `skill-auditor` ICM Skill

```
skills/icm/skill-auditor/
  SKILL.md
  stages/
    01-ingest-run.md       # Load the latest completed run, read telemetry
    02-verify-behavior.md   # Compare model behavior against stage contract
    03-flag-deviations.md   # Produce a structured deviation report
    04-propose-fixes.md     # Generate improvement proposals (diffs)
  checks/
    verify-audit.sh         # Gate: was the audit report written? are all deviations documented?
  tools/
    compare-tool-calls.sh   # Diff expected vs actual tool calls
    estimate-improvement.sh # Quantify potential improvement
```

### D.2 Stage 01: Ingest Run

```
# Stage 01: Ingest Completed Run

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| User-specified workspace | Chat message | Which workspace to audit |
| Run telemetry | `.icm/<ws>/<ts>/telemetry/` | Run metadata, tool calls |
| Stage contracts | `.icm/<ws>/<ts>/*/CONTEXT.md` | Frozen expectations |
| Tool call log | `.icm/telemetry/tool-calls.jsonl` | Actual tool invocations |

## Process
1. Identify the workspace to audit (from user input or default to latest modified workspace)
2. Call `icm.sh list <workspace>` to find the latest completed run
3. Read `telemetry/run.json` for metadata
4. Read `telemetry/tool-calls.jsonl` for all tool invocations during the run
5. Read each stage's `CONTEXT.md` and `output/` to understand what was expected
6. Write a consolidated `output/ingest-summary.md` with all gathered data

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Ingest summary | output/ingest-summary.md | Structured: workspace, run_id, stages, tool calls, model info |
```

### D.3 Stage 02: Verify Behavior

```
# Stage 02: Verify Behavior

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Ingest summary | ../01-ingest-run/output/ingest-summary.md | All run data |
| Stage contracts | `.icm/<ws>/<ts>/*/CONTEXT.md` | Expected process |

## Process
1. For each stage, parse the Process section for expected tool calls (convention: `Call \`tools/X.sh\``)
2. Compare expected tool calls against actual tool calls from telemetry
3. Note: tool calls not matching the convention (raw search_web, fetch_url, etc.) are flagged
4. Check if gate-enforced steps were satisfied
5. Write verification report

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Verification report | output/verification.md | Stage-by-stage: expected vs actual, passed/failed |
```

### D.4 Stage 03: Flag Deviations

```
# Stage 03: Flag Deviations

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Verification report | ../02-verify-behavior/output/verification.md | Expected vs actual |

## Process
1. Categorize each deviation:
   - SKIP: step wasn't executed at all
   - PARTIAL: step was executed but with different args/behavior
   - EXTRA: tool was called that wasn't expected
   - ORDER: steps executed in wrong order
2. Assign severity: BLOCKING (gate-relevant), HIGH (materially different output), LOW (cosmetic)
3. Write structured deviation report

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Deviation report | output/deviations.md | Table: stage, step, expected, actual, severity, evidence |
```

### D.5 Stage 04: Propose Fixes

```
# Stage 04: Propose Fixes

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Deviation report | ../03-flag-deviations/output/deviations.md | Categorized deviations |
| Source skill | `skills/<ws>/` | The live skill files (not the frozen ones) |

## Process
1. For each HIGH or BLOCKING deviation, propose a fix to the skill source:
   - Missing step → add to Process section
   - Wrong tool → correct the instruction
   - Missing tool → suggest creating a new tools/ script
2. Generate a unified diff for each proposed change
3. Write the proposal as a human-reviewable document
4. DO NOT apply any changes. This stage only proposes.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Improvement proposal | output/proposal.md | For each deviation: problem, proposed fix, diff, rationale |
```

### D.6 Gate: Human Review Required

The Stage 04 contract includes a gate:

```html
<!-- ICM-GATE tools="mcp__claude_ai_Slack__slack_send_message" run="grep -Eq '^STATUS: REVIEW_NEEDED$' output/proposal.md" -->
```

This prevents the agent from auto-applying fixes or publishing results without human review. The proposal.md file must contain `STATUS: REVIEW_NEEDED` as a final gate before any publish action.

### D.7 Post-Audit: Manual Application

The human reviews `output/proposal.md` and decides which fixes to apply. The agent can then apply them with `/skill-auditor apply` (a separate invocation that takes the reviewed proposal and applies the accepted diffs).

### D.8 `skill-auditor` Registration

Add to `icm-runtime/skills/icm/skill-auditor/` (namespaced under `icm/` since it's infrastructure, not a user-facing workflow).

---

## 7. Phase E: Review-Agent-to-Skill Conversion

**Repo:** Depends on where the review agent lives (currently `~/.claude-profiles/main/agents/review.md`)
**Goal:** Convert the `review` agent into an ICM skill with deterministic stages.

### E.1 Analysis: What the Review Agent Does

The review agent (from `~/.claude-profiles/main/agents/review.md`, 11705 bytes) is an agent-based workflow. It performs:

1. Ingest PR diff and metadata
2. Check PR answers requirements
3. Check for security risks
4. Architecture review
5. Test coverage assessment
6. Code style / conventions check
7. Publish feedback (via GitHub PR review or similar)

**These are all repeatable steps.** Every review follows this structure. It should be an ICM skill.

### E.2 ICM Skill Design: `code-review`

```
skills/code-review/
  SKILL.md
  stages/
    01-ingest.md          # Fetch PR diff, metadata, linked issues
    02-requirements.md    # Check PR against requirements/AC
    03-security.md        # Security scan (static analysis tools)
    04-architecture.md    # Architecture review (AI judgment zone)
    05-testing.md         # Test coverage, test quality
    06-style.md           # Code style, conventions, naming
    07-publish.md         # Compile report + publish to GitHub
  checks/
    verify-report.sh      # Gate: report is non-empty, all sections filled
  tools/
    fetch-pr.sh           # gh pr view/diff → structured output
    lint.sh               # Run project's linter, capture output
    security-scan.sh      # Run security scanner, capture output
    test-coverage.sh      # Run tests + coverage, capture output
    compile-report.sh     # Compile all stage outputs into final report
    publish-review.sh     # Post review to GitHub via gh pr review
```

### E.3 Stage Contracts (Short Form)

**Stage 01 - Ingest:**
```
Process:
1. Call tools/fetch-pr.sh with the PR number from user input
2. Read output/pr-data.json for PR metadata, diff, linked issues
3. Write summary to output/ingest-summary.md
```

**Stage 02 - Requirements:**
```
Process:
1. Read ../01-ingest/output/pr-data.json
2. Extract requirements/AC from linked issues
3. AI analysis: does the diff satisfy each requirement?
4. Write findings to output/requirements-check.md
```

**Stage 03 - Security:**
```
Process:
1. Call tools/security-scan.sh on the diff files
2. AI analysis: review tool output + manual patterns
3. Write findings to output/security-review.md
```

**Stage 04 - Architecture:**
```
Process:
1. Read the full diff context
2. AI analysis: does this change fit the architecture? any design issues?
3. Write findings to output/architecture-review.md
```

**Stage 05 - Testing:**
```
Process:
1. Call tools/test-coverage.sh
2. AI analysis: test quality, edge cases, regression coverage
3. Write findings to output/testing-review.md
```

**Stage 06 - Style:**
```
Process:
1. Call tools/lint.sh
2. AI analysis: naming, conventions, readability
3. Write findings to output/style-review.md
```

**Stage 07 - Publish:**
```
Process:
1. Call tools/compile-report.sh (merges all stage outputs)
2. Call tools/publish-review.sh (posts to GitHub)
3. Write confirmation to output/publish-result.md

<!-- ICM-GATE tools="gh pr review|gh api" run="checks/verify-report.sh" -->
```

### E.4 Deterministic vs AI Zones

| Stage | Deterministic (tools/) | AI Judgment |
|-------|------------------------|-------------|
| 01-ingest | `fetch-pr.sh` | None (pure ingestion) |
| 02-requirements | None | Requirement interpretation, diff analysis |
| 03-security | `security-scan.sh` | Reviewing scanner output, pattern recognition |
| 04-architecture | None | Pure AI judgment |
| 05-testing | `test-coverage.sh` | Test quality assessment |
| 06-style | `lint.sh` | Style commentary |
| 07-publish | `compile-report.sh`, `publish-review.sh` | None (compilation + publish) |

The AI thinks freely at each stage but is constrained to the stage's scope. The gates and tools ensure no step is skipped.

### E.5 Where This Lives

The `code-review` skill should live in `skills/` inside the profile that uses it. For the `icm-focus` profile, that's `~/.claude-profiles/icm-focus/skills/code-review/`. For the `main` profile, it could replace the `agents/review.md` file (keeping the original as `agents-archive/review.md`).

**Implementation note:** This conversion is the largest piece of work. It can be done incrementally — start with stages 01+07 (ingest + publish) and add the analysis stages one at a time.

**Installer update (addresses concern #4):** Phase E must also update `~/Code/icm-runtime/installer.sh`:

```diff
+# Symlink code-review skill if present
+if [ -d "$SCRIPT_DIR/skills/code-review" ]; then
+    mkdir -p "$HOME/.agents/skills/code-review"
+    ln -sfn "$SCRIPT_DIR/skills/code-review" "$HOME/.agents/skills/code-review"
+    echo "  code-review -> ~/.agents/skills/code-review"
+fi
```

And update `PLAN-gate-enforcement.md` to list `code-review` as a registered skill.

**Files changed in Phase E (expanded):**

| File | Changes |
|------|---------|
| `skills/code-review/` (new) | SKILL.md + 7 stage contracts + 2 checks + 6 tools |
| `installer.sh` | Add `code-review` symlink block |
| `PLAN-gate-enforcement.md` | Register `code-review` skill |
| `README.md` | Document `code-review` in skill list |
| `CHANGELOG.md` | Entry for new skill |

---

## 8. Phase F: Pi ICM Profile (Future)

**Status:** Not in current scope. Documented for completeness.
**Repo:** `~/Code/claude-code-profiles/` (profile content) + `~/Code/icm-runtime/` (gate adapter)

### F.1 What's Different for Pi

| Aspect | Claude Code ICM | Pi ICM |
|--------|----------------|--------|
| Global context file | `CLAUDE.md` | `AGENTS.md` (at `~/.pi/agent/AGENTS.md`) |
| Skill storage | `~/.claude/skills/` | `~/.pi/agent/skills/` (profile-managed) + `~/.agents/skills/` (shared) |
| Agent dir | `agents/` | No equivalent — use `extensions/` for programmatic tools |
| Gate enforcement | `gate-hook.sh` (Claude Code PreToolUse hook) | `icm-gate.ts` (pi `tool_call` event hook) |
| Plugin install | `claude plugin install` | No equivalent — extensions are symlinked `.ts` files |
| Settings schema | Claude Code settings.json format | Pi settings.json format (different keys) |
| ICM tool to restrict | `Bash` | `bash` (lowercase in pi) |

### F.2 Required Changes (when this phase activates)

1. **Create pi icm-focus profile:**
   ```bash
   hps --harness pi create icm-focus
   touch ~/.pi-agent-profiles/icm-focus/MISSING_SKILLS.md
   # Write AGENTS.md (adapted from B.2 above, replacing CLAUDE.md references)
   # Write pi-format settings.json (no claude-specific keys)
   ```

2. **Update icm-gate.ts** to be profile-aware (read gate config from profile dir not cwd).

3. **Update `hps audit` for pi** — already designed in Phase C above, just needs
   the pi profile to exist to test against.

4. **Add pi-format CLAUDE.md/AGENTS.md** to the icm-focus profile documentation.

5. **Test `icm.sh` under pi** — pi's `bash` tool has the same semantics but the tool
   name is lowercase. The gate adapter already handles this (icm-gate.ts exists).
   Run the full gate test suite with `pi-driver.ts`.

### F.3 When to Activate

- After Phase E is complete and `code-review` skill is stable
- After the pi harness has been battle-tested with at least one real pi profile
- When a pi user wants ICM workflows (demand-driven, not speculative)

---

## 8. Implementation Order & Dependencies

```
Phase A.1 (tool logging)
  └─→ Phase A.2 (telemetry)
       └─→ Phase A.3 (tools convention)
            └─→ Phase A.4 (audit command)
                 └─→ Phase A.5 (manifest expansion)
                      └─→ Phase D (skill-auditor skill)

Phase B (icm-focus profile) — can start in parallel with Phase A
  └─→ Phase C (hps audit) — needs Phase B profile to test against
       └─→ Phase C.5 (isolation audit)

Phase E (review→skill) — can start in parallel with everything
```

### Recommended Sprint Order

**Sprint 1:** Phase A.1 + A.2 (tool logging + telemetry)  
**Sprint 2:** Phase A.3 + A.5 (tools convention + manifest expansion)  
**Sprint 3:** Phase A.4 (audit command) + Phase B (icm-focus profile)  
**Sprint 4:** Phase C (hps improvements) + Phase C.5 (isolation audit)  
**Sprint 5:** Phase D (skill-auditor skill)  
**Sprint 6:** Phase E (review agent conversion)  
**Future:** Phase F (pi ICM profile) — activate when demand exists

Each sprint is independently testable and deployable.

---

## 9. Testing Strategy

### icm-runtime Tests

For each Phase A change, add test cases to `tests/gate.test.sh`:

| Feature | Test Cases |
|---------|------------|
| Tool logging | `icm.sh init` creates `.icm/telemetry/`; `tool-calls.jsonl` gets lines; exit code recorded |
| Telemetry | Global `~/.icm/telemetry/skill-runs.jsonl` is append-only; `run.json` has correct structure |
| Tools freezing | `tools/` dir copied into run; tools added to manifest; tamper detection covers tools |
| Audit | Audit on completed run produces report; audit on no-telemetry run warns; audit on incomplete run handles gracefully |
| Manifest | Tools in manifest; tampered tool → deny; missing tool → deny |

### hps Tests

Add to `test_hps.sh`:

| Feature | Test Cases |
|---------|------------|
| `hps audit` (claude) | Lists missing skills/agents/plugins from other profiles; handles empty target; handles single-profile setup |
| `hps --harness pi audit` | Lists missing skills/extensions/prompts/themes from other profiles; handles empty target |
| `hps audit --write-missing` | Generates MISSING_SKILLS.md; preserves manual notes; idempotent |
| `hps audit` across harnesses | `hps audit` on claude profile from pi harness context (reports harness mismatch or warns) |
| ICM install | `hps install` for icm-focus profile runs icm-runtime installer (claude harness only) |
| Isolation (claude) | Refuse to switch if managed items are not symlinks; warn on orphaned files in `~/.claude/`; detect cross-profile sharing |
| Isolation (pi) | Same for `~/.pi/agent/`; warn if `~/.agents/skills/` items shadow profile skills |

### skill-auditor Tests

Create `tests/skill-auditor.test.sh`:

| Feature | Test Cases |
|---------|------------|
| Full pipeline | Run skill-auditor on a known-bad run; verify deviations flagged |
| No deviations | Run on a clean run; verify "no issues found" |
| Human gate | Verify gate blocks publish without REVIEW_NEEDED status |
| Proposal format | Verify diff format in proposal.md is apply-able |

---

## Appendix: Key Design Decisions Log

| Decision | Rationale |
|----------|-----------|
| JSONL not OTel | OTel is distributed tracing for microservices; JSONL is simpler, sufficient for local CLI |
| `icm.sh` stays jq-free | POSIX sh compatibility; JSON via printf is fragile but workable for simple structures |
| Telemetry at project level (`.icm/`) + global aggregate (`~/.icm/`) | Project-level for run context; global for cross-project searchability |
| `tools/` convention separate from `checks/` | `tools/` = stage execution helpers; `checks/` = gate verification. Different lifecycles |
| Auto-audit never auto-applies | Human review is the safety net against AI-generated skill drift |
| `icm-focus` profile is blank-slate | Intentional: skills are added deliberately, not inherited from `main` |
| `MISSING_SKILLS.md` as profile-level file | Lightweight tracking; no database or config format needed |
| Review agent conversion is Phase E (last) | Largest scope; depends on tools convention and audit being stable first |

---

## Reviewer's Assessment (second agent, 2026-06-12)

**Overall verdict: Solid plan, corrected for naming drift and pi harness gaps.**

### What was corrected

| Issue | Fix applied |
|-------|-------------|
| Repo name `claude-code-profiles` throughout | Updated to `harness-profile-switcher` (disk dir still old name) |
| CLI name `ccp` in various spots | Already resolved — `hps` v2.0.0 is live |
| Env var `CCP_CLAUDE_DIR` / `CCP_PROFILES_DIR` | Noted as already deprecated in hps v2, warned if used |
| `$CLAUDE_DIR` variable references | Verified: hps v2 uses `$CONFIG_DIR` already |
| Phase B manual profile creation | Replaced with `hps create` (it works), added pi variant |
| Phase C audit only claude-centric | Added full pi harness audit (extensions, prompts, themes) |
| Phase C.3 ICM install | Clarified pi no-ops, ICM runtime detection is claude-only |
| Phase C.5 isolation audit | Added pi-specific checks (shadowed skills from 4 paths) |
| Test matrix | Added pi harness test variants for audit and isolation |
| Current state section | Updated to reflect hps v2.0.0 already-implemented features |

### What the plan does well

- **Clear dependency graph** between phases A-E with no circular deps
- **Realistic sprint order** — each sprint independently testable/deployable
- **Deterministic-first design** — tools/ convention, not just AI freedom
- **Human review gate** — auto-audit proposes, never applies
- **Blank-slate profile** — icm-focus starts empty, skills added intentionally
- **JSONL not OTel** — right call for local CLI observability
- **Review agent → skill conversion** (Phase E) is well-structured into 7 ICM stages

### Concerns addressed (second pass, 2026-06-12)

| # | Concern | Fix applied |
|---|---------|-------------|
| 1 | Phase A.1 JSON via `printf` brittle | Added `json_escape()` helper (sed-based, POSIX, handles \ " \t \n \r). Logging code updated. |
| 2 | Phase A.4 audit has placeholder | Replaced with real `tool-calls.jsonl` lookup: awk-based time-window filter, tool name matching, severity tagging. Exits code 2 if no telemetry. |
| 3 | Phase D depends on A.1-A.5 being complete | Added pre-condition gate in Stage 01 (fails fast with BLOCKED.md). Added partial-audit fallback mode for incomplete telemetry. |
| 4 | Phase E code-review not in installer | Added installer.sh update diff to E.5. Added files-changed table for Phase E. |
| 5 | No pi ICM profile path | Added Phase F: documents Claude vs pi differences, required changes, and activation criteria. |

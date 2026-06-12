#!/usr/bin/env bash
set -euo pipefail

HPS="$(cd "$(dirname "$0")" && pwd)/hps"
PASS=0
FAIL=0
TESTS=()

# Harnesses to test
HARNESSES="claude pi"

# ── Per-harness config helpers ────────────────────────────────

_config_dir() {
    case "$1" in claude) echo "$TMPDIR_ROOT/config_claude" ;; pi) echo "$TMPDIR_ROOT/config_pi" ;; esac
}

_profiles_dir() {
    case "$1" in claude) echo "$TMPDIR_ROOT/profiles_claude" ;; pi) echo "$TMPDIR_ROOT/profiles_pi" ;; esac
}

_managed_dirs() {
    case "$1" in
        claude) echo "agents skills plugins commands" ;;
        pi)     echo "extensions skills prompts themes" ;;
    esac
}

_context_file() {
    case "$1" in claude) echo "CLAUDE.md" ;; pi) echo "AGENTS.md" ;; esac
}

# Example non-context managed file(s) to check in tests
_settings_files() {
    case "$1" in
        claude) echo "settings.json settings.local.json" ;;
        pi)     echo "settings.json" ;;
    esac
}

_harness_flag() {
    echo "--harness $1"
}

# ── Bootstrap ─────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)

cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

reset_env() {
    local h="${1:-}"
    rm -rf "$TMPDIR_ROOT"
    mkdir -p "$TMPDIR_ROOT"
    if [ -n "$h" ]; then
        mkdir -p "$(_config_dir "$h")"
        mkdir -p "$(_profiles_dir "$h")"
    fi
}

# Wrapper: run hps with harness + env overrides
hps_with() {
    local h="$1"; shift
    HPS_CONFIG_DIR="$(_config_dir "$h")" \
    HPS_PROFILES_DIR="$(_profiles_dir "$h")" \
        "$HPS" --harness "$h" "$@"
}

# ── Assert helpers ────────────────────────────────────────────

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label")
    else
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label")
        TESTS+=("        expected: $expected")
        TESTS+=("        actual:   $actual")
    fi
}

assert_ok() {
    local label="$1"
    shift
    if env "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label")
    else
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (exit code $?)")
    fi
}

assert_fail() {
    local label="$1"
    shift
    if env "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (expected failure, got success)")
    else
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label (correctly failed)")
    fi
}

assert_symlink() {
    local label="$1" path="$2" expected_target="$3"
    if [ -L "$path" ]; then
        local actual
        actual=$(readlink "$path")
        assert_eq "$label" "$expected_target" "$actual"
    else
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (not a symlink: $path)")
    fi
}

assert_exists() {
    local label="$1" path="$2"
    if [ -e "$path" ]; then
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label")
    else
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (missing: $path)")
    fi
}

assert_not_exists() {
    local label="$1" path="$2"
    if [ ! -e "$path" ]; then
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label")
    else
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (should not exist: $path)")
    fi
}

# ============================================================
# Tests — Claude Code harness (backward compat & new)
# ============================================================

test_claude_help() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --help 2>&1)
    assert_eq "claude-help shows harness-profile-switcher" "true" \
        "$(echo "$out" | grep -q 'harness-profile-switcher' && echo true || echo false)"
    assert_eq "claude-help shows managed items" "true" \
        "$(echo "$out" | grep -q 'agents' && echo true || echo false)"
}

test_claude_version() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --version 2>&1)
    assert_eq "claude-version shows hps" "true" \
        "$(echo "$out" | grep -q '^hps' && echo true || echo false)"
    assert_eq "claude-version shows harness" "true" \
        "$(echo "$out" | grep -q 'claude' && echo true || echo false)"
}

test_claude_create() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" create test1 2>&1)
    assert_eq "claude-create prints name" "true" \
        "$(echo "$out" | grep -q 'test1' && echo true || echo false)"
    assert_exists "claude-create agents dir" "$pdir/test1/agents"
    assert_exists "claude-create skills dir" "$pdir/test1/skills"
    assert_exists "claude-create plugins dir" "$pdir/test1/plugins"
    assert_exists "claude-create commands dir" "$pdir/test1/commands"
    assert_exists "claude-create CLAUDE.md" "$pdir/test1/CLAUDE.md"

    assert_fail "claude-create duplicate fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" create test1
    assert_fail "claude-create missing name fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" create
}

test_claude_init() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/agents" "$cdir/skills" "$cdir/plugins" "$cdir/commands"
    echo "test-instructions" > "$cdir/CLAUDE.md"
    echo '{"key":"val"}' > "$cdir/settings.json"
    echo '{"local":true}' > "$cdir/settings.local.json"
    echo "agent1" > "$cdir/agents/a1.md"
    mkdir -p "$cdir/skills/s1"
    echo "skill1" > "$cdir/skills/s1/SKILL.md"
    echo '{"plugins":{}}' > "$cdir/plugins/installed_plugins.json"
    echo "cmd1" > "$cdir/commands/c1.md"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" init >/dev/null 2>&1

    assert_eq "claude-init moves CLAUDE.md" "test-instructions" "$(cat "$pdir/main/CLAUDE.md")"
    assert_eq "claude-init moves settings.json" '{"key":"val"}' "$(cat "$pdir/main/settings.json")"
    assert_eq "claude-init moves settings.local.json" '{"local":true}' "$(cat "$pdir/main/settings.local.json")"
    assert_eq "claude-init moves agents" "agent1" "$(cat "$pdir/main/agents/a1.md")"
    assert_eq "claude-init moves skills" "skill1" "$(cat "$pdir/main/skills/s1/SKILL.md")"
    assert_eq "claude-init moves plugins" '{"plugins":{}}' "$(cat "$pdir/main/plugins/installed_plugins.json")"
    assert_eq "claude-init moves commands" "cmd1" "$(cat "$pdir/main/commands/c1.md")"
    assert_symlink "claude-init symlinks agents" "$cdir/agents" "$pdir/main/agents"
    assert_symlink "claude-init symlinks skills" "$cdir/skills" "$pdir/main/skills"
    assert_symlink "claude-init symlinks plugins" "$cdir/plugins" "$pdir/main/plugins"
    assert_symlink "claude-init symlinks commands" "$cdir/commands" "$pdir/main/commands"
    assert_symlink "claude-init symlinks CLAUDE.md" "$cdir/CLAUDE.md" "$pdir/main/CLAUDE.md"
    assert_symlink "claude-init symlinks settings.json" "$cdir/settings.json" "$pdir/main/settings.json"
    assert_symlink "claude-init symlinks settings.local.json" "$cdir/settings.local.json" "$pdir/main/settings.local.json"

    # Init again — main already exists, should switch to it
    assert_ok "claude-init with existing main" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" init
}

test_claude_current_after_init() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/agents"
    echo "" > "$cdir/agents/a.md"
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" init >/dev/null 2>&1
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" current 2>&1)
    assert_eq "claude-current shows main after init" "main" "$out"
}

test_claude_list_after_init() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/agents"
    echo "" > "$cdir/agents/a.md"
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" init >/dev/null 2>&1
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" list 2>&1)
    assert_eq "claude-list marks current with *" "1" "$(echo "$out" | grep -c '^\* main')"
}

test_claude_switch() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/alpha/agents" "$pdir/alpha/skills" "$pdir/alpha/plugins" "$pdir/alpha/commands"
    echo "alpha-instructions" > "$pdir/alpha/CLAUDE.md"
    echo '{"a":true}' > "$pdir/alpha/plugins/installed_plugins.json"

    mkdir -p "$pdir/beta/agents" "$pdir/beta/skills" "$pdir/beta/plugins" "$pdir/beta/commands"
    echo "beta-instructions" > "$pdir/beta/CLAUDE.md"
    echo '{"beta":true}' > "$pdir/beta/settings.json"
    echo '{"b":true}' > "$pdir/beta/plugins/installed_plugins.json"

    ln -s "$pdir/alpha/agents" "$cdir/agents"
    ln -s "$pdir/alpha/skills" "$cdir/skills"
    ln -s "$pdir/alpha/plugins" "$cdir/plugins"
    ln -s "$pdir/alpha/commands" "$cdir/commands"
    ln -s "$pdir/alpha/CLAUDE.md" "$cdir/CLAUDE.md"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" beta >/dev/null 2>&1

    assert_symlink "claude-switch repoints agents" "$cdir/agents" "$pdir/beta/agents"
    assert_symlink "claude-switch repoints plugins" "$cdir/plugins" "$pdir/beta/plugins"
    assert_symlink "claude-switch repoints commands" "$cdir/commands" "$pdir/beta/commands"
    assert_symlink "claude-switch repoints CLAUDE.md" "$cdir/CLAUDE.md" "$pdir/beta/CLAUDE.md"
    assert_symlink "claude-switch repoints settings.json" "$cdir/settings.json" "$pdir/beta/settings.json"
    assert_eq "claude-switch reads correct CLAUDE.md" "beta-instructions" "$(cat "$cdir/CLAUDE.md")"
    assert_eq "claude-switch reads correct plugins" '{"b":true}' "$(cat "$cdir/plugins/installed_plugins.json")"
    assert_eq "claude-switch current shows beta" "beta" \
        "$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" current 2>&1)"
}

test_claude_switch_nonexistent() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    assert_fail "claude-switch nonexistent fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" nonexistent
}

test_claude_switch_skips_missing() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/minimal/agents"
    ln -s "$pdir/minimal/agents" "$cdir/agents"

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" minimal 2>&1)
    assert_eq "claude-switch reports skipped" "true" \
        "$(echo "$out" | grep -q 'Skipped' && echo true || echo false)"
    assert_not_exists "claude-switch missing CLAUDE.md not symlinked" "$cdir/CLAUDE.md"
    assert_not_exists "claude-switch missing plugins not symlinked" "$cdir/plugins"
    assert_not_exists "claude-switch missing settings not symlinked" "$cdir/settings.json"
}

test_claude_switch_removes_old_symlinks() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/agents" "$pdir/full/skills" "$pdir/full/plugins" "$pdir/full/commands"
    echo "full" > "$pdir/full/CLAUDE.md"
    echo '{}' > "$pdir/full/settings.json"
    echo '{}' > "$pdir/full/settings.local.json"

    mkdir -p "$pdir/empty/agents"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" full >/dev/null 2>&1
    assert_exists "claude-full has plugins symlink" "$cdir/plugins"
    assert_exists "claude-full has settings.json symlink" "$cdir/settings.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" empty >/dev/null 2>&1
    assert_not_exists "claude-empty removes plugins symlink" "$cdir/plugins"
    assert_not_exists "claude-empty removes settings.json symlink" "$cdir/settings.json"
    assert_not_exists "claude-empty removes settings.local.json symlink" "$cdir/settings.local.json"
}

test_claude_safety_real_dir() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/safe/agents"
    mkdir -p "$cdir/agents"  # real dir, not symlink
    assert_fail "claude-safety refuses real dir" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" safe
}

test_claude_safety_real_file() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/safe2/agents"
    echo "real" > "$pdir/safe2/CLAUDE.md"
    echo "real-file" > "$cdir/CLAUDE.md"  # real file, not symlink
    assert_fail "claude-safety refuses real file" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" safe2
}

test_claude_clone() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/original/agents" "$pdir/original/skills/s1" "$pdir/original/plugins" "$pdir/original/commands"
    echo "orig" > "$pdir/original/CLAUDE.md"
    echo "agent" > "$pdir/original/agents/a.md"
    echo '{"p":1}' > "$pdir/original/plugins/installed_plugins.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" clone original copy1 >/dev/null 2>&1

    assert_eq "claude-clone copies CLAUDE.md" "orig" "$(cat "$pdir/copy1/CLAUDE.md")"
    assert_eq "claude-clone copies agents" "agent" "$(cat "$pdir/copy1/agents/a.md")"
    assert_exists "claude-clone copies skills dir" "$pdir/copy1/skills/s1"
    assert_eq "claude-clone copies plugins" '{"p":1}' "$(cat "$pdir/copy1/plugins/installed_plugins.json")"
    assert_exists "claude-clone copies commands dir" "$pdir/copy1/commands"

    assert_fail "claude-clone nonexistent source" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" clone nope copy2
    assert_fail "claude-clone existing dest" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" clone original copy1
}

test_claude_list_counts() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/counted/agents" "$pdir/counted/skills/s1" "$pdir/counted/skills/s2"
    echo "" > "$pdir/counted/agents/a1.md"
    echo "" > "$pdir/counted/agents/a2.md"
    echo "" > "$pdir/counted/agents/a3.md"

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" list 2>&1)
    assert_eq "claude-list counts agents" "1" "$(echo "$out" | grep -c '3 agents')"
    assert_eq "claude-list counts skills" "1" "$(echo "$out" | grep -c '2 skills')"
}

test_claude_current_noprofile() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" current 2>&1) || true
    assert_eq "claude-current no profile says so" "1" "$(echo "$out" | grep -c 'No active profile')"
}

test_claude_install_noprofile() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    assert_fail "claude-install no profile fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" install
}

test_claude_install_noplugins_file() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/noplugins/agents"
    ln -s "$pdir/noplugins/agents" "$cdir/agents"
    assert_fail "claude-install no plugins file fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" install
}

test_claude_install_empty_plugins() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/emptyplugins/plugins" "$pdir/emptyplugins/agents"
    echo '{"version":2,"plugins":{}}' > "$pdir/emptyplugins/plugins/installed_plugins.json"
    ln -s "$pdir/emptyplugins/agents" "$cdir/agents"
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" install 2>&1)
    assert_eq "claude-install empty plugins says none" "true" \
        "$(echo "$out" | grep -q 'No plugins' && echo true || echo false)"
}

test_claude_full_isolation() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/work/agents" "$pdir/work/skills/ws1" "$pdir/work/plugins" "$pdir/work/commands"
    echo "work-rules" > "$pdir/work/CLAUDE.md"
    echo '{"work":true}' > "$pdir/work/settings.json"
    echo "work-cmd" > "$pdir/work/commands/deploy.md"
    echo "work-agent" > "$pdir/work/agents/deploy.md"

    mkdir -p "$pdir/play/agents" "$pdir/play/skills" "$pdir/play/plugins" "$pdir/play/commands"
    echo "play-rules" > "$pdir/play/CLAUDE.md"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" work >/dev/null 2>&1
    assert_eq "claude-isolation work CLAUDE.md" "work-rules" "$(cat "$cdir/CLAUDE.md")"
    assert_eq "claude-isolation work agent" "work-agent" "$(cat "$cdir/agents/deploy.md")"
    assert_eq "claude-isolation work command" "work-cmd" "$(cat "$cdir/commands/deploy.md")"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" play >/dev/null 2>&1
    assert_eq "claude-isolation play CLAUDE.md" "play-rules" "$(cat "$cdir/CLAUDE.md")"
    assert_not_exists "claude-isolation play no work agent" "$cdir/agents/deploy.md"
    assert_not_exists "claude-isolation play no settings" "$cdir/settings.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" work >/dev/null 2>&1
    assert_eq "claude-isolation back work CLAUDE.md" "work-rules" "$(cat "$cdir/CLAUDE.md")"
    assert_eq "claude-isolation back work agent" "work-agent" "$(cat "$cdir/agents/deploy.md")"
}

test_claude_relative_symlink_current() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/relmain/agents"
    ( cd "$cdir" && ln -s "../$(basename "$pdir")/relmain/agents" agents )
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" current 2>&1) || true
    assert_eq "claude-relative-symlink current" "relmain" "$out"
}

test_claude_symlinked_profiles_dir() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    real_profiles="$TMPDIR_ROOT/real_profiles"
    mkdir -p "$real_profiles/symprofile/agents"
    rm -rf "$pdir"
    ln -s "$real_profiles" "$pdir"
    ln -s "$real_profiles/symprofile/agents" "$cdir/agents"
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" current 2>&1) || true
    assert_eq "claude-symlinked-profiles-dir current" "symprofile" "$out"
}

# ============================================================
# Tests — Pi harness
# ============================================================

test_pi_help() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi --help 2>&1)
    assert_eq "pi-help shows harness-profile-switcher" "true" \
        "$(echo "$out" | grep -q 'harness-profile-switcher' && echo true || echo false)"
    assert_eq "pi-help shows pi" "true" \
        "$(echo "$out" | grep -q 'pi coding agent' && echo true || echo false)"
    assert_eq "pi-help lists extensions" "true" \
        "$(echo "$out" | grep -q 'extensions' && echo true || echo false)"
}

test_pi_version() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi --version 2>&1)
    assert_eq "pi-version shows hps" "true" \
        "$(echo "$out" | grep -q '^hps' && echo true || echo false)"
    assert_eq "pi-version shows harness" "true" \
        "$(echo "$out" | grep -q 'pi' && echo true || echo false)"
}

test_pi_create() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi create work 2>&1)
    assert_eq "pi-create prints name" "true" \
        "$(echo "$out" | grep -q 'work' && echo true || echo false)"
    assert_exists "pi-create extensions dir" "$pdir/work/extensions"
    assert_exists "pi-create skills dir" "$pdir/work/skills"
    assert_exists "pi-create prompts dir" "$pdir/work/prompts"
    assert_exists "pi-create themes dir" "$pdir/work/themes"
    assert_exists "pi-create AGENTS.md" "$pdir/work/AGENTS.md"
    assert_exists "pi-create settings.json" "$pdir/work/settings.json"

    assert_fail "pi-create duplicate fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi create work
    assert_fail "pi-create missing name fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi create
}

test_pi_init() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/extensions" "$cdir/skills" "$cdir/prompts" "$cdir/themes"
    echo "# Pi context" > "$cdir/AGENTS.md"
    echo '{"key":"val"}' > "$cdir/settings.json"
    echo "ext1" > "$cdir/extensions/ext1.ts"
    mkdir -p "$cdir/skills/s1"
    echo "skill1" > "$cdir/skills/s1/SKILL.md"
    echo "prompt1" > "$cdir/prompts/p1.md"
    echo '{"theme":"dark"}' > "$cdir/themes/t1.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi init >/dev/null 2>&1

    assert_eq "pi-init moves AGENTS.md" "# Pi context" "$(cat "$pdir/main/AGENTS.md")"
    assert_eq "pi-init moves settings.json" '{"key":"val"}' "$(cat "$pdir/main/settings.json")"
    assert_eq "pi-init moves extensions" "ext1" "$(cat "$pdir/main/extensions/ext1.ts")"
    assert_eq "pi-init moves skills" "skill1" "$(cat "$pdir/main/skills/s1/SKILL.md")"
    assert_eq "pi-init moves prompts" "prompt1" "$(cat "$pdir/main/prompts/p1.md")"
    assert_eq "pi-init moves themes" '{"theme":"dark"}' "$(cat "$pdir/main/themes/t1.json")"

    assert_symlink "pi-init symlinks extensions" "$cdir/extensions" "$pdir/main/extensions"
    assert_symlink "pi-init symlinks skills" "$cdir/skills" "$pdir/main/skills"
    assert_symlink "pi-init symlinks prompts" "$cdir/prompts" "$pdir/main/prompts"
    assert_symlink "pi-init symlinks themes" "$cdir/themes" "$pdir/main/themes"
    assert_symlink "pi-init symlinks AGENTS.md" "$cdir/AGENTS.md" "$pdir/main/AGENTS.md"
    assert_symlink "pi-init symlinks settings.json" "$cdir/settings.json" "$pdir/main/settings.json"

    # Init again — main already exists, should switch to it
    assert_ok "pi-init with existing main" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi init
}

test_pi_current_after_init() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/extensions"
    touch "$cdir/extensions/e.ts"
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi init >/dev/null 2>&1
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi current 2>&1)
    assert_eq "pi-current shows main after init" "main" "$out"
}

test_pi_list_after_init() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$cdir/extensions"
    touch "$cdir/extensions/e.ts"
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi init >/dev/null 2>&1
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi list 2>&1)
    assert_eq "pi-list marks current with *" "1" "$(echo "$out" | grep -c '^\* main')"
}

test_pi_switch() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Profile alpha
    mkdir -p "$pdir/alpha/extensions" "$pdir/alpha/skills" "$pdir/alpha/prompts" "$pdir/alpha/themes"
    echo "alpha-context" > "$pdir/alpha/AGENTS.md"
    echo '{"alpha":true}' > "$pdir/alpha/settings.json"
    echo "ext1" > "$pdir/alpha/extensions/e1.ts"

    # Profile beta
    mkdir -p "$pdir/beta/extensions" "$pdir/beta/skills" "$pdir/beta/prompts" "$pdir/beta/themes"
    echo "beta-context" > "$pdir/beta/AGENTS.md"
    echo '{"beta":"yes"}' > "$pdir/beta/settings.json"
    echo "bext" > "$pdir/beta/extensions/b1.ts"

    # Initial symlinks for alpha
    ln -s "$pdir/alpha/extensions" "$cdir/extensions"
    ln -s "$pdir/alpha/skills" "$cdir/skills"
    ln -s "$pdir/alpha/prompts" "$cdir/prompts"
    ln -s "$pdir/alpha/themes" "$cdir/themes"
    ln -s "$pdir/alpha/AGENTS.md" "$cdir/AGENTS.md"
    ln -s "$pdir/alpha/settings.json" "$cdir/settings.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi beta >/dev/null 2>&1

    assert_symlink "pi-switch repoints extensions" "$cdir/extensions" "$pdir/beta/extensions"
    assert_symlink "pi-switch repoints skills" "$cdir/skills" "$pdir/beta/skills"
    assert_symlink "pi-switch repoints prompts" "$cdir/prompts" "$pdir/beta/prompts"
    assert_symlink "pi-switch repoints themes" "$cdir/themes" "$pdir/beta/themes"
    assert_symlink "pi-switch repoints AGENTS.md" "$cdir/AGENTS.md" "$pdir/beta/AGENTS.md"
    assert_symlink "pi-switch repoints settings.json" "$cdir/settings.json" "$pdir/beta/settings.json"
    assert_eq "pi-switch reads correct AGENTS.md" "beta-context" "$(cat "$cdir/AGENTS.md")"
    assert_eq "pi-switch reads correct settings" '{"beta":"yes"}' "$(cat "$cdir/settings.json")"
    assert_eq "pi-switch current shows beta" "beta" \
        "$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi current 2>&1)"
}

test_pi_switch_nonexistent() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    assert_fail "pi-switch nonexistent fails" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi nonexistent
}

test_pi_switch_skips_missing() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/minimal/extensions"
    ln -s "$pdir/minimal/extensions" "$cdir/extensions"

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi minimal 2>&1)
    assert_eq "pi-switch reports skipped" "true" \
        "$(echo "$out" | grep -q 'Skipped' && echo true || echo false)"
    assert_not_exists "pi-switch missing AGENTS.md not symlinked" "$cdir/AGENTS.md"
    assert_not_exists "pi-switch missing skills not symlinked" "$cdir/skills"
    assert_not_exists "pi-switch missing settings not symlinked" "$cdir/settings.json"
}

test_pi_switch_removes_old_symlinks() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/extensions" "$pdir/full/skills" "$pdir/full/prompts" "$pdir/full/themes"
    echo "full" > "$pdir/full/AGENTS.md"
    echo '{}' > "$pdir/full/settings.json"

    mkdir -p "$pdir/empty/extensions"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi full >/dev/null 2>&1
    assert_exists "pi-full has skills symlink" "$cdir/skills"
    assert_exists "pi-full has AGENTS.md symlink" "$cdir/AGENTS.md"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi empty >/dev/null 2>&1
    assert_not_exists "pi-empty removes skills symlink" "$cdir/skills"
    assert_not_exists "pi-empty removes prompts symlink" "$cdir/prompts"
    assert_not_exists "pi-empty removes themes symlink" "$cdir/themes"
    assert_not_exists "pi-empty removes AGENTS.md symlink" "$cdir/AGENTS.md"
}

test_pi_safety_real_dir() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/safe/extensions"
    mkdir -p "$cdir/extensions"  # real dir, not symlink
    assert_fail "pi-safety refuses real dir" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi safe
}

test_pi_safety_real_file() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/safe2/extensions"
    echo "real" > "$pdir/safe2/AGENTS.md"
    echo "real-file" > "$cdir/AGENTS.md"  # real file, not symlink
    assert_fail "pi-safety refuses real file" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi safe2
}

test_pi_clone() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/original/extensions" "$pdir/original/skills/s1" "$pdir/original/prompts" "$pdir/original/themes"
    echo "orig" > "$pdir/original/AGENTS.md"
    echo "ext1" > "$pdir/original/extensions/e1.ts"
    echo '{"p":1}' > "$pdir/original/settings.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi clone original copy1 >/dev/null 2>&1

    assert_eq "pi-clone copies AGENTS.md" "orig" "$(cat "$pdir/copy1/AGENTS.md")"
    assert_eq "pi-clone copies extensions" "ext1" "$(cat "$pdir/copy1/extensions/e1.ts")"
    assert_exists "pi-clone copies skills dir" "$pdir/copy1/skills/s1"
    assert_exists "pi-clone copies prompts dir" "$pdir/copy1/prompts"
    assert_exists "pi-clone copies themes dir" "$pdir/copy1/themes"
    assert_eq "pi-clone copies settings" '{"p":1}' "$(cat "$pdir/copy1/settings.json")"

    assert_fail "pi-clone nonexistent source" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi clone nope copy2
    assert_fail "pi-clone existing dest" \
        HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi clone original copy1
}

test_pi_list_counts() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/counted/extensions" "$pdir/counted/skills/s1" "$pdir/counted/skills/s2" \
             "$pdir/counted/prompts" "$pdir/counted/themes"
    touch "$pdir/counted/extensions/e1.ts" "$pdir/counted/extensions/e2.js" "$pdir/counted/extensions/e3.ts"
    touch "$pdir/counted/prompts/p1.md" "$pdir/counted/prompts/p2.md"
    touch "$pdir/counted/themes/t1.json"

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi list 2>&1)
    assert_eq "pi-list counts ext" "1" "$(echo "$out" | grep -c '3 ext')"
    assert_eq "pi-list counts skills" "1" "$(echo "$out" | grep -c '2 skills')"
    assert_eq "pi-list counts prompts" "1" "$(echo "$out" | grep -c '2 prompts')"
    assert_eq "pi-list counts themes" "1" "$(echo "$out" | grep -c '1 themes')"
}

test_pi_current_noprofile() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi current 2>&1) || true
    assert_eq "pi-current no profile says so" "1" "$(echo "$out" | grep -c 'No active profile')"
}

test_pi_install_noop() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi install 2>&1)
    assert_eq "pi-install noop says don't use plugin install" "true" \
        "$(echo "$out" | grep -q "don't use plugin installation" && echo true || echo false)"
}

test_pi_full_isolation() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/work/extensions" "$pdir/work/skills/ws1" "$pdir/work/prompts" "$pdir/work/themes"
    echo "work-context" > "$pdir/work/AGENTS.md"
    echo '{"work":true}' > "$pdir/work/settings.json"
    echo "wext" > "$pdir/work/extensions/deploy.ts"
    echo "wprompt" > "$pdir/work/prompts/review.md"

    mkdir -p "$pdir/play/extensions" "$pdir/play/skills" "$pdir/play/prompts" "$pdir/play/themes"
    echo "play-context" > "$pdir/play/AGENTS.md"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi work >/dev/null 2>&1
    assert_eq "pi-isolation work AGENTS.md" "work-context" "$(cat "$cdir/AGENTS.md")"
    assert_eq "pi-isolation work ext" "wext" "$(cat "$cdir/extensions/deploy.ts")"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi play >/dev/null 2>&1
    assert_eq "pi-isolation play AGENTS.md" "play-context" "$(cat "$cdir/AGENTS.md")"
    assert_not_exists "pi-isolation play no work ext" "$cdir/extensions/deploy.ts"
    assert_not_exists "pi-isolation play no settings" "$cdir/settings.json"

    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi work >/dev/null 2>&1
    assert_eq "pi-isolation back work AGENTS.md" "work-context" "$(cat "$cdir/AGENTS.md")"
    assert_eq "pi-isolation back work ext" "wext" "$(cat "$cdir/extensions/deploy.ts")"
}

test_pi_partial_items() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Profile with only extensions/ — everything else missing
    mkdir -p "$pdir/partial/extensions"
    echo "only-ext" > "$pdir/partial/extensions/e1.ts"

    ln -s "$pdir/partial/extensions" "$cdir/extensions"

    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" --harness pi partial 2>&1)
    assert_eq "pi-partial reports skipped" "true" \
        "$(echo "$out" | grep -q 'Skipped' && echo true || echo false)"
    assert_exists "pi-partial extensions linked" "$cdir/extensions/e1.ts"
    assert_not_exists "pi-partial skills not linked" "$cdir/skills"
    assert_not_exists "pi-partial AGENTS.md not linked" "$cdir/AGENTS.md"
}

test_pi_harness_env() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Use HPS_HARNESS env var instead of --harness flag
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" HPS_HARNESS=pi "$HPS" create envtest >/dev/null 2>&1
    assert_exists "pi-env-var create extensions dir" "$pdir/envtest/extensions"
    assert_exists "pi-env-var create AGENTS.md" "$pdir/envtest/AGENTS.md"
}

test_pi_harness_flag_override() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # --harness pi should override HPS_HARNESS=claude
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" HPS_HARNESS=claude "$HPS" --harness pi create over >/dev/null 2>&1
    assert_exists "pi-flag-override create extensions" "$pdir/over/extensions"
    assert_exists "pi-flag-override create AGENTS.md" "$pdir/over/AGENTS.md"
}

test_default_harness_is_claude() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Without --harness, should default to claude behavior
    HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" create default-test >/dev/null 2>&1
    assert_exists "default-harness agents dir" "$pdir/default-test/agents"
    assert_exists "default-harness plugins dir" "$pdir/default-test/plugins"
    assert_exists "default-harness CLAUDE.md" "$pdir/default-test/CLAUDE.md"
    assert_not_exists "default-harness not extensions" "$pdir/default-test/extensions"
}

# ============================================================
# Audit tests — claude harness
# ============================================================

test_audit_claude_missing_skills() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Full profile
    mkdir -p "$pdir/full/agents" "$pdir/full/skills/s1" "$pdir/full/skills/s2" \
             "$pdir/full/plugins" "$pdir/full/commands"
    echo "s1-skill" > "$pdir/full/skills/s1/SKILL.md"
    echo "s2-skill" > "$pdir/full/skills/s2/SKILL.md"
    echo "agent1" > "$pdir/full/agents/a1.md"
    echo '{}' > "$pdir/full/CLAUDE.md"

    # Empty profile (target)
    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-claude-missing-skills-lists-s1" "true" \
        "$(echo "$out" | grep -q 's1.*ICM skill' && echo true || echo false)"
    assert_eq "audit-claude-missing-skills-lists-s2" "true" \
        "$(echo "$out" | grep -q 's2.*ICM skill' && echo true || echo false)"
    assert_eq "audit-claude-missing-skills-section" "true" \
        "$(echo "$out" | grep -q '### Skills' && echo true || echo false)"
}

test_audit_claude_missing_agents() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/agents" "$pdir/full/skills" "$pdir/full/plugins" "$pdir/full/commands"
    echo "agent-protocol" > "$pdir/full/agents/review.md"
    echo "agent-web" > "$pdir/full/agents/web-bot.md"
    echo '{}' > "$pdir/full/CLAUDE.md"

    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-claude-missing-agents-review" "true" \
        "$(echo "$out" | grep -q 'review.*candidate for skill conversion' && echo true || echo false)"
    assert_eq "audit-claude-missing-agents-web" "true" \
        "$(echo "$out" | grep -q 'web-bot.*candidate for skill conversion' && echo true || echo false)"
}

test_audit_claude_missing_plugins() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/plugins" "$pdir/full/agents" "$pdir/full/skills" "$pdir/full/commands"
    echo '{"version":2,"plugins":{}}' > "$pdir/full/plugins/installed_plugins.json"
    echo '{}' > "$pdir/full/CLAUDE.md"

    mkdir -p "$pdir/empty/plugins" "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-claude-missing-plugins" "true" \
        "$(echo "$out" | grep -q 'installed_plugins.*reinstall with hps install' && echo true || echo false)"
}

test_audit_claude_skips_self() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/only/agents" "$pdir/only/skills" "$pdir/only/plugins" "$pdir/only/commands"
    echo "only-agent" > "$pdir/only/agents/a1.md"
    echo '{}' > "$pdir/only/CLAUDE.md"

    local out
    out=$(hps_with "$h" audit only 2>&1)
    # Should say no other profiles, not list itself
    assert_eq "audit-claude-skips-self-no-other" "true" \
        "$(echo "$out" | grep -q 'No other profiles' && echo true || echo false)"
}

test_audit_claude_handles_empty_target() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    # Full profile with everything
    mkdir -p "$pdir/full/agents" "$pdir/full/skills/s1" "$pdir/full/plugins" "$pdir/full/commands"
    echo "skill1" > "$pdir/full/skills/s1/SKILL.md"
    echo "agent1" > "$pdir/full/agents/a1.md"
    echo '{}' > "$pdir/full/plugins/installed_plugins.json"
    echo '{}' > "$pdir/full/CLAUDE.md"

    # Empty target — no skills/agents dirs with content
    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-claude-empty-target-exit-0" "0" "$?"
    assert_eq "audit-claude-empty-target-has-header" "true" \
        "$(echo "$out" | grep -q 'hps audit empty' && echo true || echo false)"
}

test_audit_claude_nonexistent() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/some/agents"
    local out
    out=$(hps_with "$h" audit nope 2>&1) && rc=0 || rc=$?
    assert_eq "audit-claude-nonexistent-exit-1" "1" "$rc"
    assert_eq "audit-claude-nonexistent-message" "true" \
        "$(echo "$out" | grep -q "not found" && echo true || echo false)"
}

# ============================================================
# Audit tests — pi harness
# ============================================================

test_audit_pi_missing_skills() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/skills/s1" "$pdir/full/extensions" "$pdir/full/prompts" "$pdir/full/themes"
    echo "s1-skill" > "$pdir/full/skills/s1/SKILL.md"
    echo "ctx" > "$pdir/full/AGENTS.md"

    mkdir -p "$pdir/empty/skills" "$pdir/empty/extensions" "$pdir/empty/prompts" "$pdir/empty/themes"
    echo "ctx" > "$pdir/empty/AGENTS.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-pi-missing-skills-lists-s1" "true" \
        "$(echo "$out" | grep -q 's1' && echo true || echo false)"
    assert_eq "audit-pi-missing-skills-section" "true" \
        "$(echo "$out" | grep -q '### Skills' && echo true || echo false)"
}

test_audit_pi_missing_extensions() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/extensions" "$pdir/full/skills" "$pdir/full/prompts" "$pdir/full/themes"
    echo "ext1" > "$pdir/full/extensions/doom.ts"
    echo "ext2" > "$pdir/full/extensions/hack.js"
    echo "ctx" > "$pdir/full/AGENTS.md"

    mkdir -p "$pdir/empty/extensions" "$pdir/empty/skills" "$pdir/empty/prompts" "$pdir/empty/themes"
    echo "ctx" > "$pdir/empty/AGENTS.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-pi-missing-extensions-doom" "true" \
        "$(echo "$out" | grep -q 'doom.ts.*candidate for skill conversion' && echo true || echo false)"
    assert_eq "audit-pi-missing-extensions-hack" "true" \
        "$(echo "$out" | grep -q 'hack.js.*candidate for skill conversion' && echo true || echo false)"
}

test_audit_pi_missing_prompts() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/prompts" "$pdir/full/extensions" "$pdir/full/skills" "$pdir/full/themes"
    echo "review-prompt" > "$pdir/full/prompts/review.md"
    echo "deploy-prompt" > "$pdir/full/prompts/deploy.md"
    echo "ctx" > "$pdir/full/AGENTS.md"

    mkdir -p "$pdir/empty/prompts" "$pdir/empty/extensions" "$pdir/empty/skills" "$pdir/empty/themes"
    echo "ctx" > "$pdir/empty/AGENTS.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-pi-missing-prompts-review" "true" \
        "$(echo "$out" | grep -q 'review.*can be copied' && echo true || echo false)"
    assert_eq "audit-pi-missing-prompts-deploy" "true" \
        "$(echo "$out" | grep -q 'deploy.*can be copied' && echo true || echo false)"
}

test_audit_pi_missing_themes() {
    local h="pi"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/themes" "$pdir/full/extensions" "$pdir/full/skills" "$pdir/full/prompts"
    echo '{"dark":true}' > "$pdir/full/themes/dark.json"
    echo "ctx" > "$pdir/full/AGENTS.md"

    mkdir -p "$pdir/empty/themes" "$pdir/empty/extensions" "$pdir/empty/skills" "$pdir/empty/prompts"
    echo "ctx" > "$pdir/empty/AGENTS.md"

    local out
    out=$(hps_with "$h" audit empty 2>&1)
    assert_eq "audit-pi-missing-themes-dark" "true" \
        "$(echo "$out" | grep -q 'dark.*can be copied' && echo true || echo false)"
}

# ============================================================
# Audit --write-missing tests
# ============================================================

test_audit_write_missing_creates_file() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/agents" "$pdir/full/skills/s1" "$pdir/full/plugins" "$pdir/full/commands"
    echo "skill1" > "$pdir/full/skills/s1/SKILL.md"
    echo '{}' > "$pdir/full/CLAUDE.md"
    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    hps_with "$h" audit empty --write-missing >/dev/null 2>&1
    assert_exists "audit-write-missing-file-exists" "$pdir/empty/MISSING_SKILLS.md"
}

test_audit_write_missing_preserves_notes() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/agents" "$pdir/full/skills/s1" "$pdir/full/plugins" "$pdir/full/commands"
    echo "skill1" > "$pdir/full/skills/s1/SKILL.md"
    echo '{}' > "$pdir/full/CLAUDE.md"
    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    # Write once
    hps_with "$h" audit empty --write-missing >/dev/null 2>&1
    # Add manual notes
    echo "" >> "$pdir/empty/MISSING_SKILLS.md"
    echo "## Adaptation Notes" >> "$pdir/empty/MISSING_SKILLS.md"
    echo "" >> "$pdir/empty/MISSING_SKILLS.md"
    echo "These skills need manual adaptation for this profile." >> "$pdir/empty/MISSING_SKILLS.md"
    # Write again
    hps_with "$h" audit empty --write-missing >/dev/null 2>&1

    assert_eq "audit-write-missing-preserves-notes" "true" \
        "$(grep -q 'manual adaptation' "$pdir/empty/MISSING_SKILLS.md" && echo true || echo false)"
}

test_audit_write_missing_idempotent() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/full/agents" "$pdir/full/skills/s1" "$pdir/full/plugins" "$pdir/full/commands"
    echo "skill1" > "$pdir/full/skills/s1/SKILL.md"
    echo '{}' > "$pdir/full/CLAUDE.md"
    mkdir -p "$pdir/empty/agents" "$pdir/empty/skills" "$pdir/empty/plugins" "$pdir/empty/commands"
    echo '{}' > "$pdir/empty/CLAUDE.md"

    hps_with "$h" audit empty --write-missing >/dev/null 2>&1
    local first_content
    first_content=$(cat "$pdir/empty/MISSING_SKILLS.md")
    hps_with "$h" audit empty --write-missing >/dev/null 2>&1
    local second_content
    second_content=$(cat "$pdir/empty/MISSING_SKILLS.md")

    # Compare generated sections (before ## Adaptation Notes)
    local first_gen
    first_gen=$(echo "$first_content" | sed -n '1,/^## Adaptation Notes/p' | sed '$d')
    local second_gen
    second_gen=$(echo "$second_content" | sed -n '1,/^## Adaptation Notes/p' | sed '$d')
    assert_eq "audit-write-missing-idempotent" "$first_gen" "$second_gen"
}

# ============================================================
# Isolation audit tests
# ============================================================

test_isolation_notes_orphaned_items() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/main/agents" "$pdir/main/skills" "$pdir/main/plugins" "$pdir/main/commands"
    echo '{}' > "$pdir/main/CLAUDE.md"

    # Create an orphaned file in config dir
    echo "garbage" > "$cdir/orphan.txt"

    local out
    out=$(hps_with "$h" main 2>&1) || true
    assert_eq "isolation-notes-orphaned" "true" \
        "$(echo "$out" | grep -q 'Non-managed item' && echo true || echo false)"
}

# ============================================================
# ICM install detection tests
# ============================================================

test_icm_install_skips_no_icm() {
    local h="claude"
    reset_env "$h"
    local cdir; cdir=$(_config_dir "$h")
    local pdir; pdir=$(_profiles_dir "$h")

    mkdir -p "$pdir/plain/agents" "$pdir/plain/plugins" "$pdir/plain/commands" \
             "$pdir/plain/skills/s1"
    echo "skill1" > "$pdir/plain/skills/s1/SKILL.md"
    echo '{"version":2,"plugins":{}}' > "$pdir/plain/plugins/installed_plugins.json"

    # Symlink a managed item to make plain the active profile
    ln -s "$pdir/plain/agents" "$cdir/agents"
    ln -s "$pdir/plain/plugins" "$cdir/plugins"

    local out
    out=$(HPS_CONFIG_DIR="$cdir" HPS_PROFILES_DIR="$pdir" "$HPS" install 2>&1) || true
    # Should NOT mention ICM installer at all
    assert_eq "icm-install-skips-no-icm" "false" \
        "$(echo "$out" | grep -q 'ICM' && echo true || echo false)"
}

# ============================================================
# Run tests
# ============================================================

echo "=== Claude Code harness tests ==="
test_claude_help
test_claude_version
test_claude_create
test_claude_init
test_claude_current_after_init
test_claude_list_after_init
test_claude_switch
test_claude_switch_nonexistent
test_claude_switch_skips_missing
test_claude_switch_removes_old_symlinks
test_claude_safety_real_dir
test_claude_safety_real_file
test_claude_clone
test_claude_list_counts
test_claude_current_noprofile
test_claude_install_noprofile
test_claude_install_noplugins_file
test_claude_install_empty_plugins
test_claude_full_isolation
test_claude_relative_symlink_current
test_claude_symlinked_profiles_dir
test_audit_claude_missing_skills
test_audit_claude_missing_agents
test_audit_claude_missing_plugins
test_audit_claude_skips_self
test_audit_claude_handles_empty_target
test_audit_claude_nonexistent
test_audit_write_missing_creates_file
test_audit_write_missing_preserves_notes
test_audit_write_missing_idempotent
test_isolation_notes_orphaned_items
test_icm_install_skips_no_icm

echo ""
echo "=== Pi harness tests ==="
test_pi_help
test_pi_version
test_pi_create
test_pi_init
test_pi_current_after_init
test_pi_list_after_init
test_pi_switch
test_pi_switch_nonexistent
test_pi_switch_skips_missing
test_pi_switch_removes_old_symlinks
test_pi_safety_real_dir
test_pi_safety_real_file
test_pi_clone
test_pi_list_counts
test_pi_current_noprofile
test_pi_install_noop
test_pi_full_isolation
test_pi_partial_items
test_pi_harness_env
test_pi_harness_flag_override
test_default_harness_is_claude
test_audit_pi_missing_skills
test_audit_pi_missing_extensions
test_audit_pi_missing_prompts
test_audit_pi_missing_themes

# ============================================================
# Report
# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed (total $((PASS + FAIL)))"
echo ""
for line in "${TESTS[@]}"; do
    echo "$line"
done

exit "$FAIL"

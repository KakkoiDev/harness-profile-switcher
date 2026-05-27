#!/usr/bin/env bash
set -euo pipefail

CCP="$(cd "$(dirname "$0")" && pwd)/ccp"
PASS=0
FAIL=0
TESTS=()

# Setup temp dirs
TMPDIR_ROOT=$(mktemp -d)
export CCP_CLAUDE_DIR="$TMPDIR_ROOT/claude"
export CCP_PROFILES_DIR="$TMPDIR_ROOT/profiles"

cleanup() {
    rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

reset_env() {
    rm -rf "$TMPDIR_ROOT"
    mkdir -p "$CCP_CLAUDE_DIR"
    mkdir -p "$CCP_PROFILES_DIR"
}

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
    if "$@" >/dev/null 2>&1; then
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
    if "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1))
        TESTS+=("  FAIL  $label (expected failure, got success)")
    else
        PASS=$((PASS + 1))
        TESTS+=("  PASS  $label")
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
# Tests
# ============================================================

# -- help --
reset_env
out=$("$CCP" --help 2>&1)
assert_eq "help shows usage" "true" "$(echo "$out" | grep -q 'claude-code-profiles' && echo true || echo false)"
assert_eq "help lists plugins" "true" "$(echo "$out" | grep -q 'plugins' && echo true || echo false)"

# -- create --
reset_env
out=$("$CCP" create test1 2>&1)
assert_eq "create prints name" "true" "$(echo "$out" | grep -q 'test1' && echo true || echo false)"
assert_exists "create makes agents dir" "$CCP_PROFILES_DIR/test1/agents"
assert_exists "create makes skills dir" "$CCP_PROFILES_DIR/test1/skills"
assert_exists "create makes plugins dir" "$CCP_PROFILES_DIR/test1/plugins"
assert_exists "create makes commands dir" "$CCP_PROFILES_DIR/test1/commands"
assert_exists "create makes CLAUDE.md" "$CCP_PROFILES_DIR/test1/CLAUDE.md"

# -- create duplicate --
assert_fail "create duplicate fails" "$CCP" create test1

# -- create missing name --
assert_fail "create without name fails" "$CCP" create

# -- init --
reset_env
mkdir -p "$CCP_CLAUDE_DIR/agents" "$CCP_CLAUDE_DIR/skills" \
         "$CCP_CLAUDE_DIR/plugins" "$CCP_CLAUDE_DIR/commands"
echo "test-instructions" > "$CCP_CLAUDE_DIR/CLAUDE.md"
echo '{"key":"val"}' > "$CCP_CLAUDE_DIR/settings.json"
echo '{"local":true}' > "$CCP_CLAUDE_DIR/settings.local.json"
echo "agent1" > "$CCP_CLAUDE_DIR/agents/a1.md"
mkdir -p "$CCP_CLAUDE_DIR/skills/s1"
echo "skill1" > "$CCP_CLAUDE_DIR/skills/s1/SKILL.md"
echo '{"plugins":{}}' > "$CCP_CLAUDE_DIR/plugins/installed_plugins.json"
echo "cmd1" > "$CCP_CLAUDE_DIR/commands/c1.md"

"$CCP" init >/dev/null 2>&1

assert_eq "init moves CLAUDE.md" "test-instructions" "$(cat "$CCP_PROFILES_DIR/main/CLAUDE.md")"
assert_eq "init moves settings.json" '{"key":"val"}' "$(cat "$CCP_PROFILES_DIR/main/settings.json")"
assert_eq "init moves settings.local.json" '{"local":true}' "$(cat "$CCP_PROFILES_DIR/main/settings.local.json")"
assert_eq "init moves agents" "agent1" "$(cat "$CCP_PROFILES_DIR/main/agents/a1.md")"
assert_eq "init moves skills" "skill1" "$(cat "$CCP_PROFILES_DIR/main/skills/s1/SKILL.md")"
assert_eq "init moves plugins" '{"plugins":{}}' "$(cat "$CCP_PROFILES_DIR/main/plugins/installed_plugins.json")"
assert_eq "init moves commands" "cmd1" "$(cat "$CCP_PROFILES_DIR/main/commands/c1.md")"
assert_symlink "init symlinks agents" "$CCP_CLAUDE_DIR/agents" "$CCP_PROFILES_DIR/main/agents"
assert_symlink "init symlinks skills" "$CCP_CLAUDE_DIR/skills" "$CCP_PROFILES_DIR/main/skills"
assert_symlink "init symlinks plugins" "$CCP_CLAUDE_DIR/plugins" "$CCP_PROFILES_DIR/main/plugins"
assert_symlink "init symlinks commands" "$CCP_CLAUDE_DIR/commands" "$CCP_PROFILES_DIR/main/commands"
assert_symlink "init symlinks CLAUDE.md" "$CCP_CLAUDE_DIR/CLAUDE.md" "$CCP_PROFILES_DIR/main/CLAUDE.md"
assert_symlink "init symlinks settings.json" "$CCP_CLAUDE_DIR/settings.json" "$CCP_PROFILES_DIR/main/settings.json"
assert_symlink "init symlinks settings.local.json" "$CCP_CLAUDE_DIR/settings.local.json" "$CCP_PROFILES_DIR/main/settings.local.json"

# -- init with existing main (fresh machine scenario) --
# main already exists from previous init, should switch to it
assert_ok "init with existing main switches to it" "$CCP" init

# -- current after init --
out=$("$CCP" current 2>&1)
assert_eq "current shows main after init" "main" "$out"

# -- list after init --
out=$("$CCP" list 2>&1)
assert_eq "list marks current with *" "1" "$(echo "$out" | grep -c '^\* main')"

# -- switch --
reset_env
mkdir -p "$CCP_PROFILES_DIR/alpha/agents" "$CCP_PROFILES_DIR/alpha/skills" \
         "$CCP_PROFILES_DIR/alpha/plugins" "$CCP_PROFILES_DIR/alpha/commands"
echo "alpha-instructions" > "$CCP_PROFILES_DIR/alpha/CLAUDE.md"
echo '{"a":true}' > "$CCP_PROFILES_DIR/alpha/plugins/installed_plugins.json"

mkdir -p "$CCP_PROFILES_DIR/beta/agents" "$CCP_PROFILES_DIR/beta/skills" \
         "$CCP_PROFILES_DIR/beta/plugins" "$CCP_PROFILES_DIR/beta/commands"
echo "beta-instructions" > "$CCP_PROFILES_DIR/beta/CLAUDE.md"
echo '{"beta":true}' > "$CCP_PROFILES_DIR/beta/settings.json"
echo '{"b":true}' > "$CCP_PROFILES_DIR/beta/plugins/installed_plugins.json"

# Create initial symlinks (simulate previous switch)
ln -s "$CCP_PROFILES_DIR/alpha/agents" "$CCP_CLAUDE_DIR/agents"
ln -s "$CCP_PROFILES_DIR/alpha/skills" "$CCP_CLAUDE_DIR/skills"
ln -s "$CCP_PROFILES_DIR/alpha/plugins" "$CCP_CLAUDE_DIR/plugins"
ln -s "$CCP_PROFILES_DIR/alpha/commands" "$CCP_CLAUDE_DIR/commands"
ln -s "$CCP_PROFILES_DIR/alpha/CLAUDE.md" "$CCP_CLAUDE_DIR/CLAUDE.md"

"$CCP" beta >/dev/null 2>&1

assert_symlink "switch repoints agents" "$CCP_CLAUDE_DIR/agents" "$CCP_PROFILES_DIR/beta/agents"
assert_symlink "switch repoints plugins" "$CCP_CLAUDE_DIR/plugins" "$CCP_PROFILES_DIR/beta/plugins"
assert_symlink "switch repoints commands" "$CCP_CLAUDE_DIR/commands" "$CCP_PROFILES_DIR/beta/commands"
assert_symlink "switch repoints CLAUDE.md" "$CCP_CLAUDE_DIR/CLAUDE.md" "$CCP_PROFILES_DIR/beta/CLAUDE.md"
assert_symlink "switch repoints settings.json" "$CCP_CLAUDE_DIR/settings.json" "$CCP_PROFILES_DIR/beta/settings.json"
assert_eq "switch reads correct CLAUDE.md" "beta-instructions" "$(cat "$CCP_CLAUDE_DIR/CLAUDE.md")"
assert_eq "switch reads correct plugins" '{"b":true}' "$(cat "$CCP_CLAUDE_DIR/plugins/installed_plugins.json")"
assert_eq "current shows beta" "beta" "$("$CCP" current 2>&1)"

# -- switch to nonexistent --
assert_fail "switch to nonexistent fails" "$CCP" nonexistent

# -- switch skips missing items --
reset_env
mkdir -p "$CCP_PROFILES_DIR/minimal/agents"
# Only agents - everything else missing
ln -s "$CCP_PROFILES_DIR/minimal/agents" "$CCP_CLAUDE_DIR/agents"

out=$("$CCP" minimal 2>&1)
assert_eq "switch reports skipped items" "true" "$(echo "$out" | grep -q 'Skipped' && echo true || echo false)"
assert_not_exists "missing CLAUDE.md not symlinked" "$CCP_CLAUDE_DIR/CLAUDE.md"
assert_not_exists "missing plugins not symlinked" "$CCP_CLAUDE_DIR/plugins"
assert_not_exists "missing settings not symlinked" "$CCP_CLAUDE_DIR/settings.json"

# -- switch removes old symlinks for missing items --
reset_env
mkdir -p "$CCP_PROFILES_DIR/full/agents" "$CCP_PROFILES_DIR/full/skills" \
         "$CCP_PROFILES_DIR/full/plugins" "$CCP_PROFILES_DIR/full/commands"
echo "full" > "$CCP_PROFILES_DIR/full/CLAUDE.md"
echo '{}' > "$CCP_PROFILES_DIR/full/settings.json"
echo '{}' > "$CCP_PROFILES_DIR/full/settings.local.json"

mkdir -p "$CCP_PROFILES_DIR/empty/agents"
# empty has only agents dir

# Switch to full first
"$CCP" full >/dev/null 2>&1
assert_exists "full profile has plugins symlink" "$CCP_CLAUDE_DIR/plugins"
assert_exists "full profile has settings.json symlink" "$CCP_CLAUDE_DIR/settings.json"

# Switch to empty - old symlinks should be removed
"$CCP" empty >/dev/null 2>&1
assert_not_exists "empty profile removes plugins symlink" "$CCP_CLAUDE_DIR/plugins"
assert_not_exists "empty profile removes settings.json symlink" "$CCP_CLAUDE_DIR/settings.json"
assert_not_exists "empty profile removes settings.local.json symlink" "$CCP_CLAUDE_DIR/settings.local.json"

# -- safety: refuse to overwrite non-symlink --
reset_env
mkdir -p "$CCP_PROFILES_DIR/safe/agents"
mkdir -p "$CCP_CLAUDE_DIR/agents"  # real dir, not symlink
assert_fail "refuses to overwrite real dir" "$CCP" safe

# -- safety: refuse to overwrite real file --
reset_env
mkdir -p "$CCP_PROFILES_DIR/safe2/agents"
echo "real" > "$CCP_PROFILES_DIR/safe2/CLAUDE.md"
echo "real-file" > "$CCP_CLAUDE_DIR/CLAUDE.md"  # real file, not symlink
assert_fail "refuses to overwrite real file" "$CCP" safe2

# -- clone --
reset_env
mkdir -p "$CCP_PROFILES_DIR/original/agents" "$CCP_PROFILES_DIR/original/skills/s1" \
         "$CCP_PROFILES_DIR/original/plugins" "$CCP_PROFILES_DIR/original/commands"
echo "orig" > "$CCP_PROFILES_DIR/original/CLAUDE.md"
echo "agent" > "$CCP_PROFILES_DIR/original/agents/a.md"
echo '{"p":1}' > "$CCP_PROFILES_DIR/original/plugins/installed_plugins.json"

"$CCP" clone original copy1 >/dev/null 2>&1

assert_eq "clone copies CLAUDE.md" "orig" "$(cat "$CCP_PROFILES_DIR/copy1/CLAUDE.md")"
assert_eq "clone copies agents" "agent" "$(cat "$CCP_PROFILES_DIR/copy1/agents/a.md")"
assert_exists "clone copies skills dir" "$CCP_PROFILES_DIR/copy1/skills/s1"
assert_eq "clone copies plugins" '{"p":1}' "$(cat "$CCP_PROFILES_DIR/copy1/plugins/installed_plugins.json")"
assert_exists "clone copies commands dir" "$CCP_PROFILES_DIR/copy1/commands"

# -- clone errors --
assert_fail "clone nonexistent source fails" "$CCP" clone nope copy2
assert_fail "clone to existing dest fails" "$CCP" clone original copy1

# -- list counts --
reset_env
mkdir -p "$CCP_PROFILES_DIR/counted/agents" "$CCP_PROFILES_DIR/counted/skills/s1" "$CCP_PROFILES_DIR/counted/skills/s2"
echo "" > "$CCP_PROFILES_DIR/counted/agents/a1.md"
echo "" > "$CCP_PROFILES_DIR/counted/agents/a2.md"
echo "" > "$CCP_PROFILES_DIR/counted/agents/a3.md"

out=$("$CCP" list 2>&1)
assert_eq "list counts agents" "1" "$(echo "$out" | grep -c '3 agents')"
assert_eq "list counts skills" "1" "$(echo "$out" | grep -c '2 skills')"

# -- current with no profile --
reset_env
out=$("$CCP" current 2>&1) || true
assert_eq "current with no profile says so" "1" "$(echo "$out" | grep -c 'No active profile')"

# -- install: no active profile --
reset_env
assert_fail "install with no profile fails" "$CCP" install

# -- install: no plugins file --
reset_env
mkdir -p "$CCP_PROFILES_DIR/noplugins/agents"
ln -s "$CCP_PROFILES_DIR/noplugins/agents" "$CCP_CLAUDE_DIR/agents"
assert_fail "install with no plugins file fails" "$CCP" install

# -- install: empty plugins --
reset_env
mkdir -p "$CCP_PROFILES_DIR/emptyplugins/plugins" "$CCP_PROFILES_DIR/emptyplugins/agents"
echo '{"version":2,"plugins":{}}' > "$CCP_PROFILES_DIR/emptyplugins/plugins/installed_plugins.json"
ln -s "$CCP_PROFILES_DIR/emptyplugins/agents" "$CCP_CLAUDE_DIR/agents"
out=$("$CCP" install 2>&1)
assert_eq "install with empty plugins says none" "true" "$(echo "$out" | grep -q 'No plugins' && echo true || echo false)"

# -- full isolation round-trip --
reset_env
mkdir -p "$CCP_PROFILES_DIR/work/agents" "$CCP_PROFILES_DIR/work/skills/ws1" \
         "$CCP_PROFILES_DIR/work/plugins" "$CCP_PROFILES_DIR/work/commands"
echo "work-rules" > "$CCP_PROFILES_DIR/work/CLAUDE.md"
echo '{"work":true}' > "$CCP_PROFILES_DIR/work/settings.json"
echo "work-cmd" > "$CCP_PROFILES_DIR/work/commands/deploy.md"
echo "work-agent" > "$CCP_PROFILES_DIR/work/agents/deploy.md"

mkdir -p "$CCP_PROFILES_DIR/play/agents" "$CCP_PROFILES_DIR/play/skills" \
         "$CCP_PROFILES_DIR/play/plugins" "$CCP_PROFILES_DIR/play/commands"
echo "play-rules" > "$CCP_PROFILES_DIR/play/CLAUDE.md"

# Switch work -> play -> work, verify isolation
"$CCP" work >/dev/null 2>&1
assert_eq "round-trip: work CLAUDE.md" "work-rules" "$(cat "$CCP_CLAUDE_DIR/CLAUDE.md")"
assert_eq "round-trip: work agent" "work-agent" "$(cat "$CCP_CLAUDE_DIR/agents/deploy.md")"
assert_eq "round-trip: work command" "work-cmd" "$(cat "$CCP_CLAUDE_DIR/commands/deploy.md")"

"$CCP" play >/dev/null 2>&1
assert_eq "round-trip: play CLAUDE.md" "play-rules" "$(cat "$CCP_CLAUDE_DIR/CLAUDE.md")"
assert_not_exists "round-trip: play has no work agent" "$CCP_CLAUDE_DIR/agents/deploy.md"
assert_not_exists "round-trip: play has no settings" "$CCP_CLAUDE_DIR/settings.json"

"$CCP" work >/dev/null 2>&1
assert_eq "round-trip: back to work CLAUDE.md" "work-rules" "$(cat "$CCP_CLAUDE_DIR/CLAUDE.md")"
assert_eq "round-trip: back to work agent" "work-agent" "$(cat "$CCP_CLAUDE_DIR/agents/deploy.md")"

# -- regression: current_profile handles relative symlinks --
# Real-world dotfiles commits store ~/.claude/<item> as relative symlinks
# (e.g. ../../../claude-profiles/main/agents). Parser must resolve them.
reset_env
mkdir -p "$CCP_PROFILES_DIR/relmain/agents"
( cd "$CCP_CLAUDE_DIR" && ln -s "../$(basename "$CCP_PROFILES_DIR")/relmain/agents" agents )
out=$("$CCP" current 2>&1) || true
assert_eq "current handles relative symlink target" "relmain" "$out"

# -- regression: current_profile handles PROFILES_DIR being a symlink --
# Real-world ~/.claude-profiles is a symlink to ~/dotfiles/claude-profiles.
# If symlinks point through the underlying real path while PROFILES_DIR uses
# the surface path, the parser must canonicalize both before comparing.
reset_env
real_profiles="$TMPDIR_ROOT/real_profiles"
mkdir -p "$real_profiles/symprofile/agents"
rm -rf "$CCP_PROFILES_DIR"
ln -s "$real_profiles" "$CCP_PROFILES_DIR"
# Symlink stores absolute path through the REAL directory, not the symlink alias
ln -s "$real_profiles/symprofile/agents" "$CCP_CLAUDE_DIR/agents"
out=$("$CCP" current 2>&1) || true
assert_eq "current handles symlinked PROFILES_DIR" "symprofile" "$out"

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

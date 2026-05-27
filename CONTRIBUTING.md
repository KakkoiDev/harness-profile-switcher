# Contributing to claude-code-profiles

## Getting Started

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/claude-code-profiles.git
cd claude-code-profiles
chmod +x ccp test_ccp.sh install.sh

# Install dev dependencies
brew install shellcheck    # macOS
sudo apt-get install shellcheck  # Debian/Ubuntu
```

## Development

```bash
# Run tests (no framework needed - pure bash)
./test_ccp.sh

# Test against a real ~/.claude in an isolated dir
export CCP_CLAUDE_DIR=/tmp/fake-claude
export CCP_PROFILES_DIR=/tmp/fake-profiles
mkdir -p "$CCP_CLAUDE_DIR" "$CCP_PROFILES_DIR"
./ccp init
./ccp create work
./ccp work

# Lint
shellcheck ccp install.sh test_ccp.sh
```

## Code Style

**Bash, not POSIX sh.** The script uses arrays and `[[ ... ]]`-free conventional bash. `#!/usr/bin/env bash` is required.

**Naming:** `snake_case` for variables/functions, `UPPER_CASE` for constants and env overrides.

**Safety:** Every destructive operation must check pre-conditions. `cmd_switch` refuses to overwrite non-symlinks. Follow that pattern.

## Pull Requests

Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`.

Checklist:
- [ ] `./test_ccp.sh` passes (all 70+ tests)
- [ ] `shellcheck ccp` is clean
- [ ] New behavior covered by a test in `test_ccp.sh`
- [ ] Bug fixes include a regression test that fails on revert

## Scope

**In scope:**
- Profile switching of managed items (`agents/`, `skills/`, `plugins/`, `commands/`, `CLAUDE.md`, `settings.json`, `settings.local.json`)
- Plugin reinstallation per profile
- Safe migration from existing `~/.claude` config

**Out of scope:**
- Sync between machines (use git on the profile dir)
- Profile content editing (use a regular editor)
- Project-level `.claude/` switching (already isolated by Claude Code)

## Bug Reports

Include:
- `ccp --version`
- OS + bash version (`bash --version`)
- `ls -la ~/.claude` and `ls -la ~/.claude-profiles`
- Steps to reproduce, expected vs actual

## License

Contributions licensed under MIT.

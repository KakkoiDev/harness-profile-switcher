# Contributing to harness-profile-switcher

## Getting Started

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/harness-profile-switcher.git
cd harness-profile-switcher
chmod +x hps test_hps.sh install.sh

# Install dev dependencies
brew install shellcheck    # macOS
sudo apt-get install shellcheck  # Debian/Ubuntu
```

## Development

```bash
# Run tests (no framework needed - pure bash)
./test_hps.sh

# Test both harnesses against isolated dirs
export HPS_CONFIG_DIR=/tmp/fake-config
export HPS_PROFILES_DIR=/tmp/fake-profiles
mkdir -p "$HPS_CONFIG_DIR" "$HPS_PROFILES_DIR"
./hps init
./hps create work
./hps work

# Pi harness test
export HPS_CONFIG_DIR=/tmp/pi-config
export HPS_PROFILES_DIR=/tmp/pi-profiles
mkdir -p "$HPS_CONFIG_DIR" "$HPS_PROFILES_DIR"
./hps --harness pi init
./hps --harness pi create work
./hps --harness pi work

# Test with HPS_HARNESS env var
HPS_HARNESS=pi ./hps create test

# Lint
shellcheck hps install.sh test_hps.sh
```

## Code Style

**Bash, not POSIX sh.** The script uses arrays and `[[ ... ]]`-free conventional bash. `#!/usr/bin/env bash` is required.

**Naming:** `snake_case` for variables/functions, `UPPER_CASE` for constants and env overrides.

**Safety:** Every destructive operation must check pre-conditions. `cmd_switch` refuses to overwrite non-symlinks. Follow that pattern.

## Pull Requests

Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`.

Checklist:
- [ ] `./test_hps.sh` passes (all 80+ tests)
- [ ] `shellcheck hps` is clean
- [ ] New behavior covered by a test in `test_hps.sh`
- [ ] Bug fixes include a regression test that fails on revert

## Scope

**In scope:**
- Profile switching of managed items (harness-specific: `agents/`, `skills/`, `plugins/`, `commands/`, `CLAUDE.md`, `settings.json`, `settings.local.json` for Claude; `extensions/`, `skills/`, `prompts/`, `themes/`, `AGENTS.md`, `settings.json` for pi)
- Plugin reinstallation per profile (Claude Code only)
- Safe migration from existing config
- Harness abstraction for future tools
- **Profile auditing:** `hps audit <profile>` compares items across profiles
- **ICM runtime detection:** `hps install` detects ICM skills (skill with `stages/` dir) and triggers installer
- **Isolation verification:** `hps <profile>` and `hps init` verify symlinks point to the correct profile
- **MISSING_SKILLS.md:** Generatable report with idempotent regeneration and preserved manual notes

**Out of scope:**
- Sync between machines (use git on the profile dir)
- Profile content editing (use a regular editor)
- Project-level `.claude/` or `.pi/` switching (already isolated by the tool)
- Package management for pi profiles (pi auto-installs on startup)

## Testing with both harnesses

The test suite (`test_hps.sh`) includes tests for both `claude` and `pi` harnesses.
All existing Claude tests are preserved. New features should include tests for
both harnesses where applicable.

```bash
# Run the full suite
./test_hps.sh

# Run a specific test function directly
HPS_CONFIG_DIR=/tmp/t HPS_PROFILES_DIR=/tmp/p ./hps --harness pi create work
```

### Testing audit commands manually

```bash
# Claude: profile comparison
HPS_PROFILES_DIR=/tmp/profiles ./hps --harness claude create full
HPS_PROFILES_DIR=/tmp/profiles ./hps --harness claude create empty
mkdir -p /tmp/profiles/full/agents /tmp/profiles/full/skills/s1
mkdir -p /tmp/profiles/empty/agents /tmp/profiles/empty/skills
echo "my-skill" > /tmp/profiles/full/skills/s1/SKILL.md
echo "my-agent" > /tmp/profiles/full/agents/a1.md
echo '{}' > /tmp/profiles/full/CLAUDE.md
echo '{}' > /tmp/profiles/empty/CLAUDE.md
HPS_PROFILES_DIR=/tmp/profiles ./hps --harness claude audit empty

# Pi: extension/prompt/theme comparison
HPS_PROFILES_DIR=/tmp/pi-profiles ./hps --harness pi create pfull
HPS_PROFILES_DIR=/tmp/pi-profiles ./hps --harness pi create pempty
mkdir -p /tmp/pi-profiles/pfull/extensions /tmp/pi-profiles/pfull/prompts
touch /tmp/pi-profiles/pfull/extensions/my-ext.ts
echo "### review" > /tmp/pi-profiles/pfull/prompts/review.md
echo '{}' > /tmp/pi-profiles/pfull/AGENTS.md
echo '{}' > /tmp/pi-profiles/pempty/AGENTS.md
HPS_PROFILES_DIR=/tmp/pi-profiles ./hps --harness pi audit pempty

# Write MISSING_SKILLS.md
HPS_PROFILES_DIR=/tmp/profiles ./hps --harness claude audit empty --write-missing
cat /tmp/profiles/empty/MISSING_SKILLS.md
```

### New test functions (audit, isolation, ICM)

| Function | What it tests |
|----------|---------------|
| `test_audit_claude_missing_skills` | Audit lists ICM skills from full profile |
| `test_audit_claude_missing_agents` | Audit lists agents as conversion candidates |
| `test_audit_claude_missing_plugins` | Audit lists plugins as reinstall candidates |
| `test_audit_claude_skips_self` | Audit doesn't compare profile against itself |
| `test_audit_claude_handles_empty_target` | Audit handles profiles with no content |
| `test_audit_claude_nonexistent` | Audit nonexistent profile exits 1 |
| `test_audit_pi_missing_skills` | Pi audit lists missing skills |
| `test_audit_pi_missing_extensions` | Pi audit lists .ts/.js extensions |
| `test_audit_pi_missing_prompts` | Pi audit lists prompts as copyable |
| `test_audit_pi_missing_themes` | Pi audit lists themes as copyable |
| `test_audit_write_missing_creates_file` | `--write-missing` creates MISSING_SKILLS.md |
| `test_audit_write_missing_preserves_notes` | Manual notes survive regeneration |
| `test_audit_write_missing_idempotent` | Same generated content on multiple runs |
| `test_isolation_notes_orphaned_items` | Warns about non-managed items in config dir |
| `test_icm_install_skips_no_icm` | Install doesn't trigger ICM without stages/ |

## Bug Reports

Include:
- `hps --version --harness <name>`
- OS + bash version (`bash --version`)
- `ls -la ~/.claude` (or `~/.pi/agent`) and `ls -la ~/.claude-profiles` (or `~/.pi-agent-profiles`)
- Steps to reproduce, expected vs actual

## License

Contributions licensed under MIT.

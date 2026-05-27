# claude-code-profiles

Switch [Claude Code](https://github.com/anthropics/claude-code) configurations atomically: agents, skills, plugins, commands, CLAUDE.md, and settings, all at once.

## Why claude-code-profiles?

**The gap:** Claude Code keeps everything in a single `~/.claude/` directory. Agents, skills, plugins, commands, `CLAUDE.md`, and `settings.json` all live in one place. There's no built-in `--profile` flag, no separate work/personal contexts, no clean way to swap a security-review setup for a frontend-dev setup.

**The workarounds break:**
- Renaming `~/.claude` mid-session: messy, race-y, easy to clobber.
- Git branches on `~/.claude`: noisy diffs, breaks while switching, no isolation.
- Manually editing `CLAUDE.md` per task: fine for one file, terrible for ten.

**ccp adds:**
- Atomic switching via symlinks. One command, all managed items swap together.
- Complete isolation. A profile is a separate computer equivalent.
- Per-profile plugin reinstall (`ccp install`).
- Safe migration from existing `~/.claude` (refuses to clobber non-symlinks).
- No daemon, no config file, no telemetry. Pure bash + python3.

**ccp doesn't replace** project-level `.claude/` config; that stays per-repo and is unaffected by profile switching.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/KakkoiDev/claude-code-profiles/main/install.sh | sh
```

Or clone and run locally:

```bash
git clone https://github.com/KakkoiDev/claude-code-profiles.git
cd claude-code-profiles
./install.sh
```

After install, migrate your existing config into a profile called `main`:

```bash
ccp init
```

<details>
<summary>Manual installation</summary>

```bash
chmod +x ccp
sudo ln -s "$(pwd)/ccp" /usr/local/bin/ccp
ccp init
```

</details>

<details>
<summary>Install options</summary>

```
./install.sh [OPTIONS]

Options:
  --dir PATH        Install directory (default: ~/.local/bin or /usr/local/bin)
  --init            Run 'ccp init' after install
  --skip-deps       Skip dependency checks
  --uninstall       Remove ccp
  --help            Show this help
```

</details>

## Usage

**Create profiles for different contexts:**

```bash
ccp create work
ccp create personal
ccp create security-audit
```

**Switch instantly:**

```bash
ccp work        # ~/.claude/* now points into work profile
ccp personal    # swap again
ccp current     # personal
```

**Clone a profile as a starting point:**

```bash
ccp clone main experiment
```

**Reinstall plugins for the active profile** (after `ccp init` on a fresh machine, or after pulling a profile from another machine):

```bash
ccp install
```

**List profiles with counts:**

```bash
ccp list
#   bare        (0 agents, 0 skills)
# * main        (15 agents, 23 skills)
#   security    (4 agents, 7 skills)
```

### Options

```
ccp [COMMAND] [ARGS]

Commands:
  ccp <profile>          Switch to profile
  ccp list               List available profiles
  ccp current            Show active profile
  ccp init               Setup on new machine or migrate existing config
  ccp install            Reinstall plugins for current profile
  ccp create <name>      Create empty profile
  ccp clone <src> <dst>  Clone profile
  ccp --version          Show version
  ccp --help             Show help

Environment:
  CCP_CLAUDE_DIR        Override ~/.claude (for testing)
  CCP_PROFILES_DIR      Override ~/.claude-profiles (for testing)
```

## How it works

```
~/.claude-profiles/
  main/
    agents/   skills/   plugins/   commands/
    CLAUDE.md   settings.json   settings.local.json
  work/
    ...
  security/
    ...

~/.claude/
  agents          -> ~/.claude-profiles/<active>/agents
  skills          -> ~/.claude-profiles/<active>/skills
  plugins         -> ~/.claude-profiles/<active>/plugins
  commands        -> ~/.claude-profiles/<active>/commands
  CLAUDE.md       -> ~/.claude-profiles/<active>/CLAUDE.md
  settings.json   -> ~/.claude-profiles/<active>/settings.json
  ...
```

`ccp <name>` removes the old symlinks and creates new ones pointing into the chosen profile. All seven managed items swap together. Items missing from a profile are unlinked rather than mis-pointed.

**Safety:** `ccp <name>` refuses to overwrite anything that isn't a symlink. If you have a real `CLAUDE.md` file in `~/.claude/`, you'll get an error pointing you at `ccp init` to migrate it first.

## With other tools

**Version your profiles with git:**

```bash
cd ~/.claude-profiles
git init
git add main work security
git commit -m "checkpoint profiles"
```

**Sync across machines:**

```bash
# Machine A
cd ~/.claude-profiles && git push

# Machine B
git clone <repo> ~/.claude-profiles
ccp init     # creates ~/.claude symlinks
ccp install  # reinstalls plugins listed in plugins/installed_plugins.json
```

**Per-shell profile (advanced):**

```bash
# Open a terminal scoped to a profile without changing the global one
CCP_CLAUDE_DIR=$(mktemp -d)/claude ccp work
CLAUDE_CONFIG_DIR=$CCP_CLAUDE_DIR claude
```

**Quick swap during a session:**

```bash
alias ccw='ccp work'
alias ccp-p='ccp personal'
```

## Contributing

```bash
# Run tests (no framework needed)
./test_ccp.sh

# 70+ tests covering: switch, init, clone, create, install,
# safety, isolation, relative symlinks, symlinked PROFILES_DIR
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Philosophy

- **Atomic.** All managed items swap together or not at all.
- **Safe.** Refuses to clobber non-symlinks. Migration is explicit.
- **Composable.** Profiles are plain directories. Use git, rsync, scp, anything.
- **Boring.** Pure bash + python3, no daemon, no config file, no telemetry.
- **Reversible.** Every profile is a normal directory. Delete `~/.claude-profiles/<name>/` to throw one away.

## Resources

- [Claude Code](https://github.com/anthropics/claude-code) (the CLI this manages)
- [Claude Code Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [Command Line Interface Guidelines](https://clig.dev)

## License

[MIT License](LICENSE)

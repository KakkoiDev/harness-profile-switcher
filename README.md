# harness-profile-switcher

Switch [Claude Code](https://github.com/anthropics/claude-code) and [pi coding agent](https://github.com/earendil-works/pi-coding-agent) configurations atomically: agents/extensions, skills, plugins/prompts/themes, commands, context files, and settings — all at once.

## Why hps?

**The gap:** Both Claude Code and pi keep everything in a single config directory (`~/.claude/` or `~/.pi/agent/`). There's no built-in `--profile` flag, no separate work/personal contexts, no clean way to swap a security-review setup for a frontend-dev setup.

**The workarounds break:**
- Renaming the config dir mid-session: messy, race-y, easy to clobber.
- Git branches on the config dir: noisy diffs, breaks while switching, no isolation.
- Manually editing the context file per task: fine for one file, terrible for ten.

**hps adds:**
- Atomic switching via symlinks. One command, all managed items swap together.
- Complete isolation. A profile is a separate computer equivalent.
- Multi-harness support: works with Claude Code (`~/.claude/`) and pi (`~/.pi/agent/`).
- Per-profile plugin reinstall (`hps install`, Claude Code only).
- Safe migration from existing config (refuses to clobber non-symlinks).
- No daemon, no config file, no telemetry. Pure bash + python3.

**hps doesn't replace** project-level config (`.claude/`, `.pi/`); those stay per-repo and are unaffected by profile switching.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/KakkoiDev/harness-profile-switcher/main/install.sh | sh
```

Or clone and run locally:

```bash
git clone https://github.com/KakkoiDev/harness-profile-switcher.git
cd harness-profile-switcher
./install.sh
```

After install, migrate your existing config into a profile called `main`:

```bash
# For Claude Code
hps init

# For pi
hps --harness pi init
```

<details>
<summary>Manual installation</summary>

```bash
chmod +x hps
sudo ln -s "$(pwd)/hps" /usr/local/bin/hps
hps init
```

</details>

<details>
<summary>Install options</summary>

```
./install.sh [OPTIONS]

Options:
  --dir PATH        Install directory (default: ~/.local/bin or /usr/local/bin)
  --init            Run 'hps init' after install
  --skip-deps       Skip dependency checks
  --uninstall       Remove hps
  --help            Show this help
```

</details>

---

## With Claude Code

**Create profiles for different contexts:**

```bash
hps create work
hps create personal
hps create security-audit
```

**Switch instantly:**

```bash
hps work        # ~/.claude/* now points into work profile
hps personal    # swap again
hps current     # personal
```

**Clone a profile as a starting point:**

```bash
hps clone main experiment
```

**Reinstall plugins for the active profile** (after `hps init` on a fresh machine, or after pulling a profile from another machine):

```bash
hps install
```

**List profiles with counts:**

```bash
hps list
#   bare        (0 agents, 0 skills)
# * main        (15 agents, 23 skills)
#   security    (4 agents, 7 skills)
```

### Managed items (Claude Code)

| Item | Type | Description |
|------|------|-------------|
| `agents/` | directory | Agent `.md` files |
| `skills/` | directory | Skill subdirectories |
| `plugins/` | directory | Plugin configs + `installed_plugins.json` |
| `commands/` | directory | Custom command `.md` files |
| `CLAUDE.md` | file | Global context instructions |
| `settings.json` | file | User settings |
| `settings.local.json` | file | Local settings overlay |

---

## With pi

**Create profiles for different contexts:**

```bash
hps --harness pi create work
hps --harness pi create personal
```

**Switch instantly:**

```bash
hps --harness pi work          # ~/.pi/agent/* now points into work profile
hps --harness pi personal      # swap again
hps --harness pi current       # personal
```

**Clone a profile as a starting point:**

```bash
hps --harness pi clone main experiment
```

**List profiles with counts:**

```bash
hps --harness pi list
#   bare        (0 ext, 0 skills, 0 prompts, 0 themes)
# * main        (12 ext, 8 skills, 5 prompts, 3 themes)
```

### Managed items (pi)

| Item | Type | Description |
|------|------|-------------|
| `extensions/` | directory | Pi extension `.ts` / `.js` files |
| `skills/` | directory | Skill subdirectories |
| `prompts/` | directory | Prompt template `.md` files |
| `themes/` | directory | Theme `.json` files |
| `AGENTS.md` | file | Global context instructions |
| `settings.json` | file | User settings (includes `packages` array) |

### Pi-specific notes

- **No plugin install.** Pi extensions are TypeScript files in `~/.pi/agent/extensions/`, not installable by name. `hps install` with the pi harness prints a note and exits 0.
- **Skills at multiple paths.** Pi loads skills from `~/.pi/agent/skills/`, `~/.agents/skills/`, `.pi/skills/`, and `.agents/skills/`. hps manages **only** `~/.pi/agent/skills/`. The other paths are project-level and unaffected.
- **`AGENTS.md` vs `CLAUDE.md`.** Pi reads both. `~/.pi/agent/AGENTS.md` (global, managed by hps) vs `./AGENTS.md` / `./CLAUDE.md` (project-level, unmanaged).
- **Pi auto-installs packages.** If a profile's `settings.json` contains a `packages` array, pi installs them on next startup (after project trust). Nothing for hps to do.
- **No `agents/` or `commands/` dirs.** Pi doesn't use these. No `settings.local.json` either.

---

## Commands

### `hps audit <profile>` — Compare profile against others

Shows what skills, agents, plugins, extensions, prompts, and themes exist in other
profiles but are missing from `<profile>`. Useful when you discover useful items in
one profile and want to add them to another.

**Claude Code example:**

```bash
hps audit main
# hps audit main (harness: claude)
#
# ## From 'work' profile
#
# ### Skills
#   refine-tickets (ICM skill)
#   sprint-focus (ICM skill)
#
# ### Agents
#   review (candidate for skill conversion)
#
# ### Plugins
#   installed_plugins.json (reinstall with hps install)
#
# Run 'hps audit main --write-missing' to generate MISSING_SKILLS.md
```

**Pi example:**

```bash
hps --harness pi audit main
# hps audit main (harness: pi)
#
# ## From 'work' profile
#
# ### Skills
#   ai-folder-research (ICM skill)
#
# ### Extensions
#   doom.ts (extension — candidate for skill conversion)
#
# ### Prompts
#   review (can be copied)
#
# ### Themes
#   dark (can be copied)
#
# Run 'hps audit main --write-missing' to generate MISSING_SKILLS.md
```

Items are categorized:

| Label | Meaning |
|-------|---------|
| `(ICM skill)` | Has `SKILL.md` + `stages/` dir — ICM-runtime compatible |
| `(candidate for skill conversion)` | Agent file that could be converted to a skill |
| `(reinstall with hps install)` | Plugin JSON — needs `hps install` to activate |
| `(can be copied)` | Plain file — safe to copy into the target profile |
| `(extension — candidate for skill conversion)` | Pi extension that could be adapted as a skill |

### `hps audit <profile> --write-missing` — Generate MISSING_SKILLS.md

Writes the audit report to `<profile>/MISSING_SKILLS.md` inside the profile directory.

**Idempotent.** Running multiple times produces the same generated content.

**Manual notes preserved.** Any content after the `## Adaptation Notes` section in
`MISSING_SKILLS.md` survives regeneration. Use this to track decisions about which
items to adapt and how.

```bash
hps audit main --write-missing
# Wrote MISSING_SKILLS.md to ~/.claude-profiles/main/MISSING_SKILLS.md
```

The file is plain Markdown — no YAML frontmatter, no JSON. Edit by hand as needed.

---

## Options

```
hps [COMMAND] [ARGS] [--harness <name>]

Commands:
  hps <profile>          Switch to profile
  hps list               List available profiles
  hps current            Show active profile
  hps init               Setup on new machine or migrate existing config
  hps install            Reinstall plugins for current profile (Claude Code only)
  hps create <name>      Create empty profile
  hps clone <src> <dst>  Clone profile
  hps --version          Show version
  hps --help             Show this help

Options:
  --harness <name>       Harness to use: claude (default) or pi
                         Can also be set via HPS_HARNESS env var

Environment:
  HPS_CONFIG_DIR         Override config dir (default: ~/.claude or ~/.pi/agent)
  HPS_PROFILES_DIR       Override profiles dir (default: ~/.claude-profiles or ~/.pi-agent-profiles)
  HPS_HARNESS            Harness name (claude, pi)
  CCP_CLAUDE_DIR         Deprecated, use HPS_CONFIG_DIR
  CCP_PROFILES_DIR       Deprecated, use HPS_PROFILES_DIR
```

---

## How it works

### Claude Code layout

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

### pi layout

```
~/.pi-agent-profiles/
  main/
    extensions/   skills/   prompts/   themes/
    AGENTS.md   settings.json
  work/
    ...
  personal/
    ...

~/.pi/agent/
  extensions      -> ~/.pi-agent-profiles/<active>/extensions
  skills          -> ~/.pi-agent-profiles/<active>/skills
  prompts         -> ~/.pi-agent-profiles/<active>/prompts
  themes          -> ~/.pi-agent-profiles/<active>/themes
  AGENTS.md       -> ~/.pi-agent-profiles/<active>/AGENTS.md
  settings.json   -> ~/.pi-agent-profiles/<active>/settings.json
```

`hps <name>` removes the old symlinks and creates new ones pointing into the chosen profile. All managed items swap together. Items missing from a profile are unlinked rather than mis-pointed.

**Safety:** `hps <name>` refuses to overwrite anything that isn't a symlink. If you have a real file where a symlink should go, you'll get an error pointing you at `hps init` to migrate it first.

---

## With other tools

**Version your profiles with git:**

```bash
cd ~/.claude-profiles   # or ~/.pi-agent-profiles
git init
git add main work personal
git commit -m "checkpoint profiles"
```

**Sync across machines:**

```bash
# Machine A
cd ~/.claude-profiles && git push

# Machine B
git clone <repo> ~/.claude-profiles
hps init         # creates config symlinks
hps install      # reinstalls plugins (Claude Code only)
```

**Per-shell profile (advanced):**

```bash
# Open a terminal scoped to a profile without changing the global one
HPS_CONFIG_DIR=$(mktemp -d)/claude hps work
CLAUDE_CONFIG_DIR=$HPS_CONFIG_DIR claude
```

**Quick swap during a session:**

```bash
alias hpw='hps work'
alias hpp='hps personal'
alias hppi='hps --harness pi'
```

---

## Contributing

```bash
# Run tests (no framework needed)
./test_hps.sh

# 80+ tests covering both harnesses: switch, init, clone, create, install,
# safety, isolation, relative symlinks, symlinked PROFILES_DIR
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Philosophy

- **Atomic.** All managed items swap together or not at all.
- **Safe.** Refuses to clobber non-symlinks. Migration is explicit.
- **Composable.** Profiles are plain directories. Use git, rsync, scp, anything.
- **Boring.** Pure bash + python3, no daemon, no config file, no telemetry.
- **Reversible.** Every profile is a normal directory. Delete `~/.claude-profiles/<name>/` or `~/.pi-agent-profiles/<name>/` to throw one away.

## Resources

- [Claude Code](https://github.com/anthropics/claude-code)
- [Claude Code Settings](https://docs.claude.com/en/docs/claude-code/settings)
- [pi coding agent](https://github.com/earendil-works/pi-coding-agent)
- [Command Line Interface Guidelines](https://clig.dev)

## License

[MIT License](LICENSE)

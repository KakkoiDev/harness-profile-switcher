#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

# Allow overrides for testing
CLAUDE_DIR="${CCP_CLAUDE_DIR:-$HOME/.claude}"
PROFILES_DIR="${CCP_PROFILES_DIR:-$HOME/.claude-profiles}"

# Items managed by profiles (complete isolation)
MANAGED_ITEMS=(agents skills plugins commands CLAUDE.md settings.json settings.local.json)

usage() {
    cat <<EOF
claude-code-profiles v${VERSION} - Switch Claude Code configurations

Usage:
  ccp <profile>          Switch to profile
  ccp list               List available profiles
  ccp current            Show active profile
  ccp init               Setup on new machine or migrate existing config
  ccp install            Reinstall plugins for current profile
  ccp create <name>      Create empty profile
  ccp clone <src> <dst>  Clone profile
  ccp --version          Show version
  ccp --help             Show this help

Managed items:
  agents/  skills/  plugins/  commands/
  CLAUDE.md  settings.json  settings.local.json

Layout:
  ~/.claude-profiles/
    main/
      agents/ skills/ plugins/ commands/
      CLAUDE.md settings.json settings.local.json
    work/
      ...

  ~/.claude/<item> is a symlink to ~/.claude-profiles/<active>/<item>
  Each profile is fully isolated (separate computer equivalent).
  Project-level .claude/ config is unaffected by profile switching.

Environment:
  CCP_CLAUDE_DIR        Override ~/.claude (for testing)
  CCP_PROFILES_DIR      Override ~/.claude-profiles (for testing)
EOF
}

current_profile() {
    local profiles_real
    profiles_real=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$PROFILES_DIR")
    for item in "${MANAGED_ITEMS[@]}"; do
        local target="$CLAUDE_DIR/$item"
        if [ -L "$target" ]; then
            local resolved
            resolved=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$target")
            case "$resolved" in
                "$profiles_real"/*)
                    echo "${resolved#$profiles_real/}" | cut -d/ -f1
                    return 0
                    ;;
            esac
        fi
    done
    echo ""
}

cmd_list() {
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "No profiles directory. Run: ccp init"
        exit 1
    fi

    local current
    current=$(current_profile)

    for dir in "$PROFILES_DIR"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")

        # Count agents and skills
        local n_agents=0 n_skills=0
        [ -d "$dir/agents" ] && n_agents=$(find "$dir/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
        [ -d "$dir/skills" ] && n_skills=$(find "$dir/skills" -maxdepth 1 -type d ! -name skills | wc -l | tr -d ' ')

        local marker="  "
        [ "$name" = "$current" ] && marker="* "

        echo "${marker}${name}  (${n_agents} agents, ${n_skills} skills)"
    done
}

cmd_current() {
    local current
    current=$(current_profile)
    if [ -n "$current" ]; then
        echo "$current"
    else
        echo "No active profile"
        exit 1
    fi
}

cmd_init() {
    mkdir -p "$CLAUDE_DIR"
    mkdir -p "$PROFILES_DIR"

    # If main profile exists already, switch and install plugins
    if [ -d "$PROFILES_DIR/main" ]; then
        cmd_switch "main"
        if [ -f "$PROFILES_DIR/main/plugins/installed_plugins.json" ]; then
            cmd_install
        fi
        echo ""
        echo "Ready. Profile 'main' active."
        return
    fi

    # First-time: migrate current config to main profile
    mkdir -p "$PROFILES_DIR/main"

    for item in "${MANAGED_ITEMS[@]}"; do
        local source="$CLAUDE_DIR/$item"
        if [ -e "$source" ] && [ ! -L "$source" ]; then
            mv "$source" "$PROFILES_DIR/main/$item"
            echo "Moved $item -> profiles/main/$item"
        fi
    done

    cmd_switch "main"
    echo ""
    echo "Initialized. Current config is now profile 'main'."
}

cmd_create() {
    local name="$1"

    if [ -d "$PROFILES_DIR/$name" ]; then
        echo "Profile '$name' already exists."
        exit 1
    fi

    mkdir -p "$PROFILES_DIR/$name/agents" "$PROFILES_DIR/$name/skills" \
             "$PROFILES_DIR/$name/plugins" "$PROFILES_DIR/$name/commands"
    touch "$PROFILES_DIR/$name/CLAUDE.md"
    echo "Created profile: $name"
    echo "  $PROFILES_DIR/$name/"
}

cmd_clone() {
    local src="$1"
    local dst="$2"

    if [ ! -d "$PROFILES_DIR/$src" ]; then
        echo "Source profile '$src' not found."
        exit 1
    fi
    if [ -d "$PROFILES_DIR/$dst" ]; then
        echo "Destination profile '$dst' already exists."
        exit 1
    fi

    cp -a "$PROFILES_DIR/$src" "$PROFILES_DIR/$dst"
    echo "Cloned: $src -> $dst"
}

cmd_install() {
    local current
    current=$(current_profile)
    if [ -z "$current" ]; then
        echo "No active profile. Switch to a profile first."
        exit 1
    fi

    local plugins_json="$PROFILES_DIR/$current/plugins/installed_plugins.json"
    if [ ! -f "$plugins_json" ]; then
        echo "No installed_plugins.json in profile '$current'."
        exit 1
    fi

    # Extract plugin keys (format: name@marketplace)
    local plugins
    plugins=$(python3 -c "
import json, sys
with open('$plugins_json') as f:
    data = json.load(f)
for key in data.get('plugins', {}):
    entries = data['plugins'][key]
    for entry in entries:
        scope = entry.get('scope', 'user')
        print(f'{key} {scope}')
" 2>/dev/null)

    if [ -z "$plugins" ]; then
        echo "No plugins to install."
        return
    fi

    echo "Installing plugins for profile '$current'..."
    local installed=0 failed=0
    while IFS=' ' read -r plugin scope; do
        echo "  Installing $plugin (scope: $scope)..."
        if claude plugin install "$plugin" --scope "$scope" 2>&1; then
            installed=$((installed + 1))
        else
            echo "    Failed: $plugin"
            failed=$((failed + 1))
        fi
    done <<< "$plugins"

    echo "Done. $installed installed, $failed failed."
}

cmd_switch() {
    local name="$1"
    local profile_dir="$PROFILES_DIR/$name"

    if [ ! -d "$profile_dir" ]; then
        echo "Profile '$name' not found."
        echo "Available:"
        cmd_list 2>/dev/null || ls "$PROFILES_DIR" 2>/dev/null | tr '\n' ' '
        exit 1
    fi

    local linked=()
    local skipped=()

    for item in "${MANAGED_ITEMS[@]}"; do
        local target="$CLAUDE_DIR/$item"
        local source="$profile_dir/$item"

        # Safety: refuse to overwrite non-symlink files
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            echo "ERROR: $target exists and is not a symlink."
            echo "Run 'ccp init' first to migrate existing config."
            exit 1
        fi

        # Remove old symlink
        rm -f "$target"

        # Create new symlink if profile has this item
        if [ -e "$source" ]; then
            ln -s "$source" "$target"
            linked+=("$item")
        else
            skipped+=("$item")
        fi
    done

    echo "Switched to: $name"
    if [ ${#linked[@]} -gt 0 ]; then echo "  Linked: ${linked[*]}"; fi
    if [ ${#skipped[@]} -gt 0 ]; then echo "  Skipped (not in profile): ${skipped[*]}"; fi
}

# Main
case "${1:-}" in
    ""|-h|--help)
        usage
        ;;
    --version|-V)
        echo "ccp v${VERSION}"
        ;;
    list)
        cmd_list
        ;;
    current)
        cmd_current
        ;;
    init)
        cmd_init
        ;;
    install)
        cmd_install
        ;;
    create)
        [ -z "${2:-}" ] && { echo "Usage: ccp create <name>"; exit 1; }
        cmd_create "$2"
        ;;
    clone)
        [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Usage: ccp clone <source> <dest>"; exit 1; }
        cmd_clone "$2" "$3"
        ;;
    *)
        cmd_switch "$1"
        ;;
esac

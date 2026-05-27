#!/bin/sh
# claude-code-profiles installer
# Installs the ccp binary
set -e

VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/KakkoiDev/claude-code-profiles/main"

# Detect local vs remote (curl | sh) mode
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/ccp" ]; then
  LOCAL_MODE=1
  CCP_SOURCE="$SCRIPT_DIR/ccp"
else
  LOCAL_MODE=0
  CCP_SOURCE=""
fi

# Defaults
INSTALL_DIR=""
SKIP_DEPS=0
UNINSTALL=0
RUN_INIT=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  RESET='\033[0m'
else
  GREEN="" RED="" YELLOW="" RESET=""
fi

info()  { printf "${GREEN}[+]${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${RESET} %s\n" "$1"; }
error() { printf "${RED}[x]${RESET} %s\n" "$1" >&2; }
die()   { error "$1"; exit 1; }

usage() {
  cat <<EOF
claude-code-profiles installer v${VERSION}

Usage: ./install.sh [OPTIONS]

Options:
  --dir PATH        Install directory (default: ~/.local/bin or /usr/local/bin)
  --init            Run 'ccp init' after install (migrates existing ~/.claude config)
  --skip-deps       Skip dependency checks
  --uninstall       Remove ccp
  --help            Show this help

Examples:
  ./install.sh                # Install ccp only
  ./install.sh --init         # Install and migrate existing config
  ./install.sh --dir ~/bin    # Install to custom directory
  ./install.sh --uninstall    # Remove
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        INSTALL_DIR="$2"; shift 2 ;;
    --init)       RUN_INIT=1; shift ;;
    --skip-deps)  SKIP_DEPS=1; shift ;;
    --uninstall)  UNINSTALL=1; shift ;;
    --help)       usage ;;
    *)            die "Unknown option: $1" ;;
  esac
done

resolve_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    return
  fi

  if [ -d "$HOME/.local/bin" ]; then
    INSTALL_DIR="$HOME/.local/bin"
  elif [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
}

check_deps() {
  if [ "$SKIP_DEPS" = 1 ]; then
    warn "Skipping dependency checks"
    return
  fi

  missing=""
  command -v bash >/dev/null 2>&1    || missing="$missing bash"
  command -v python3 >/dev/null 2>&1 || missing="$missing python3"

  if [ -n "$missing" ]; then
    die "Missing dependencies:$missing"
  fi

  if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found. 'ccp install' will fail until Claude Code is installed."
  fi
}

download() {
  _dl_url="$1" _dl_dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$_dl_url" -o "$_dl_dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$_dl_dest" "$_dl_url"
  else
    die "curl or wget required for remote install"
  fi
}

install_ccp() {
  mkdir -p "$INSTALL_DIR"

  if [ "$LOCAL_MODE" = 1 ]; then
    cp "$CCP_SOURCE" "$INSTALL_DIR/ccp"
  else
    info "Downloading ccp from GitHub..."
    download "$REPO_URL/ccp" "$INSTALL_DIR/ccp"
  fi

  chmod +x "$INSTALL_DIR/ccp"
  info "Installed ccp to $INSTALL_DIR/ccp"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      warn "$INSTALL_DIR is not in your PATH"
      warn "Add to your shell profile: export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

uninstall() {
  resolve_install_dir

  if [ -f "$INSTALL_DIR/ccp" ]; then
    rm "$INSTALL_DIR/ccp"
    info "Removed $INSTALL_DIR/ccp"
  else
    warn "ccp not found at $INSTALL_DIR/ccp"
  fi

  warn "Profile data at ~/.claude-profiles was not touched."
  warn "Symlinks in ~/.claude still point into profile dirs."
  warn "Remove manually if desired."

  info "Uninstall complete"
  exit 0
}

if [ "$UNINSTALL" = 1 ]; then
  uninstall
fi

resolve_install_dir
check_deps
install_ccp

if [ "$RUN_INIT" = 1 ]; then
  info "Running ccp init..."
  "$INSTALL_DIR/ccp" init
fi

info "ccp v${VERSION} installed successfully"
if [ "$RUN_INIT" != 1 ]; then
  info "Next: run 'ccp init' to migrate existing ~/.claude config into profile 'main'"
fi

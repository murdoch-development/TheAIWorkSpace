#!/usr/bin/env bash
# bootstrap.sh - Bootstrap installer for The AI Workspace.
#
# Checks and installs dependencies, extracts the ws profile to
# ~/.config/opencode/profiles/ws, installs the Zellij helper
# scripts and config, then runs setup-workspace.sh which
# handles everything else.
#
# Just run this script - it will prompt you through the rest.
#
# Usage:
#   bash bootstrap.sh

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

printf '\n'
info "  ============================================"
info "     The AI Workspace - Bootstrap Installer    "
info "  ============================================"
printf '\n'

# === Step 1: Install Dependencies ===

warn "  Step 1: Checking and installing dependencies..."
INSTALL_DEPS="$SCRIPT_DIR/install-deps.sh"
if [ -f "$INSTALL_DEPS" ]; then
    bash "$INSTALL_DEPS"
else
    err "  [X]  install-deps.sh not found"
    exit 1
fi

# Refresh PATH for current session (npm may have just been installed)
if command -v npm >/dev/null 2>&1; then
    npm_prefix=$(npm prefix -g 2>/dev/null || true)
    if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ]; then
        npm_bin="$npm_prefix/bin"
        case ":$PATH:" in
            *":$npm_bin:"*) ;;
            *) PATH="$npm_bin:$PATH"; export PATH ;;
        esac
    fi
fi

printf '\n'

# === Step 2: Install the ws profile ===

warn "  Step 2: Installing OpenCode profile..."

CONFIG_BASE="${XDG_CONFIG_HOME:-}"
if [ -z "$CONFIG_BASE" ]; then CONFIG_BASE="$HOME/.config"; fi
PROFILE_DEST="$CONFIG_BASE/opencode/profiles/ws"
PROFILE_SOURCE="$SCRIPT_DIR/profile"

if [ -d "$PROFILE_SOURCE" ]; then
    if [ -d "$PROFILE_DEST" ]; then
        warn "  [!]  Profile 'ws' already exists at: $PROFILE_DEST"
        printf '\033[36m  Overwrite? (y/N): \033[0m'
        overwrite=""
        read -r overwrite || overwrite=""
        if [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; then
            rm -rf "$PROFILE_DEST"
            cp -R "$PROFILE_SOURCE" "$PROFILE_DEST"
            ok "  [OK] Profile overwritten"
        else
            note "  [..] Keeping existing profile"
        fi
    else
        PROFILE_PARENT="${PROFILE_DEST%/*}"
        if [ ! -d "$PROFILE_PARENT" ]; then
            mkdir -p "$PROFILE_PARENT"
        fi
        cp -R "$PROFILE_SOURCE" "$PROFILE_DEST"
        ok "  [OK] Profile installed"
    fi

    # Install plugin dependencies (npm is now available from Step 1)
    printf '\n'
    note "  Installing plugin dependencies..."
    rc=0
    (cd "$PROFILE_DEST" && npm install 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        warn "  [!]  npm install failed (exit $rc)."
        note "       Run manually: cd \"$PROFILE_DEST\" && npm install"
    else
        ok "  [OK] Dependencies installed"
    fi
else
    err "  [X]  Profile not found in package. Contact the sender."
fi

# === Step 2b: Install Zellij scripts and config ===

printf '\n'
warn "  Installing Zellij helper scripts and config..."

ZELLIJ_CONFIG_BASE="${XDG_CONFIG_HOME:-}"
if [ -z "$ZELLIJ_CONFIG_BASE" ]; then ZELLIJ_CONFIG_BASE="$HOME/.config"; fi
ZELLIJ_CONFIG_DIR="$ZELLIJ_CONFIG_BASE/zellij"
ZELLIJ_SCRIPTS_DIR="$ZELLIJ_CONFIG_DIR/scripts"

if [ ! -d "$ZELLIJ_SCRIPTS_DIR" ]; then
    mkdir -p "$ZELLIJ_SCRIPTS_DIR"
fi

NEW_BUILD_AGENT_SRC="$SCRIPT_DIR/new-build-agent.sh"
if [ -f "$NEW_BUILD_AGENT_SRC" ]; then
    cp "$NEW_BUILD_AGENT_SRC" "$ZELLIJ_SCRIPTS_DIR/new-build-agent.sh"
    ok "  [OK] new-build-agent.sh"
else
    warn "  [!]  new-build-agent.sh not found (skipping)"
fi

# Install config-ws.kdl (Zellij config with ws-specific keybinds)
CONFIG_WS_SRC="$SCRIPT_DIR/config-ws.kdl"
if [ -f "$CONFIG_WS_SRC" ]; then
    cp "$CONFIG_WS_SRC" "$ZELLIJ_CONFIG_DIR/config-ws.kdl"
    ok "  [OK] config-ws.kdl"
else
    warn "  [!]  config-ws.kdl not found (skipping)"
fi

# Add dirs to PATH (persistent in the shell rc file + current session)
ensure_path_persistent() {
    dir="$1"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$dir:$PATH"; export PATH ;;
    esac
    rc_file=""
    case "${SHELL:-}" in
        *zsh) rc_file="$HOME/.zshrc" ;;
        *) rc_file="$HOME/.bashrc" ;;
    esac
    if [ -f "$rc_file" ] && grep -F -q -- "$dir" "$rc_file"; then
        note "  [..] $dir already on PATH"
        return 0
    fi
    printf 'export PATH="%s:$PATH"\n' "$dir" >> "$rc_file"
    ok "  [OK] Added $dir to PATH ($rc_file, new terminals)"
}

# ~/.local/bin hosts the prebuilt Zellij binary on Linux (if installed there)
if [ -f "$HOME/.local/bin/zellij" ]; then
    ensure_path_persistent "$HOME/.local/bin"
fi

# Zellij scripts dir (so new-build-agent.sh is discoverable by keybinds)
ensure_path_persistent "$ZELLIJ_SCRIPTS_DIR"

printf '\n'

# === Step 3: Run workspace setup ===

warn "  Step 3: Workspace setup..."
SETUP_WORKSPACE="$SCRIPT_DIR/setup-workspace.sh"
if [ -f "$SETUP_WORKSPACE" ]; then
    bash "$SETUP_WORKSPACE" --skip-deps --force
else
    err "  [X]  setup-workspace.sh not found"
fi

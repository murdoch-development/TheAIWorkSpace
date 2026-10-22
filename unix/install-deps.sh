#!/usr/bin/env bash
# install-deps.sh - Installs all dependencies for the multi-agent OpenCode workspace.
#
# Checks and installs:
# - Git (brew / apt / dnf / pacman)
# - Node.js LTS (brew / apt / dnf / pacman)
# - Zellij (brew on macOS; prebuilt musl tarball -> ~/.local/bin on Linux)
# - Backlog.md (npm global, pinned @1)
# - OCX (npm global, pinned @2.0.15 - frozen OpenCode V1 client)
# - OpenCode (npm global, pinned @1)
#
# Supports macOS and Linux. Safe to re-run: skips already-installed tools.
#
# Usage:
#   bash install-deps.sh
#   bash install-deps.sh --skip-optional

set -eu

SKIP_OPTIONAL=0
for arg in "$@"; do
    case "$arg" in
        --skip-optional) SKIP_OPTIONAL=1 ;;
        *)
            printf 'Unknown argument: %s\n' "$arg" >&2
            printf 'Usage: bash install-deps.sh [--skip-optional]\n' >&2
            exit 1
            ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

ok()      { printf '\033[32m%s\033[0m\n' "$*"; }
red()     { printf '\033[31m%s\033[0m\n' "$*"; }
info()    { printf '\033[36m%s\033[0m\n' "$*"; }
warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
note()    { printf '\033[90m%s\033[0m\n' "$*"; }
section() { printf '\033[97m%s\033[0m\n' "$*"; }
err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# === OS Detection ===

OS_KERNEL=$(uname -s)
OS=""
case "$OS_KERNEL" in
    Darwin)
        OS="macOS"
        ;;
    Linux)
        OS="Linux"
        ;;
    *)
        err "Unsupported OS: $OS_KERNEL"
        err "This installer supports macOS and Linux."
        err "Windows users: run install-deps.ps1 in PowerShell instead."
        exit 1
        ;;
esac

# === Package Manager Detection ===

PM=""
SUDO=""
if [ "$OS" = "macOS" ]; then
    if ! have brew; then
        err "Homebrew not found."
        note "      Install it from https://brew.sh, then re-run this script."
        exit 1
    fi
else
    if have apt-get; then
        PM="apt"
    elif have dnf; then
        PM="dnf"
    elif have pacman; then
        PM="pacman"
    else
        err "No supported package manager found (apt, dnf, or pacman)."
        exit 1
    fi
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif have sudo; then
        SUDO="sudo"
    else
        err "sudo not found. Re-run as root, or install sudo first."
        exit 1
    fi
fi

pm_install() {
    # $@ = packages to install
    if [ "$OS" = "macOS" ]; then
        note "      brew install $*"
        brew install "$@" || true
        return 0
    fi
    case "$PM" in
        apt)
            note "      $SUDO apt-get install -y $*"
            $SUDO apt-get install -y "$@" || true
            ;;
        dnf)
            note "      $SUDO dnf install -y $*"
            $SUDO dnf install -y "$@" || true
            ;;
        pacman)
            note "      $SUDO pacman -S --noconfirm $*"
            $SUDO pacman -S --noconfirm "$@" || true
            ;;
    esac
    return 0
}

refresh_npm_bin() {
    have npm || return 0
    prefix_dir=$(npm prefix -g 2>/dev/null || true)
    if [ -n "$prefix_dir" ] && [ -d "$prefix_dir/bin" ]; then
        bin_dir="$prefix_dir/bin"
        case ":$PATH:" in
            *":$bin_dir:"*) ;;
            *) PATH="$bin_dir:$PATH"; export PATH ;;
        esac
    fi
    return 0
}

install_zellij() {
    if [ "$OS" = "macOS" ]; then
        note "      brew install zellij"
        brew install zellij || true
        return 0
    fi
    arch=""
    case "$(uname -m)" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *)
            red "       [X]  No prebuilt Zellij for architecture: $(uname -m)"
            return 1
            ;;
    esac
    if ! have curl; then
        red "       [X]  curl not found. Install it first:"
        note "      $SUDO apt-get install -y curl    # or: dnf install -y curl / pacman -S curl"
        return 1
    fi
    url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-$arch-unknown-linux-musl.tar.gz"
    tmp_dir=$(mktemp -d)
    mkdir -p "$HOME/.local/bin"
    note "      curl -fsSL $url | tar -xz"
    if curl -fsSL "$url" | tar -xz -C "$tmp_dir"; then
        if [ -f "$tmp_dir/zellij" ]; then
            mv "$tmp_dir/zellij" "$HOME/.local/bin/zellij"
            rm -rf "$tmp_dir"
        else
            found=$(find "$tmp_dir" -type f -name zellij 2>/dev/null | head -n 1)
            if [ -n "$found" ]; then
                mv "$found" "$HOME/.local/bin/zellij"
            fi
            rm -rf "$tmp_dir"
        fi
    else
        rm -rf "$tmp_dir"
        return 1
    fi
    if [ -f "$HOME/.local/bin/zellij" ]; then
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
        esac
        return 0
    fi
    return 1
}

# === Start ===

printf '\n'
info "  ============================================"
info "     Multi-Agent Workspace - Dependency Setup "
info "  ============================================"
note "  OS: $OS"
printf '\n'

# === 1. Git ===

section "  [1/6] Git"
if have git; then
    git_ver=$(git --version 2>&1)
    ok "       [OK] $git_ver"
else
    warn "       [..] Installing Git..."
    pm_install "git"
    if have git; then
        ok "       [OK] Git installed"
    else
        red "       [X]  Git install failed. Install manually."
    fi
fi

# === 2. Node.js ===

section "  [2/6] Node.js (LTS)"
if have node; then
    node_ver=$(node --version 2>&1)
    ok "       [OK] Node.js $node_ver"
else
    warn "       [..] Installing Node.js LTS..."
    if [ "$OS" = "macOS" ]; then
        pm_install "node"
    else
        pm_install "nodejs" "npm"
    fi
    if have node; then
        ok "       [OK] Node.js installed"
    else
        red "       [X]  Node.js install failed. Install manually."
    fi
fi
if have node; then
    node_major=$(printf '%s' "$(node --version 2>&1)" | sed -E 's/^v([0-9]+)\..*$/\1/')
    case "$node_major" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$node_major" -lt 18 ]; then
                warn "       [!]  Node.js $(node --version 2>&1) is below 18."
                note "      Some tools need Node 18+. Consider NodeSource: https://github.com/nodesource/distributions"
            fi
            ;;
    esac
fi
refresh_npm_bin

# === 3. Zellij (optional) ===

if [ "$SKIP_OPTIONAL" = "1" ]; then
    note "  [3/6] Zellij (skipped --skip-optional)"
else
    section "  [3/6] Zellij"
    if have zellij; then
        zellij_ver=$(zellij --version 2>&1)
        ok "       [OK] $zellij_ver"
    else
        warn "       [..] Installing Zellij..."
        install_zellij || true
        if have zellij; then
            ok "       [OK] Zellij installed"
        else
            warn "       [!]  Zellij install failed (optional). Install manually if needed."
        fi
    fi
fi

# === 4. Backlog.md ===

section "  [4/6] Backlog.md"
if have backlog; then
    ok "       [OK] Backlog.md CLI"
else
    warn "       [..] Installing Backlog.md (npm global)..."
    note "      npm install -g backlog.md@1"
    npm install -g backlog.md@1 2>&1 | while IFS= read -r line; do note "      $line"; done || true
    refresh_npm_bin
    if have backlog; then
        ok "       [OK] Backlog.md installed"
    else
        red "       [X]  Backlog.md install failed. Run: npm install -g backlog.md@1"
    fi
fi

# === 5. OCX ===

section "  [5/6] OCX (OpenCode profile manager)"
if have ocx; then
    ok "       [OK] OCX"
else
    warn "       [..] Installing OCX (npm global)..."
    note "      npm install -g ocx@2.0.15"
    npm install -g ocx@2.0.15 2>&1 | while IFS= read -r line; do note "      $line"; done || true
    refresh_npm_bin
    if have ocx; then
        ok "       [OK] OCX installed"
    else
        red "       [X]  OCX install failed. Run: npm install -g ocx@2.0.15"
        note "            You may need to restart your terminal first."
    fi
fi

# === 6. OpenCode ===

section "  [6/6] OpenCode"
if have opencode; then
    ok "       [OK] OpenCode"
else
    warn "       [..] Installing OpenCode..."
    note "      npm install -g opencode-ai@1"
    npm install -g opencode-ai@1 2>&1 | while IFS= read -r line; do note "      $line"; done || true
    refresh_npm_bin
    if have opencode; then
        ok "       [OK] OpenCode installed"
    else
        red "       [X]  OpenCode install failed. Run: npm install -g opencode-ai@1"
        note "            You may need to restart your terminal first."
    fi
fi

# === Summary ===

printf '\n'
info "  ============================================"
all_ok=1
for cmd in git node backlog ocx opencode; do
    if have "$cmd"; then
        ok "  [OK] $cmd"
    else
        red "  [X]  $cmd"
        all_ok=0
    fi
done
if [ "$SKIP_OPTIONAL" != "1" ]; then
    if have zellij; then
        ok "  [OK] zellij (optional)"
    else
        warn "  [!]  zellij (optional, not installed)"
    fi
fi
printf '\n'
if [ "$all_ok" = "1" ]; then
    ok "  All core dependencies installed!"
else
    warn "  Some dependencies failed. Install manually and re-run."
fi
printf '\n'
exit 0

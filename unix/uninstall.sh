#!/usr/bin/env bash
# uninstall.sh - Uninstalls The AI Workspace - undoes everything bootstrap.sh did.
#
# Phase 1: Infrastructure (undo bootstrap.sh)
#   - Remove ws profile (~/.config/opencode/profiles/ws/)
#   - Remove Zellij scripts (new-build-agent.sh)
#   - Remove config-ws.kdl from Zellij config dir
#   - Remove Zellij scripts dir (+ ~/.local/bin) PATH entries from the shell rc
#   - Uninstall ocx (npm uninstall -g ocx)
#   - Uninstall opencode-ai (npm uninstall -g opencode-ai)
#   - Uninstall backlog.md (npm uninstall -g backlog.md)
#   (Bun is not touched - the bash installer never installs it.)
#
# Phase 2: Workspace artifacts (undo setup-workspace.sh)
#   - Remove generated Zellij layouts + configs
#   - Remove repo workflow files (scripts/, backlog/, SOFTWARE_ENGINEERING_PRINCIPLES.md)
#
# Each step prompts y/n.
#
# Usage:
#   bash uninstall.sh

set -eu

ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }
section() { printf '\033[97m%s\033[0m\n' "$*"; }

# === OS Detection ===

OS_KERNEL=$(uname -s)
OS=""
case "$OS_KERNEL" in
    Darwin) OS="macOS" ;;
    *) OS="Linux" ;;
esac

# === Helpers ===

ask_yesno() {
    # $1 = prompt; returns 0 if answered y/Y
    printf '\033[36m  %s (y/N): \033[0m' "$1"
    response=""
    read -r response || response=""
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        return 0
    fi
    return 1
}

remove_safely() {
    if [ -e "$1" ]; then
        rm -rf "$1" 2>/dev/null || true
        if [ ! -e "$1" ]; then
            ok "       [OK] Removed: $1"
        else
            warn "       [!]  Could not fully remove: $1"
        fi
    else
        note "       [..] Not found: $1"
    fi
}

# === Banner ===

printf '\n'
info "  ============================================"
info "     The AI Workspace - Uninstall              "
info "  ============================================"
note "  OS: $OS"
printf '\n'
note "  Each step will ask y/n. Answer N to skip."
printf '\n'

# === Resolve paths ===

CONFIG_BASE="${XDG_CONFIG_HOME:-}"
if [ -z "$CONFIG_BASE" ]; then CONFIG_BASE="$HOME/.config"; fi

PROFILE_DEST="$CONFIG_BASE/opencode/profiles/ws"
ZELLIJ_CONFIG_DIR="$CONFIG_BASE/zellij"
ZELLIJ_SCRIPTS_DIR="$ZELLIJ_CONFIG_DIR/scripts"
ZELLIJ_LAYOUTS_DIR="$ZELLIJ_CONFIG_DIR/layouts"

RC_FILE=""
case "${SHELL:-}" in
    *zsh) RC_FILE="$HOME/.zshrc" ;;
    *) RC_FILE="$HOME/.bashrc" ;;
esac

# === Phase 1: Infrastructure ===

warn "  -- Phase 1: Infrastructure ----------------------"
printf '\n'

# 1. ws profile
if ask_yesno "Remove ws profile? ($PROFILE_DEST)"; then
    remove_safely "$PROFILE_DEST"
fi
printf '\n'

# 2. Zellij scripts - new-build-agent.sh
if ask_yesno "Remove Zellij helper script? (new-build-agent.sh)"; then
    remove_safely "$ZELLIJ_SCRIPTS_DIR/new-build-agent.sh"
    # Remove scripts dir if now empty
    if [ -d "$ZELLIJ_SCRIPTS_DIR" ]; then
        if [ -z "$(ls -A "$ZELLIJ_SCRIPTS_DIR" 2>/dev/null)" ]; then
            if ask_yesno "  Scripts dir is now empty. Remove it? ($ZELLIJ_SCRIPTS_DIR)"; then
                remove_safely "$ZELLIJ_SCRIPTS_DIR"
            fi
        fi
    fi
fi
printf '\n'

# 3. config-ws.kdl
if ask_yesno "Remove config-ws.kdl from Zellij config?"; then
    remove_safely "$ZELLIJ_CONFIG_DIR/config-ws.kdl"
fi
printf '\n'

# 4. Remove PATH entries from the shell rc file
if [ -f "$RC_FILE" ] && grep -F -q -- "export PATH=\"$ZELLIJ_SCRIPTS_DIR:" "$RC_FILE"; then
    if ask_yesno "Remove Zellij scripts dir from PATH? ($ZELLIJ_SCRIPTS_DIR in $RC_FILE)"; then
        tmp="$RC_FILE.ws-uninstall-tmp"
        grep -v -F -- "export PATH=\"$ZELLIJ_SCRIPTS_DIR:" "$RC_FILE" > "$tmp" || true
        mv "$tmp" "$RC_FILE"
        ok "       [OK] Removed $ZELLIJ_SCRIPTS_DIR from PATH ($RC_FILE)"
    fi
else
    note "  [..] Zellij scripts dir not on PATH (skipping)"
fi
if [ -f "$RC_FILE" ] && grep -F -q -- "export PATH=\"$HOME/.local/bin:" "$RC_FILE"; then
    if ask_yesno "Remove ~/.local/bin from PATH? (in $RC_FILE)"; then
        tmp="$RC_FILE.ws-uninstall-tmp"
        grep -v -F -- "export PATH=\"$HOME/.local/bin:" "$RC_FILE" > "$tmp" || true
        mv "$tmp" "$RC_FILE"
        ok "       [OK] Removed ~/.local/bin from PATH ($RC_FILE)"
    fi
fi
printf '\n'

# 5. Uninstall ocx
if ask_yesno "Uninstall OCX? (npm uninstall -g ocx)"; then
    if command -v npm >/dev/null 2>&1; then
        npm uninstall -g ocx 2>&1 | while IFS= read -r line; do note "      $line"; done || true
        ok "       [OK] OCX uninstalled"
    else
        err "       [X]  npm not found. Run manually: npm uninstall -g ocx"
    fi
fi
printf '\n'

# 6. Uninstall opencode-ai
if ask_yesno "Uninstall OpenCode? (npm uninstall -g opencode-ai)"; then
    if command -v npm >/dev/null 2>&1; then
        npm uninstall -g opencode-ai 2>&1 | while IFS= read -r line; do note "      $line"; done || true
        ok "       [OK] OpenCode uninstalled"
    else
        err "       [X]  npm not found. Run manually: npm uninstall -g opencode-ai"
    fi
fi
printf '\n'

# 7. Uninstall backlog.md
if ask_yesno "Uninstall Backlog.md? (npm uninstall -g backlog.md)"; then
    if command -v npm >/dev/null 2>&1; then
        npm uninstall -g backlog.md 2>&1 | while IFS= read -r line; do note "      $line"; done || true
        ok "       [OK] Backlog.md uninstalled"
    else
        err "       [X]  npm not found. Run manually: npm uninstall -g backlog.md"
    fi
fi
printf '\n'

# === Phase 2: Workspace Artifacts ===

warn "  -- Phase 2: Workspace Artifacts ----------------"
printf '\n'

# 8. Remove generated Zellij layouts and configs
if ask_yesno "Remove generated Zellij layouts and configs?"; then
    found_any=0

    # Layouts: *.kdl in layouts dir
    if [ -d "$ZELLIJ_LAYOUTS_DIR" ]; then
        while IFS= read -r layout; do
            found_any=1
            note "       Layout: $(basename "$layout")"
            remove_safely "$layout"
        done < <(find "$ZELLIJ_LAYOUTS_DIR" -maxdepth 1 -name '*.kdl' -type f 2>/dev/null)
    fi

    # Configs: config-*.kdl in config dir (but NOT config-ws.kdl, already handled above)
    while IFS= read -r config; do
        found_any=1
        note "       Config: $(basename "$config")"
        remove_safely "$config"
    done < <(find "$ZELLIJ_CONFIG_DIR" -maxdepth 1 -name 'config-*.kdl' -type f ! -name 'config-ws.kdl' 2>/dev/null)

    if [ "$found_any" = "0" ]; then
        note "       [..] No generated layouts or configs found"
    fi
fi
printf '\n'

# 9. Remove repo workflow files
if ask_yesno "Remove repo workflow files? (scripts/, backlog/, SOFTWARE_ENGINEERING_PRINCIPLES.md)"; then
    printf '\n'
    section "    Enter repo paths to clean (one per line, empty line to finish):"
    repos=()
    while :; do
        printf '\033[36m    > \033[0m'
        repo_path=""
        read -r repo_path || repo_path=""
        if [ -z "$repo_path" ]; then break; fi
        case "$repo_path" in
            "~") repo_path="$HOME" ;;
            "~/"*) repo_path="$HOME${repo_path:1}" ;;
        esac
        if [ ! -d "$repo_path" ]; then
            err "      [X] Path does not exist: $repo_path"
            continue
        fi
        repos+=("$repo_path")
    done

    if [ "${#repos[@]}" -gt 0 ]; then
        for repo in "${repos[@]}"; do
            printf '\n'
            info "    Repo: $repo"

            # scripts/ dir
            if [ -d "$repo/scripts" ]; then
                if ask_yesno "    Remove scripts/ dir?"; then
                    remove_safely "$repo/scripts"
                fi
            else
                note "      [..] scripts/ not found"
            fi

            # backlog/ dir (warn about data)
            if [ -d "$repo/backlog" ]; then
                err "    WARNING: backlog/ contains board data and worktrees!"
                if ask_yesno "    Remove backlog/ dir?"; then
                    remove_safely "$repo/backlog"
                fi
            else
                note "      [..] backlog/ not found"
            fi

            # SOFTWARE_ENGINEERING_PRINCIPLES.md
            if [ -f "$repo/SOFTWARE_ENGINEERING_PRINCIPLES.md" ]; then
                if ask_yesno "    Remove SOFTWARE_ENGINEERING_PRINCIPLES.md?"; then
                    remove_safely "$repo/SOFTWARE_ENGINEERING_PRINCIPLES.md"
                fi
            else
                note "      [..] SOFTWARE_ENGINEERING_PRINCIPLES.md not found"
            fi

            # Remove backlog/worktrees/ from .gitignore
            gitignore="$repo/.gitignore"
            if [ -f "$gitignore" ]; then
                if grep -qE '^[[:space:]]*backlog/worktrees/[[:space:]]*$' "$gitignore"; then
                    if ask_yesno "    Remove backlog/worktrees/ from .gitignore?"; then
                        tmp="$gitignore.ws-tmp"
                        grep -vE '^[[:space:]]*backlog/worktrees/[[:space:]]*$' "$gitignore" > "$tmp" || true
                        mv "$tmp" "$gitignore"
                        ok "       [OK] Removed backlog/worktrees/ from .gitignore"
                    fi
                fi
            fi
        done
    fi
fi
printf '\n'

# === Summary ===

printf '\n'
info "  ============================================"
ok "  Uninstall complete!"
info "  ============================================"
printf '\n'
note "  Note: Git, Node.js, and Zellij were NOT uninstalled"
note "  (they may be used by other projects)."
note "  To remove them manually:"
if [ "$OS" = "macOS" ]; then
    note "    Git:    brew uninstall git"
    note "    Node:   brew uninstall node"
    note "    Zellij: brew uninstall zellij"
else
    note "    Git:    sudo apt remove git     # or: sudo dnf remove git / sudo pacman -R git"
    note "    Node:   sudo apt remove nodejs  # or: sudo dnf remove nodejs / sudo pacman -R nodejs"
    note "    Zellij: rm -f ~/.local/bin/zellij   # (prebuilt binary)"
fi
printf '\n'

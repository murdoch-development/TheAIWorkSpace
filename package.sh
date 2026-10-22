#!/usr/bin/env bash
# package.sh - Creates a shareable zip of The AI Workspace for any target OS.
#
# Any OS can build all three zips in its native shell:
#   windows: PowerShell tree (root .ps1 scripts + profile/)
#   macos / linux: bash tree (unix/ scripts + unix/profile/)
#
# macos and linux zips share the bash tree and differ only in QUICKSTART.txt.
# All text in macos/linux zips is LF-normalized (bash must not see CRLF).
# Profile contents are staged from the REPO tree (profile/ and unix/profile/),
# never from an installed machine.
#
# Usage:
#   bash package.sh                      # build all three zips
#   bash package.sh windows|macos|linux  # build one
#   bash package.sh --dry-run            # stage + list contents, no zip
#
# Requires: zip (Info-ZIP) for real builds. --dry-run works without it.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DATE=$(date +%Y-%m-%d)
STAGING_ROOT="${TMPDIR:-/tmp}/TheAIWorkSpace-staging"
DRY_RUN=0
TARGET="all"

while [ $# -gt 0 ]; do
    case "$1" in
        windows|macos|linux|all) TARGET="$1"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            printf 'Usage: bash package.sh [windows|macos|linux|all] [--dry-run]\n' >&2
            exit 1
            ;;
    esac
done

ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

normalize_lf() {
    # $1 = dir; strips CR from every file (text trees only)
    while IFS= read -r f; do
        tmp="$f.lf-tmp"
        tr -d '\r' < "$f" > "$tmp"
        mv "$tmp" "$f"
    done < <(find "$1" -type f)
}

WINDOWS_SCRIPTS="bootstrap.ps1 install-deps.ps1 setup-repo.ps1 generate-layout.ps1 setup-workspace.ps1 new-build-agent.ps1 config-ws.kdl package.ps1 uninstall.ps1 README.md"
UNIX_SCRIPTS="bootstrap.sh install-deps.sh setup-repo.sh generate-layout.sh setup-workspace.sh new-build-agent.sh uninstall.sh config-ws.kdl"

STAGING=""

stage_profile() {
    # $1 = profile source dir (repo tree)
    src="$1"
    if [ -d "$src" ]; then
        cp -R "$src" "$STAGING/profile"
        rm -rf "$STAGING/profile/.ocx" "$STAGING/profile/node_modules" "$STAGING/profile/bun.lock" "$STAGING/profile/package-lock.json" 2>/dev/null || true
        rm -f "$STAGING/profile/.DS_Store" 2>/dev/null || true
        ok "[OK] Profile included"
    else
        warn "ws profile not found at: $src"
        warn "Package will not include the profile. Colleague will need it separately."
    fi
}

write_quickstart() {
    # $1 = os, $2 = staging dir
    qs_os="$1"
    qs_dir="$2"
    qs_file="$qs_dir/QUICKSTART.txt"
    if [ "$qs_os" = "windows" ]; then
        cat > "$qs_file" <<'QS_WINDOWS_EOF'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)

2. Open PowerShell in the extracted folder:
   - Right-click in the folder -> "Open in Terminal"
   - Or: Open PowerShell, cd to the folder

3. Run:
   .\bootstrap.ps1

4. Follow the prompts. It will (in order):
   a. Fix PowerShell execution policy if needed (Windows)
   b. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   c. Install the OpenCode "ws" profile (agents, skills, plugins)
   d. Ask for your project name and repo paths
   e. Set up each repo with workflow scripts and Backlog.md
   f. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with -Force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$env:APPDATA\Zellij\config\config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
On Windows, freshly installed npm may not be on PATH in the
current session. If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: .\bootstrap.ps1

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "scripts can't run" -> The bootstrap fixes this automatically on Windows
- "npm not found after install" -> Restart terminal, re-run .\bootstrap.ps1
- "zellij not found" -> See https://zellij.dev/documentation/installation
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.ps1 did, run:
   .\uninstall.ps1   (Windows)
   pwsh ./uninstall.ps1   (macOS/Linux)

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
QS_WINDOWS_EOF
    elif [ "$qs_os" = "macos" ]; then
        cat > "$qs_file" <<'QS_MACOS_EOF'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)
PREREQUISITE (macOS): Homebrew is used for dependency installs (git, node,
zellij). Install it from https://brew.sh if you don't have it.

2. Open a terminal in the extracted folder:
   - Right-click the folder -> "Open Terminal Here" (many file managers)
   - Or: Open your terminal app and cd to the folder

3. Run:
   bash bootstrap.sh

4. Follow the prompts. It will (in order):
   a. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   b. Install the OpenCode "ws" profile (agents, skills, plugins)
   c. Ask for your project name and repo paths
   d. Set up each repo with workflow scripts and Backlog.md
   e. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with --force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$HOME/.config/zellij/config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
Freshly installed npm may not be on PATH in the current session.
If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: bash bootstrap.sh

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "Homebrew not found" -> Install it from https://brew.sh, then re-run bash bootstrap.sh
- "npm not found after install" -> Restart terminal, re-run bash bootstrap.sh
- "zellij not found" -> See https://zellij.dev/documentation/installation
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.sh did, run:
   bash uninstall.sh

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
QS_MACOS_EOF
    else
        cat > "$qs_file" <<'QS_LINUX_EOF'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)
PREREQUISITE (Linux): System packages install with sudo via your package
manager: apt (Debian/Ubuntu), dnf (Fedora/RHEL), or pacman (Arch).
Zellij installs as a prebuilt binary to ~/.local/bin.

2. Open a terminal in the extracted folder:
   - Right-click the folder -> "Open Terminal Here" (many file managers)
   - Or: Open your terminal app and cd to the folder

3. Run:
   bash bootstrap.sh

4. Follow the prompts. It will (in order):
   a. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   b. Install the OpenCode "ws" profile (agents, skills, plugins)
   c. Ask for your project name and repo paths
   d. Set up each repo with workflow scripts and Backlog.md
   e. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with --force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$HOME/.config/zellij/config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
Freshly installed npm may not be on PATH in the current session.
If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: bash bootstrap.sh

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "sudo: command not found" -> Install sudo, or run as root
- "No supported package manager" -> Supported: apt, dnf, pacman
- "npm not found after install" -> Restart terminal, re-run bash bootstrap.sh
- "zellij not found" -> Restart terminal so ~/.local/bin is on PATH
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.sh did, run:
   bash uninstall.sh

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
QS_LINUX_EOF
    fi
    ok "[OK] QUICKSTART.txt created ($qs_os)"
}

build_one() {
    os="$1"
    zip_name="TheAIWorkSpace-$DATE-$os.zip"
    zip_path="$(pwd)/$zip_name"
    STAGING="$STAGING_ROOT/staging-$os"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"

    if [ "$os" = "windows" ]; then
        for s in $WINDOWS_SCRIPTS; do
            if [ -f "$SCRIPT_DIR/$s" ]; then
                cp "$SCRIPT_DIR/$s" "$STAGING/"
            else
                warn "Missing: $s"
            fi
        done
        stage_profile "$SCRIPT_DIR/profile"
    else
        for s in $UNIX_SCRIPTS; do
            if [ -f "$SCRIPT_DIR/unix/$s" ]; then
                cp "$SCRIPT_DIR/unix/$s" "$STAGING/"
            else
                warn "Missing: unix/$s"
            fi
        done
        if [ -f "$SCRIPT_DIR/package.sh" ]; then
            cp "$SCRIPT_DIR/package.sh" "$STAGING/"
        else
            warn "Missing: package.sh"
        fi
        # README.md from the repo root (same doc set as the windows zip)
        if [ -f "$SCRIPT_DIR/README.md" ]; then
            cp "$SCRIPT_DIR/README.md" "$STAGING/"
        else
            warn "Missing: README.md"
        fi
        stage_profile "$SCRIPT_DIR/unix/profile"
    fi

    write_quickstart "$os" "$STAGING"

    if [ "$os" != "windows" ]; then
        normalize_lf "$STAGING"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf '\n'
        info "[DRY-RUN] Would zip -> $zip_path"
        info "[DRY-RUN] Staged contents ($os):"
        (cd "$STAGING" && find . -type f | sed 's|^\./||' | sort)
        printf '\n'
        return 0
    fi

    if ! command -v zip >/dev/null 2>&1; then
        err "zip not found. Install it first:"
        note "      Debian/Ubuntu: sudo apt-get install -y zip"
        note "      Fedora/RHEL:   sudo dnf install -y zip"
        note "      Arch:          sudo pacman -S zip"
        note "      macOS:         brew install zip"
        return 1
    fi

    rm -f "$zip_path"
    (cd "$STAGING" && zip -r -q "$zip_path" .)
    rm -rf "$STAGING"

    zip_size=$(wc -c < "$zip_path" | tr -d '[:space:]')
    zip_kb=$(( zip_size / 1024 ))
    printf '\n'
    ok "[OK] Package created: $zip_path (${zip_kb} KB)"
    info "     Send this zip to your colleague."
    if [ "$os" = "windows" ]; then
        info "     They extract it and run: .\\bootstrap.ps1"
    else
        info "     They extract it and run: bash bootstrap.sh"
    fi
    printf '\n'
}

case "$TARGET" in
    all)
        build_one windows
        build_one macos
        build_one linux
        ;;
    *)
        build_one "$TARGET"
        ;;
esac

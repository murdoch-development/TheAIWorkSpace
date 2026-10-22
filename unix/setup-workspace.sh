#!/usr/bin/env bash
# setup-workspace.sh - Full workspace setup orchestrator.
#
# One-command setup for a multi-agent OpenCode workspace. Calls the other 3 scripts:
# 1. install-deps.sh    - ensures git, node, zellij, backlog, ocx, opencode are installed
# 2. setup-repo.sh     - for each repo: installs scripts, AGENTS.md, backlog.md
# 3. generate-layout.sh - creates a zellij layout with tabs for each repo
#
# Designed to be shared with team members. They run this one script and get the full setup.
#
# Usage:
#   bash setup-workspace.sh                                          # interactive - prompts for everything
#   bash setup-workspace.sh --project-name "My App" --repos ~/a --repos ~/b
#   bash setup-workspace.sh --project-name "My App" --repos ~/a --skip-deps --force

set -eu

PROJECT_NAME=""
LAYOUT_NAME=""
REPOS=()
PROFILE_NAME="ws"
PLAN_DIR=""
SKIP_DEPS=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project-name)
            if [ $# -lt 2 ]; then printf 'Error: --project-name requires a value\n' >&2; exit 1; fi
            PROJECT_NAME="$2"; shift 2 ;;
        --project-name=*)
            PROJECT_NAME="${1#*=}"; shift ;;
        --layout-name)
            if [ $# -lt 2 ]; then printf 'Error: --layout-name requires a value\n' >&2; exit 1; fi
            LAYOUT_NAME="$2"; shift 2 ;;
        --layout-name=*)
            LAYOUT_NAME="${1#*=}"; shift ;;
        --repos)
            if [ $# -lt 2 ]; then printf 'Error: --repos requires a value\n' >&2; exit 1; fi
            REPOS+=("$2"); shift 2 ;;
        --repos=*)
            REPOS+=("${1#*=}"); shift ;;
        --profile-name)
            if [ $# -lt 2 ]; then printf 'Error: --profile-name requires a value\n' >&2; exit 1; fi
            PROFILE_NAME="$2"; shift 2 ;;
        --profile-name=*)
            PROFILE_NAME="${1#*=}"; shift ;;
        --plan-dir)
            if [ $# -lt 2 ]; then printf 'Error: --plan-dir requires a value\n' >&2; exit 1; fi
            PLAN_DIR="$2"; shift 2 ;;
        --plan-dir=*)
            PLAN_DIR="${1#*=}"; shift ;;
        --skip-deps)
            SKIP_DEPS=1; shift ;;
        --force)
            FORCE=1; shift ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            printf 'Usage: bash setup-workspace.sh [--project-name <name>] [--layout-name <name>] [--repos <path>]... [--profile-name <name>] [--plan-dir <dir>] [--skip-deps] [--force]\n' >&2
            exit 1 ;;
    esac
done

ok()      { printf '\033[32m%s\033[0m\n' "$*"; }
info()    { printf '\033[36m%s\033[0m\n' "$*"; }
warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
note()    { printf '\033[90m%s\033[0m\n' "$*"; }
section() { printf '\033[97m%s\033[0m\n' "$*"; }
err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

convert_to_slug() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# === Resolve script directory ===

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
INSTALL_DEPS_SCRIPT="$SCRIPT_DIR/install-deps.sh"
SETUP_REPO_SCRIPT="$SCRIPT_DIR/setup-repo.sh"
GENERATE_LAYOUT_SCRIPT="$SCRIPT_DIR/generate-layout.sh"

for s in "$INSTALL_DEPS_SCRIPT" "$SETUP_REPO_SCRIPT" "$GENERATE_LAYOUT_SCRIPT"; do
    if [ ! -f "$s" ]; then
        err "Missing script: $s"
        err "All 4 scripts must be in the same directory."
        exit 1
    fi
done

# === Gather parameters (interactive) ===

clear 2>/dev/null || true
printf '\n'
info "  ============================================"
info "    Multi-Agent OpenCode Workspace - Full Setup"
info "  ============================================"
printf '\n'

if [ -z "$PROJECT_NAME" ]; then
    while :; do
        section "    Project name (e.g., 'My App', 'PMDG Tablet'):"
        printf '\033[36m    > \033[0m'
        PROJECT_NAME=""
        read -r PROJECT_NAME || PROJECT_NAME=""
        if [ -n "$PROJECT_NAME" ]; then break; fi
        err "      [X] Project name is required."
    done
fi

if [ -z "$LAYOUT_NAME" ]; then
    LAYOUT_NAME="$(convert_to_slug "$PROJECT_NAME")-dev"
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
    printf '\n'
    section "    Enter repo paths (one per line, empty line to finish):"
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
        REPOS+=("$repo_path")
    done
    if [ "${#REPOS[@]}" -eq 0 ]; then
        err "At least one repo path is required."
        exit 1
    fi
fi

# === Resolve Plan dir (only prompted when multiple repos) ===

if [ "${#REPOS[@]}" -eq 1 ]; then
    PLAN_DIR="${REPOS[0]}"
elif [ -z "$PLAN_DIR" ]; then
    printf '\n'
    section "    Which folder should Plan-WS run in? (Shell tab follows it)"
    note "    This can be a repo below or any other existing folder."
    n=1
    for repo in "${REPOS[@]}"; do
        note "      $n. $repo"
        n=$((n + 1))
    done
    while :; do
        printf '\033[36m    Enter a number 1-%s, or a folder path [default 1]: \033[0m' "${#REPOS[@]}"
        choice=""
        read -r choice || choice=""
        if [ -z "$choice" ]; then choice="1"; fi
        if printf '%s' "$choice" | grep -qE '^[0-9]+$'; then
            chosen=$choice
            if [ "$chosen" -ge 1 ] && [ "$chosen" -le "${#REPOS[@]}" ]; then
                idx=$((chosen - 1))
                PLAN_DIR="${REPOS[$idx]}"
                break
            fi
            err "      [X] Number out of range (valid 1-${#REPOS[@]})."
            continue
        fi
        candidate="$choice"
        case "$candidate" in
            "~") candidate="$HOME" ;;
            "~/"*) candidate="$HOME${candidate:1}" ;;
        esac
        if [ -d "$candidate" ]; then
            PLAN_DIR="$candidate"
            break
        fi
        err "      [X] Path does not exist: $candidate"
    done
else
    # Explicitly passed via param - validate it exists (with ~ expansion)
    candidate="$PLAN_DIR"
    case "$candidate" in
        "~") candidate="$HOME" ;;
        "~/"*) candidate="$HOME${candidate:1}" ;;
    esac
    if [ ! -d "$candidate" ]; then
        err "PlanDir does not exist: $candidate"
        exit 1
    fi
    PLAN_DIR="$candidate"
fi

# === Summary ===

printf '\n'
section "    Setup plan:"
note "      Project:  $PROJECT_NAME"
note "      Profile:  $PROFILE_NAME"
note "      Layout:   $LAYOUT_NAME"
note "      Repos:    ${#REPOS[@]}"
for repo in "${REPOS[@]}"; do
    note "        $repo"
done
note "      Plan dir:  $PLAN_DIR"
if [ "$SKIP_DEPS" = "1" ]; then
    note "      Deps:     SKIPPED"
else
    note "      Deps:     Will check/install"
fi
printf '\n'

if [ "$FORCE" != "1" ]; then
    printf '\033[36m    > Proceed? (Y/n) \033[0m'
    proceed=""
    read -r proceed || proceed=""
    if [ "$proceed" = "n" ] || [ "$proceed" = "N" ]; then
        warn "    Cancelled."
        exit 0
    fi
fi

# === Step 1: Install Dependencies ===

if [ "$SKIP_DEPS" = "1" ]; then
    printf '\n'
    note "  -- Step 1: Dependencies (skipped) ---------------"
else
    printf '\n'
    warn "  -- Step 1: Install Dependencies -----------------"
    if bash "$INSTALL_DEPS_SCRIPT"; then
        :
    else
        warn "Dependency install had issues. Continuing anyway..."
    fi
fi

# === Step 2: Set Up Repos ===

printf '\n'
warn "  -- Step 2: Set Up Repos -------------------------"

for repo in "${REPOS[@]}"; do
    if [ "$FORCE" = "1" ]; then
        bash "$SETUP_REPO_SCRIPT" "$repo" --force || true
    else
        bash "$SETUP_REPO_SCRIPT" "$repo" || true
    fi
done

# === Step 3: Generate Zellij Layout ===

printf '\n'
warn "  -- Step 3: Generate Zellij Layout ---------------"

if [ "$FORCE" = "1" ]; then
    bash "$GENERATE_LAYOUT_SCRIPT" "$LAYOUT_NAME" "${REPOS[@]}" --profile-name "$PROFILE_NAME" --plan-dir "$PLAN_DIR" --force || true
else
    bash "$GENERATE_LAYOUT_SCRIPT" "$LAYOUT_NAME" "${REPOS[@]}" --profile-name "$PROFILE_NAME" --plan-dir "$PLAN_DIR" || true
fi

# === Done ===

printf '\n'
info "  ============================================"
ok "  Setup complete!"
info "  ============================================"
printf '\n'
warn "  Next steps:"
printf '\n'
section "  1. Edit AGENTS.md in each repo:"
for repo in "${REPOS[@]}"; do
    note "     $repo/AGENTS.md"
done
printf '\n'
base="${XDG_CONFIG_HOME:-}"
if [ -z "$base" ]; then base="$HOME/.config"; fi
config_path="$base/zellij/config-$LAYOUT_NAME.kdl"
section "  2. Launch:"
info "     zellij --config \"$config_path\" --layout $LAYOUT_NAME"
printf '\n'
section "  3. Agents available (oc -p $PROFILE_NAME):"
note "     /agent Plan-WS    -> creates tasks"
note "     /agent Build-WS   -> orchestrates builds"
note "     /agent Merger-WS  -> merges tasks"
printf '\n'

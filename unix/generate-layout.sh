#!/usr/bin/env bash
# generate-layout.sh - Generates a Zellij layout and ws config for any set of repos
# using the "ws" OpenCode profile.
#
# Creates two files:
# 1. <layout-name>.kdl - Zellij layout with:
#    - Plan tab (Plan-WS agent, in the chosen Plan dir)
#    - One Build tab + one Board tab + one Merge tab per repo (indexed: Build 1, Board 1, Merge 1, ...)
#    - Shell tab (plain shell, in the chosen Plan dir)
#    - new_tab_template
# 2. config-<layout-name>.kdl - Zellij config with a "duplicate tab" keybind
#    (a = duplicate focused tab). Generated from config-ws.kdl template by
#    replacing {{WS_KEYBINDS}} with the keybind.
#
# The keybind uses the Run action (floating pane, close-on-exit) to call
# new-build-agent.sh (no params) in the source tab. The script reads the
# source tab's cwd + name, creates a new tab via "zellij action new-tab"
# with the same cwd, name "SourceName.N", and the same agent command,
# then moves it next to the source via "move-tab -t".
#
# Usage:
#   bash generate-layout.sh <layout-name> <repo-path> [repo-path...] [--profile-name <name>] [--plan-dir <dir>] [--force]

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

LAYOUT_NAME=""
REPOS=()
PROFILE_NAME="ws"
PLAN_DIR=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
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
        --force)
            FORCE=1; shift ;;
        --)
            shift
            while [ $# -gt 0 ]; do REPOS+=("$1"); shift; done ;;
        -*)
            printf 'Unknown argument: %s\n' "$1" >&2
            printf 'Usage: bash generate-layout.sh <layout-name> <repo-path> [repo-path...] [--profile-name <name>] [--plan-dir <dir>] [--force]\n' >&2
            exit 1 ;;
        *)
            if [ -z "$LAYOUT_NAME" ]; then
                LAYOUT_NAME="$1"
            else
                REPOS+=("$1")
            fi
            shift ;;
    esac
done

if [ -z "$LAYOUT_NAME" ] || [ "${#REPOS[@]}" -eq 0 ]; then
    printf 'Usage: bash generate-layout.sh <layout-name> <repo-path> [repo-path...] [--profile-name <name>] [--plan-dir <dir>] [--force]\n' >&2
    exit 1
fi

ok()      { printf '\033[32m%s\033[0m\n' "$*"; }
info()    { printf '\033[36m%s\033[0m\n' "$*"; }
warn()    { printf '\033[33m%s\033[0m\n' "$*"; }
note()    { printf '\033[90m%s\033[0m\n' "$*"; }
section() { printf '\033[97m%s\033[0m\n' "$*"; }
err()     { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# === Helpers ===

zellij_config_dir() {
    base="${XDG_CONFIG_HOME:-}"
    if [ -z "$base" ]; then base="$HOME/.config"; fi
    printf '%s' "$base/zellij"
}

normalize_path_for_kdl() {
    # Strip trailing slashes (Zellij cwd resolution can be inconsistent
    # with a trailing separator)
    printf '%s' "$1" | sed -E 's|[/]+$||'
}

LINES=()

# Emits a pane block that runs the given command list. Invokes the command
# directly (no cmd /c wrapper on unix). Zellij's KDL parser requires all args
# values on a single line after `args`.
emit_pane() {
    cwd_attr=""
    if [ -n "$1" ]; then cwd_attr=" cwd=\"$1\""; fi
    exe="$2"
    shift 2
    args_line=""
    for a in "$@"; do
        args_line="$args_line \"$a\""
    done
    LINES+=("        pane command=\"$exe\"$cwd_attr {")
    LINES+=("            args$args_line")
    LINES+=("        }")
}

emit_tab_bar() {
    LINES+=("        pane size=1 borderless=true {")
    LINES+=("            plugin location=\"zellij:tab-bar\"")
    LINES+=("        }")
}

emit_status_bar() {
    LINES+=("        pane size=1 borderless=true {")
    LINES+=("            plugin location=\"zellij:status-bar\"")
    LINES+=("        }")
}

# === Resolve paths ===

ZCFG=$(zellij_config_dir)

# === Validate repo paths ===

for repo in "${REPOS[@]}"; do
    if [ ! -d "$repo" ]; then
        err "Repo path does not exist: $repo"
        exit 1
    fi
done

if [ -z "$PLAN_DIR" ]; then PLAN_DIR="${REPOS[0]}"; fi
if [ ! -d "$PLAN_DIR" ]; then
    err "Plan dir path does not exist: $PLAN_DIR"
    exit 1
fi

LAYOUT_DIR="$ZCFG/layouts"
DEST_LAYOUT="$LAYOUT_DIR/$LAYOUT_NAME.kdl"

# === Check existing ===

if [ -e "$DEST_LAYOUT" ]; then
    if [ "$FORCE" = "1" ]; then
        printf 'WARNING: Layout %s already exists. Overwriting (--force).\n' "'$LAYOUT_NAME'" >&2
    else
        printf 'WARNING: Layout %s already exists at: %s\n' "'$LAYOUT_NAME'" "$DEST_LAYOUT" >&2
        printf 'Overwrite? (y/N) '
        overwrite=""
        read -r overwrite || overwrite=""
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            warn "Cancelled."
            exit 0
        fi
    fi
fi

# === Build layout ===

plan_dir_path=$(normalize_path_for_kdl "$PLAN_DIR")

LINES=()
LINES+=("layout {")
LINES+=("    cwd \"$plan_dir_path\"")

# Tab: Plan (focus on open) - runs in the chosen Plan dir (where Plan-WS lives)
LINES+=("    tab name=\"Plan\" focus=true hide_floating_panes=true {")
emit_tab_bar
emit_pane "$plan_dir_path" "ocx" "oc" "-p" "$PROFILE_NAME" "--agent" "Plan-WS"
emit_status_bar
LINES+=("    }")

# Tabs: one Build + one Board + one Merge per repo (indexed, grouped by repo)
idx=0
for repo in "${REPOS[@]}"; do
    idx=$((idx + 1))
    repo_path=$(normalize_path_for_kdl "$repo")

    # Build tab
    LINES+=("    tab name=\"Build $idx\" hide_floating_panes=true {")
    emit_tab_bar
    emit_pane "$repo_path" "ocx" "oc" "-p" "$PROFILE_NAME" "--agent" "Build-WS"
    emit_status_bar
    LINES+=("    }")

    # Board tab
    LINES+=("    tab name=\"Board $idx\" hide_floating_panes=true {")
    emit_tab_bar
    emit_pane "$repo_path" "backlog" "board"
    emit_status_bar
    LINES+=("    }")

    # Merge tab - one Merger-WS per repo (Merger-WS operates on the repo it's launched in)
    LINES+=("    tab name=\"Merge $idx\" hide_floating_panes=true {")
    emit_tab_bar
    emit_pane "$repo_path" "ocx" "oc" "-p" "$PROFILE_NAME" "--agent" "Merger-WS"
    emit_status_bar
    LINES+=("    }")
done

# Tab: Shell (in Plan dir)
LINES+=("    tab name=\"Shell\" hide_floating_panes=true {")
emit_tab_bar
LINES+=("        pane cwd=\"$plan_dir_path\"")
emit_status_bar
LINES+=("    }")

# new_tab_template
LINES+=("    new_tab_template {")
emit_tab_bar
LINES+=("        pane")
emit_status_bar
LINES+=("    }")

# Close the layout block
LINES+=("}")

# === Write layout ===

if [ ! -d "$LAYOUT_DIR" ]; then
    mkdir -p "$LAYOUT_DIR"
fi

line_count=${#LINES[@]}
i=1
for line in "${LINES[@]}"; do
    if [ "$i" -eq "$line_count" ]; then
        printf '%s' "$line"
    else
        printf '%s\n' "$line"
    fi
    i=$((i + 1))
done > "$DEST_LAYOUT"

# === Generate config-<layout>.kdl (from config-ws.kdl template with duplicate-tab keybind) ===

script_path=$(normalize_path_for_kdl "$ZCFG/scripts/new-build-agent.sh")

keybind_file=$(mktemp)
printf '        bind "a" {\n' > "$keybind_file"
printf '            Run "bash" "%s" {\n' "$script_path" >> "$keybind_file"
printf '                floating true\n' >> "$keybind_file"
printf '                close_on_exit true\n' >> "$keybind_file"
printf '            }\n' >> "$keybind_file"
printf '            SwitchToMode "normal"\n' >> "$keybind_file"
printf '        }\n' >> "$keybind_file"

template_path="$SCRIPT_DIR/config-ws.kdl"
if [ ! -f "$template_path" ]; then
    template_path="$ZCFG/config-ws.kdl"
fi
if [ ! -f "$template_path" ]; then
    err "config-ws.kdl template not found. Run bootstrap.sh to install it."
    exit 1
fi
if ! grep -q '{{WS_KEYBINDS}}' "$template_path"; then
    err "config-ws.kdl template does not contain {{WS_KEYBINDS}} placeholder."
    exit 1
fi

DEST_CONFIG="$ZCFG/config-$LAYOUT_NAME.kdl"
awk -v kbfile="$keybind_file" '
    /^[[:space:]]*\/\/[[:space:]]*\{\{WS_KEYBINDS\}\}/ {
        while ((getline kbline < kbfile) > 0) print kbline
        next
    }
    { print }
' "$template_path" > "$DEST_CONFIG.tmp"
sed -E -e 's/\r$//' -e 's|default_shell[[:space:]]+"[^"]*"|default_shell "bash"|' "$DEST_CONFIG.tmp" > "$DEST_CONFIG"
rm -f "$DEST_CONFIG.tmp" "$keybind_file"

# === Report ===

tab_count=$(( 2 + ${#REPOS[@]} * 3 ))
printf '\n'
info "  Layout: $LAYOUT_NAME ($tab_count tabs)  [macOS/Linux]"
note "  File:   $DEST_LAYOUT"
printf '\n'
section "  Tabs:"
note "    Plan              - Task creation (Plan-WS agent)"
idx=0
for repo in "${REPOS[@]}"; do
    idx=$((idx + 1))
    note "    Build $idx            - Build orchestrator (Build-WS)"
    note "    Board $idx            - Backlog.md board view"
    note "    Merge $idx            - Merge orchestrator (Merger-WS)"
done
note "    Shell             - Shell"
printf '\n'
section "  Config: config-$LAYOUT_NAME.kdl"
note "    File:  $DEST_CONFIG"
printf '\n'
section "  Keybinds (Ctrl+t mode):"
note "    a  - Duplicate focused tab (same cwd + agent, name.N)"
note "    n  - New plain tab"
printf '\n'
info "  Launch:  zellij --config \"$DEST_CONFIG\" --layout $LAYOUT_NAME"
printf '\n'

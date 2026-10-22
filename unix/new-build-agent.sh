#!/usr/bin/env bash
# new-build-agent.sh - Duplicates the focused Zellij tab - same cwd, same agent, incremented name.
#
# Launched from a Zellij keybind via the Run action (floating pane, close-on-exit).
# The floating pane runs in the SOURCE tab, so the source tab stays focused.
# This script:
# 1. Reads the source tab's name + position (current-tab-info)
# 2. Reads the source pane's cwd (list-panes, non-plugin non-floating pane)
# 3. Computes "BaseName.N" where N = max existing suffix + 1
# 4. Creates a new tab with --cwd, --name, and the same agent command (new-tab)
# 5. Moves the new tab to be immediately right of the source (move-tab -t)
#
# Agent is derived from the source tab name prefix:
#   Build  -> ocx oc -p ws --agent Build-WS
#   Plan   -> ocx oc -p ws --agent Plan-WS
#   Merge  -> ocx oc -p ws --agent Merger-WS
#   Board  -> backlog board
#   Shell  -> (plain shell, no command)
#
# Requires zellij and node on PATH. JSON parsing is done with node -e.
#
# Usage (from a Zellij keybind):
#   Run "bash" "<zellij-config>/scripts/new-build-agent.sh"

set -eu

have() { command -v "$1" >/dev/null 2>&1; }

for tool in zellij node; do
    if ! have "$tool"; then
        printf 'Error: %s not found on PATH.\n' "$tool" >&2
        exit 1
    fi
done

# Step 1: Get source tab info (Run opened a floating pane in the focused tab)
source_info=$(zellij action current-tab-info -j 2>&1 | node -e '
let d = "";
process.stdin.on("data", (c) => { d += c; });
process.stdin.on("end", () => {
    const j = JSON.parse(d);
    console.log(j.name + " " + j.position);
});
')
source_name=${source_info% *}
source_pos=${source_info##* }

# Step 2: Get all panes - source cwd + tab name list
panes_out=$(zellij action list-panes -j -a -c -t -s 2>&1 | node -e '
let d = "";
process.stdin.on("data", (c) => { d += c; });
process.stdin.on("end", () => {
    const ps = JSON.parse(d);
    const pos = process.argv[1];
    const out = [];
    for (const p of ps) {
        if (!p.is_plugin && !p.is_floating && String(p.tab_position) === pos) {
            out.push("CWD " + (p.pane_cwd || ""));
            break;
        }
    }
    const seen = {};
    const sorted = ps.slice().sort((a, b) => a.tab_position - b.tab_position);
    for (const p of sorted) {
        if (p.is_plugin) { continue; }
        const key = String(p.tab_position);
        if (seen[key]) { continue; }
        seen[key] = true;
        out.push("TAB " + key + " " + (p.tab_name || ""));
    }
    console.log(out.join("\n"));
});
' "$source_pos")

source_cwd=$(printf '%s\n' "$panes_out" | sed -nE 's/^CWD //p' | head -n 1)

tab_names=()
while IFS= read -r t; do
    if [ -n "$t" ]; then
        tab_names+=("$t")
    fi
done < <(printf '%s\n' "$panes_out" | sed -nE 's/^TAB [0-9]+ //p')

# Step 3: Compute BaseName.N
base_name=$(printf '%s' "$source_name" | sed -E 's/^(.+)\.[0-9]+$/\1/')

max_n=0
for t in "${tab_names[@]}"; do
    case "$t" in
        "$base_name".[0-9]*)
            suffix=${t##*.}
            case "$suffix" in
                ''|*[!0-9]*) ;;
                *)
                    if [ "$suffix" -gt "$max_n" ]; then
                        max_n=$suffix
                    fi
                    ;;
            esac
            ;;
    esac
done
new_name="$base_name.$((max_n + 1))"

# Step 4: Derive agent from base name
agent=()
case "$base_name" in
    Build*)  agent=(ocx oc -p ws --agent Build-WS) ;;
    Plan*)   agent=(ocx oc -p ws --agent Plan-WS) ;;
    Merge*)  agent=(ocx oc -p ws --agent Merger-WS) ;;
    Board*)  agent=(backlog board) ;;
    Shell*)  agent=() ;;
    *)       agent=(ocx oc -p ws --agent Build-WS) ;;
esac

# Step 5: Create new tab with cwd, name, and command
if [ "${#agent[@]}" -gt 0 ]; then
    new_tab_raw=$(zellij action new-tab --cwd "$source_cwd" --name "$new_name" -- "${agent[@]}" 2>&1)
else
    new_tab_raw=$(zellij action new-tab --cwd "$source_cwd" --name "$new_name" 2>&1)
fi
new_tab_id=$(printf '%s' "$new_tab_raw" | tr -d '[:space:]')

# Step 6: Move new tab to be right after source tab
new_pos=${#tab_names[@]}
target_pos=$((source_pos + 1))
moves_needed=$((new_pos - target_pos))
i=0
while [ "$i" -lt "$moves_needed" ]; do
    zellij action move-tab left -t "$new_tab_id" >/dev/null 2>&1 || true
    i=$((i + 1))
done

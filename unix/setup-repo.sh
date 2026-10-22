#!/usr/bin/env bash
# setup-repo.sh — install board-driven workflow files into a repo for the "ws" OpenCode profile.
#
# Sets up a single repo with everything it needs to work with the ws profile:
#   - 11 workflow scripts in scripts/ (check-board, start-task, create-worktree, complete-task,
#     approve-task, reject-task, read-verdict, write-verdict, sync-worktree, merge-task, done-task)
#   - SOFTWARE_ENGINEERING_PRINCIPLES.md (SOLID, DRY, KISS, YAGNI, testing, lint rules)
#   - Backlog.md initialization
#   - Task templates in backlog/docs/
#   - backlog/worktrees/ added to .gitignore
#
# Does NOT create or modify AGENTS.md — that file is repo-specific and owned by the project.
#
# Run once per repo. Safe to re-run (skips existing files unless --force).
#
# Usage:
#   bash setup-repo.sh <repo-path> [--project-name <name>] [--force]
#
# Examples:
#   bash setup-repo.sh "$HOME/Projects/my-app"
#   bash setup-repo.sh ~/Projects/kinematics-prototype --force
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

expand_path() {
    local p="$1"
    case "$p" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s%s' "$HOME" "${p:1}" ;;
        *) printf '%s' "$p" ;;
    esac
}

# === Resolve args ===

RepoPath=""
ProjectName=""
Force=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project-name) ProjectName="${2:-}"; shift 2 ;;
        --project-name=*) ProjectName="${1#--project-name=}"; shift ;;
        --force) Force=1; shift ;;
        --*) err "Unknown option: $1"; exit 1 ;;
        *)
            if [ -z "$RepoPath" ]; then RepoPath="$1"; else err "Unexpected argument: $1"; exit 1; fi
            shift
            ;;
    esac
done
if [ -z "$RepoPath" ]; then
    err "RepoPath is required. Usage: bash setup-repo.sh <repo-path> [--project-name <name>] [--force]"
    exit 1
fi

RepoPath=$(expand_path "$RepoPath")

if [ ! -d "$RepoPath" ]; then
    err "Repo path does not exist: $RepoPath"
    exit 1
fi

if [ -z "$ProjectName" ]; then
    ProjectName=$(basename "$RepoPath")
fi

printf '\n'
info "  Setting up repo: $ProjectName"
note "  Path: $RepoPath"
printf '\n'

# === Workflow scripts (self-contained) ===

SCRIPT_NAMES="check-board start-task create-worktree complete-task approve-task reject-task read-verdict write-verdict sync-worktree merge-task done-task"
total=0
for s in $SCRIPT_NAMES; do total=$((total+1)); done

ScriptsDir="$RepoPath/scripts"
mkdir -p "$ScriptsDir"

written=0
write_script() {
    local name="$1"
    local path="$ScriptsDir/$name.sh"
    local body
    body=$(cat)
    if [ "$Force" = "1" ] || [ ! -f "$path" ]; then
        printf '%s' "$body" > "$path"
        written=$((written+1))
    fi
}

write_script check-board <<'EOF_CHECK_BOARD'
#!/usr/bin/env bash
# check-board.sh - list tasks on the board, optionally filtered by status
# Usage: bash ./scripts/check-board.sh ["<status>"]
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

Status="${1:-}"

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

if [ -n "$Status" ]; then
    info "Tasks with status: $Status"
    printf '%s\n' '---'
    backlog task list --status "$Status"
else
    info "Full Board:"
    printf '%s\n' '---'
    for s in "To Do" "In Progress" "To Review" "To Merge" "Done"; do
        printf '\n'
        warn "[$s]"
        backlog task list --status "$s" 2>/dev/null || true
    done
fi
EOF_CHECK_BOARD

write_script start-task <<'EOF_START_TASK'
#!/usr/bin/env bash
# start-task.sh - move a task from "To Do" to "In Progress"
# Usage: bash ./scripts/start-task.sh <task-id>
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: start-task.sh <task-id>"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

info "Starting $TaskId..."
task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

current_status=$(printf '%s\n' "$task_text" | sed -nE 's/^Status:[[:space:]]*[^[:space:]]+[[:space:]]+//p' | head -n 1 | sed -E 's/[[:space:]]+$//')
if [ -n "$current_status" ]; then
    if [ "$current_status" != "To Do" ]; then
        err "Cannot start $TaskId: current status is '$current_status' (expected 'To Do'). Only tasks in 'To Do' can be started."
        exit 1
    fi
else
    err "Cannot determine current status of $TaskId. The backlog output was unexpected."
    exit 1
fi

backlog task edit "$TaskId" -s "In Progress" || { err "Failed to update $TaskId status."; exit 1; }

printf '\n'
printf 'TASK_STARTED: %s\n' "$TaskId"
printf 'STATUS: In Progress\n'
EOF_START_TASK

write_script create-worktree <<'EOF_CREATE_WORKTREE'
#!/usr/bin/env bash
# create-worktree.sh - create (or validate) a git worktree for a task
# Usage: bash ./scripts/create-worktree.sh <task-id> [--background]
#
# First call starts a background checkout and writes a .pending marker.
# Second call waits for completion (or reports errors). Later calls validate
# the existing worktree. Broken worktrees are cleaned up and recreated.
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi
if ! have git; then
    err "Git not found. Install Git first."
    exit 1
fi

TaskId=""
Background=0
while [ $# -gt 0 ]; do
    case "$1" in
        --background) Background=1; shift ;;
        --*) err "Unknown option: $1"; exit 1 ;;
        *)
            if [ -z "$TaskId" ]; then TaskId="$1"; else err "Unexpected argument: $1"; exit 1; fi
            shift
            ;;
    esac
done
if [ -z "$TaskId" ]; then
    err "Usage: create-worktree.sh <task-id> [--background]"
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

RepoRoot=$(git rev-parse --show-toplevel 2>/dev/null) || RepoRoot=""
if [ -z "$RepoRoot" ]; then
    script_dir=$(cd "$(dirname "$0")" && pwd)
    RepoRoot=$(cd "$script_dir/../.." && pwd)
fi
WorktreePath="$RepoRoot/backlog/worktrees/$TaskId"
BranchName="$TaskId"
WorktreesDir="$RepoRoot/backlog/worktrees"
mkdir -p "$WorktreesDir"
GitDirTarget="$RepoRoot/.git/worktrees/$TaskId"
PendingFile="$WorktreesDir/$TaskId.pending"
ErrorFile="$WorktreesDir/$TaskId.error"

# === Background mode: create worktree detached ===
if [ "$Background" = "1" ]; then
    current_branch=$(git branch --show-current 2>/dev/null) || current_branch=""
    if [ -z "$current_branch" ]; then current_branch="main"; fi

    bg_error=""
    rc=0
    git worktree add "$WorktreePath" -b "$BranchName" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        bg_error="git worktree add failed (exit $rc)"
    else
        status=$(git -C "$WorktreePath" status --porcelain 2>/dev/null) || status=""
        if [ -n "$status" ]; then
            missing_count=$(printf '%s\n' "$status" | grep -c . || true)
            bg_error="Checkout incomplete - $missing_count files missing"
        fi
    fi

    if [ -z "$bg_error" ]; then
        wt_block=$(printf '\n\n<!-- WORKTREE_START -->\n## Worktree\n- Path: `%s`\n- Branch: `%s`\n- MergeTarget: `%s`\n<!-- WORKTREE_END -->' "$WorktreePath" "$BranchName" "$current_branch")
        backlog task edit "$TaskId" --comment "$wt_block" --comment-author system >/dev/null 2>&1 || true
        ready_content=$(printf 'WORKTREE_PATH: %s\nBRANCH: %s\nMERGE_TARGET: %s\nCREATED_AT: %s' "$WorktreePath" "$BranchName" "$current_branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
        printf '%s' "$ready_content" > "$WorktreePath/.ready"
        rm -f "$PendingFile"
    else
        printf '%s' "$bg_error" > "$ErrorFile"
        git worktree remove "$WorktreePath" --force >/dev/null 2>&1 || true
        rm -rf "$WorktreePath"
        git branch -D "$BranchName" >/dev/null 2>&1 || true
        rm -f "$PendingFile"
    fi
    exit 0
fi

# === Check background process state ===
if [ -f "$PendingFile" ]; then
    bg_pid=0
    first_line=$(head -n 1 "$PendingFile" 2>/dev/null) || first_line=""
    case "$first_line" in
        '' | *[!0-9]*) ;;
        *) bg_pid=$first_line ;;
    esac

    deadline=$(( $(date +%s) + 100 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ -f "$WorktreePath/.ready" ]; then
            rm -f "$PendingFile"
            ready_content=$(cat "$WorktreePath/.ready" 2>/dev/null) || ready_content=""
            printf 'STATUS: ready\n'
            printf '%s\n' "$ready_content"
            exit 0
        fi
        if [ -f "$ErrorFile" ]; then
            error_msg=$(cat "$ErrorFile" 2>/dev/null) || error_msg=""
            rm -f "$PendingFile" "$ErrorFile"
            printf 'STATUS: error\n'
            printf '%s\n' "$error_msg"
            exit 1
        fi
        if [ "$bg_pid" -gt 0 ]; then
            if ! kill -0 "$bg_pid" 2>/dev/null; then
                rm -f "$PendingFile"
                git worktree remove "$WorktreePath" --force >/dev/null 2>&1 || true
                rm -rf "$WorktreePath"
                git branch -D "$BranchName" >/dev/null 2>&1 || true
                printf 'STATUS: error\n'
                printf 'Background process died unexpectedly.\n'
                exit 1
            fi
        fi
        sleep 5
    done
    printf 'STATUS: still_creating\n'
    printf 'The background checkout is still running. Call this script again to wait for completion.\n'
    exit 0
fi

# === Check for error from previous attempt ===
if [ -f "$ErrorFile" ]; then
    error_msg=$(cat "$ErrorFile" 2>/dev/null) || error_msg=""
    rm -f "$ErrorFile"
    printf 'STATUS: error\n'
    printf '%s\n' "$error_msg"
    exit 1
fi

# === Validate existing worktree (deterministic 4-point check) ===
if [ -d "$WorktreePath" ]; then
    git_file_exists=0
    if [ -e "$WorktreePath/.git" ]; then git_file_exists=1; fi
    git_dir_registered=0
    if [ -e "$GitDirTarget" ]; then git_dir_registered=1; fi
    branch_exists=0
    if git show-ref --verify --quiet "refs/heads/$BranchName" 2>/dev/null; then branch_exists=1; fi
    ready_exists=0
    if [ -f "$WorktreePath/.ready" ]; then ready_exists=1; fi

    # Structurally valid = directory + .git file + gitdir registration + branch all exist
    structurally_valid=0
    if [ "$git_file_exists" = "1" ] && [ "$git_dir_registered" = "1" ] && [ "$branch_exists" = "1" ]; then
        structurally_valid=1
    fi

    if [ "$structurally_valid" = "1" ] && [ "$ready_exists" = "1" ]; then
        # Fully valid worktree (new-style) — skip
        printf 'STATUS: ready\n'
        warn "Worktree already exists and is valid at $WorktreePath"
        printf '\n'
        printf 'WORKTREE_PATH: %s\n' "$WorktreePath"
        printf 'BRANCH: %s\n' "$BranchName"
        exit 0
    fi

    if [ "$structurally_valid" = "1" ]; then
        # Legacy worktree (created by old script) — repair metadata, don't destroy
        warn "Worktree exists but was created by an older script. Repairing metadata..."

        # Determine the merge target (the branch the worktree was created from)
        # Strategy: find which branch contains the parent commit of the worktree HEAD
        parent_commit=$(git -C "$WorktreePath" rev-parse HEAD~1 2>/dev/null) || parent_commit=""
        merge_target_branch=""
        if [ -n "$parent_commit" ]; then
            # Find which branch contains the parent commit
            branches=$(git -C "$RepoRoot" branch --contains "$parent_commit" 2>/dev/null) || branches=""
            if [ -n "$branches" ]; then
                # Parse branch names (strip leading * and whitespace)
                while IFS= read -r b; do
                    b=$(printf '%s' "$b" | sed -E 's/^[[:space:]]+//; s/^[*+][[:space:]]+//')
                    if [ -n "$b" ] && [ "$b" != "$BranchName" ] && [ "$b" != "HEAD" ] && [ -z "$merge_target_branch" ]; then
                        merge_target_branch="$b"
                    fi
                done < <(printf '%s\n' "$branches")
            fi
        fi

        if [ -z "$merge_target_branch" ]; then
            # Fallback: use current branch if not the task branch
            current_branch=$(git -C "$RepoRoot" branch --show-current 2>/dev/null) || current_branch=""
            if [ -n "$current_branch" ] && [ "$current_branch" != "$BranchName" ]; then
                merge_target_branch="$current_branch"
            fi
        fi

        if [ -z "$merge_target_branch" ]; then
            err "Cannot determine merge target for legacy worktree. Please specify it manually by editing the ticket and adding:
<!-- WORKTREE_START -->
## Worktree
- Path: \`$WorktreePath\`
- Branch: \`$BranchName\`
- MergeTarget: \`<branch-name>\`
<!-- WORKTREE_END -->"
            exit 1
        fi

        ok "  Detected merge target: $merge_target_branch"

        # Write worktree ref to ticket
        worktree_block=$(printf '\n\n<!-- WORKTREE_START -->\n## Worktree\n- Path: `%s`\n- Branch: `%s`\n- MergeTarget: `%s`\n<!-- WORKTREE_END -->' "$WorktreePath" "$BranchName" "$merge_target_branch")
        rc=0
        backlog task edit "$TaskId" --comment "$worktree_block" --comment-author system >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "  Worktree reference written to ticket $TaskId"
        else
            warn "  Failed to write worktree reference to ticket (non-fatal)."
        fi

        # Write .ready file
        ready_content=$(printf 'WORKTREE_PATH: %s\nBRANCH: %s\nMERGE_TARGET: %s\nCREATED_AT: %s\nREPAIRED: true' "$WorktreePath" "$BranchName" "$merge_target_branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
        printf '%s' "$ready_content" > "$WorktreePath/.ready"
        ok "  Ready signal written (legacy repair)."

        printf 'STATUS: ready\n'
        printf '\n'
        printf 'WORKTREE_PATH: %s\n' "$WorktreePath"
        printf 'BRANCH: %s\n' "$BranchName"
        printf 'MERGE_TARGET: %s\n' "$merge_target_branch"
        printf 'READY: true (repaired)\n'
        exit 0
    fi

    # === Genuinely broken worktree — clean up ===
    warn "Existing worktree is broken or incomplete. Cleaning up..."

    # 1. Remove stale lock files
    for lf in "$GitDirTarget/lock" "$RepoRoot/.git/refs/heads/$BranchName.lock"; do
        if [ -e "$lf" ]; then
            rm -f "$lf"
            note "  Removed stale lock: $lf"
        fi
    done

    # 2. Let git clean up
    git worktree remove "$WorktreePath" --force >/dev/null 2>&1 || true

    # 3. Fallback: manual removal
    rm -rf "$WorktreePath"

    # 4. Remove orphaned branch
    if [ "$branch_exists" = "1" ]; then
        git branch -D "$BranchName" >/dev/null 2>&1 || true
        note "  Removed orphaned branch: $BranchName"
    fi

    note "  Cleanup complete. Creating fresh worktree..."
fi

# === Launch background worktree creation ===
dirty=$(git status --porcelain 2>/dev/null) || dirty=""
if [ -n "$dirty" ]; then
    warn "Current branch has uncommitted changes. Worktree will be created from the last commit."
fi

printf 'pending\n%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PendingFile"

script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$RepoRoot"
nohup bash "$script_path" "$TaskId" --background >/dev/null 2>&1 &
bg_pid=$!
printf '%s\n%s' "$bg_pid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PendingFile"

printf 'STATUS: creating\n'
printf 'Background checkout started (PID %s). Call this script again to wait for completion.\n' "$bg_pid"
exit 0
EOF_CREATE_WORKTREE

write_script complete-task <<'EOF_COMPLETE_TASK'
#!/usr/bin/env bash
# complete-task.sh - move a task from "In Progress" to "To Review"
# Usage: bash ./scripts/complete-task.sh <task-id>
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: complete-task.sh <task-id>"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

current_status=$(printf '%s\n' "$task_text" | sed -nE 's/^Status:[[:space:]]*[^[:space:]]+[[:space:]]+//p' | head -n 1 | sed -E 's/[[:space:]]+$//')
if [ -n "$current_status" ]; then
    if [ "$current_status" != "In Progress" ]; then
        err "Cannot complete $TaskId: current status is '$current_status' (expected 'In Progress')."
        exit 1
    fi
else
    err "Cannot determine current status of $TaskId. The backlog output was unexpected."
    exit 1
fi

info "Moving $TaskId to To Review..."
backlog task edit "$TaskId" -s "To Review" || { err "Failed to update $TaskId status."; exit 1; }

printf '\n'
printf 'TASK_COMPLETED: %s\n' "$TaskId"
printf 'STATUS: To Review\n'
EOF_COMPLETE_TASK

write_script approve-task <<'EOF_APPROVE_TASK'
#!/usr/bin/env bash
# approve-task.sh - move a reviewed task from "To Review" to "To Merge"
# Usage: bash ./scripts/approve-task.sh <task-id>
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: approve-task.sh <task-id>"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

current_status=$(printf '%s\n' "$task_text" | sed -nE 's/^Status:[[:space:]]*[^[:space:]]+[[:space:]]+//p' | head -n 1 | sed -E 's/[[:space:]]+$//')
if [ -n "$current_status" ]; then
    if [ "$current_status" != "To Review" ]; then
        err "Cannot approve $TaskId: current status is '$current_status' (expected 'To Review')."
        exit 1
    fi
else
    err "Cannot determine current status of $TaskId. The backlog output was unexpected."
    exit 1
fi

info "Approving $TaskId (moving to To Merge)..."
backlog task edit "$TaskId" -s "To Merge" || { err "Failed to update $TaskId status."; exit 1; }

printf '\n'
printf 'TASK_APPROVED: %s\n' "$TaskId"
printf 'STATUS: To Merge\n'
EOF_APPROVE_TASK

write_script reject-task <<'EOF_REJECT_TASK'
#!/usr/bin/env bash
# reject-task.sh - move a reviewed task from "To Review" back to "In Progress"
# Usage: bash ./scripts/reject-task.sh <task-id>
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: reject-task.sh <task-id>"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

current_status=$(printf '%s\n' "$task_text" | sed -nE 's/^Status:[[:space:]]*[^[:space:]]+[[:space:]]+//p' | head -n 1 | sed -E 's/[[:space:]]+$//')
if [ -n "$current_status" ]; then
    if [ "$current_status" != "To Review" ]; then
        err "Cannot reject $TaskId: current status is '$current_status' (expected 'To Review')."
        exit 1
    fi
else
    err "Cannot determine current status of $TaskId. The backlog output was unexpected."
    exit 1
fi

info "Rejecting $TaskId (moving back to In Progress)..."
backlog task edit "$TaskId" -s "In Progress" || { err "Failed to update $TaskId status."; exit 1; }

printf '\n'
printf 'TASK_REJECTED: %s\n' "$TaskId"
printf 'STATUS: In Progress\n'
EOF_REJECT_TASK

write_script merge-task <<'EOF_MERGE_TASK'
#!/usr/bin/env bash
# merge-task.sh - merge a task branch into its merge target branch
# Usage: bash ./scripts/merge-task.sh <task-id> [--strategy no-ff|squash] [--message "..."]
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

if ! have git; then
    err "Git not found."
    exit 2
fi
if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 2
fi

TaskId=""
Strategy="no-ff"
Message=""
while [ $# -gt 0 ]; do
    case "$1" in
        --strategy) Strategy="${2:-}"; shift 2 ;;
        --strategy=*) Strategy="${1#--strategy=}"; shift ;;
        --message) Message="${2:-}"; shift 2 ;;
        --message=*) Message="${1#--message=}"; shift ;;
        --*) err "Unknown option: $1"; exit 2 ;;
        *)
            if [ -z "$TaskId" ]; then TaskId="$1"; else err "Unexpected argument: $1"; exit 2; fi
            shift
            ;;
    esac
done
if [ -z "$TaskId" ]; then
    err "Usage: merge-task.sh <task-id> [--strategy no-ff|squash] [--message \"...\"]"
    exit 2
fi
if [ "$Strategy" != "no-ff" ] && [ "$Strategy" != "squash" ]; then
    err "Strategy must be 'no-ff' or 'squash'. Got: $Strategy"
    exit 2
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac
BranchName="$TaskId"

RepoRoot=$(git rev-parse --show-toplevel 2>/dev/null) || RepoRoot=""
if [ -z "$RepoRoot" ]; then
    err "Not in a git repo."
    exit 2
fi

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 2; }

merge_target=$(printf '%s\n' "$task_text" | sed -nE 's/^.*MergeTarget:[[:space:]]*`([^`]+)`.*/\1/p' | head -n 1 | sed -E 's/[[:space:]]+$//') || true
if [ -z "$merge_target" ]; then
    err "Cannot determine merge target from ticket. The WORKTREE block is missing or malformed. Run create-worktree.sh to repair the ticket metadata."
    exit 2
fi

if ! git show-ref --verify --quiet "refs/heads/$BranchName" 2>/dev/null; then
    err "Branch $BranchName does not exist."
    exit 2
fi

current_branch=$(git branch --show-current 2>/dev/null) || current_branch=""
if [ -z "$current_branch" ]; then
    err "Cannot determine current branch."
    exit 2
fi
if [ "$current_branch" = "$BranchName" ]; then
    err "Cannot merge $BranchName into itself. Switch to the target branch first."
    exit 2
fi

dirty=$(git status --porcelain 2>/dev/null) || dirty=""
if [ -n "$dirty" ]; then
    warn "Target branch has uncommitted changes. Merge may fail."
fi

if [ "$current_branch" != "$merge_target" ]; then
    err "Cannot merge: current branch is '$current_branch' but the worktree was created from '$merge_target'. Switch to '$merge_target' first: git checkout $merge_target"
    exit 2
fi

# === Sanity check: refuse if too many files would be deleted ===
deleted_files=$(git diff --name-only --diff-filter=D "$merge_target...$BranchName" 2>/dev/null) || deleted_files=""
deleted_count=0
if [ -n "$deleted_files" ]; then
    deleted_count=$(printf '%s\n' "$deleted_files" | grep -c . || true)
fi
if [ "$deleted_count" -gt 50 ]; then
    err "Refusing to merge: $deleted_count files would be deleted. This looks like a worktree checkout issue, not a real change. Aborting. If this is intentional, run the merge manually: git merge --no-ff $BranchName"
    exit 2
fi
ok "Diff sanity check passed ($deleted_count files would be deleted, threshold: 50)."

# === Resolve commit message ===
if [ -z "$Message" ]; then
    task_title=""
    task_title=$(printf '%s\n' "$task_text" | sed -nE 's/^Title:[[:space:]]*//p' | head -n 1 | sed -E 's/[[:space:]]+$//') || true
    if [ -n "$task_title" ]; then
        Message="$task_title

Merge $TaskId into $merge_target"
    else
        Message="Merge $TaskId into $merge_target"
    fi
fi

info "Merging $BranchName into $merge_target ($Strategy)..."

merge_failed() {
    conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null) || conflicts=""
    if [ -n "$conflicts" ]; then
        conflicts_line=$(printf '%s\n' "$conflicts" | awk 'NR==1{out=$0; next} {out = out " " $0} END{printf "%s", out}')
        printf '\033[31mCONFLICTS: %s\033[0m\n' "$conflicts_line"
        exit 1
    fi
    err "Merge failed."
    exit 2
}

if [ "$Strategy" = "squash" ]; then
    git merge --squash "$BranchName" 2>&1 || merge_failed
    git commit -m "$Message" 2>&1 || { err "Squash commit failed."; exit 2; }
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null) || commit_hash=""
    ok "Squash committed: $commit_hash"
    printf 'MERGE_RESULT: success\n'
    printf 'COMMIT: %s\n' "$commit_hash"
    exit 0
else
    git merge --no-ff "$BranchName" -m "$Message" 2>&1 || merge_failed
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null) || commit_hash=""
    ok "Merge successful: $commit_hash"
    printf 'MERGE_RESULT: success\n'
    printf 'COMMIT: %s\n' "$commit_hash"
    exit 0
fi
EOF_MERGE_TASK

write_script done-task <<'EOF_DONE_TASK'
#!/usr/bin/env bash
# done-task.sh - finalize a merged task: mark Done, remove worktree + branch
# Usage: bash ./scripts/done-task.sh <task-id>
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: done-task.sh <task-id>"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi
if ! have git; then
    err "Git not found."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

current_status=$(printf '%s\n' "$task_text" | sed -nE 's/^Status:[[:space:]]*[^[:space:]]+[[:space:]]+//p' | head -n 1 | sed -E 's/[[:space:]]+$//')
if [ -n "$current_status" ]; then
    if [ "$current_status" != "To Merge" ]; then
        err "Cannot finalize $TaskId: current status is '$current_status' (expected 'To Merge')."
        exit 1
    fi
else
    err "Cannot determine current status of $TaskId. The backlog output was unexpected."
    exit 1
fi

RepoRoot=$(git rev-parse --show-toplevel 2>/dev/null) || RepoRoot=""
if [ -z "$RepoRoot" ]; then
    script_dir=$(cd "$(dirname "$0")" && pwd)
    RepoRoot=$(cd "$script_dir/../.." && pwd)
fi
WorktreePath="$RepoRoot/backlog/worktrees/$TaskId"
BranchName="$TaskId"

info "Finalizing $TaskId..."
backlog task edit "$TaskId" -s "Done" || { err "Failed to update $TaskId status."; exit 1; }

if [ -d "$WorktreePath" ]; then
    rc=0
    git worktree remove "$WorktreePath" --force >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ] || [ -d "$WorktreePath" ]; then
        warn "Failed to remove worktree at $WorktreePath. Remove manually: git worktree remove $WorktreePath --force"
        warn "Skipping branch deletion — branch cannot be deleted while worktree is checked out."
        printf '\n'
        printf 'TASK_DONE: %s\n' "$TaskId"
        printf 'STATUS: Done (worktree retained — remove manually before branch deletion)\n'
        exit 0
    fi
    ok "Removed worktree: $WorktreePath"
else
    note "Worktree not found (already removed?): $WorktreePath"
fi

if git show-ref --verify --quiet "refs/heads/$BranchName" 2>/dev/null; then
    rc=0
    git branch -d "$BranchName" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        rc=0
        git branch -D "$BranchName" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "Force-deleted branch: $BranchName"
        else
            warn "Failed to delete branch $BranchName. Remove manually: git branch -D $BranchName"
        fi
    else
        ok "Deleted branch: $BranchName"
    fi
fi

printf '\n'
printf 'TASK_DONE: %s\n' "$TaskId"
printf 'STATUS: Done\n'
EOF_DONE_TASK

write_script read-verdict <<'EOF_READ_VERDICT'
#!/usr/bin/env bash
# read-verdict.sh - read the review verdict tag from a task ticket
# Usage: bash ./scripts/read-verdict.sh <task-id>
# Exit codes: 0 = APPROVED, 1 = REJECTED, 2 = no verdict tag found
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
if [ -z "$TaskId" ]; then
    err "Usage: read-verdict.sh <task-id>"
    exit 2
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 2
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 2; }

if printf '%s\n' "$task_text" | grep -qE '<!--[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*-->'; then
    printf 'VERDICT: APPROVED\n'
    printf 'TASK_ID: %s\n' "$TaskId"
    exit 0
elif printf '%s\n' "$task_text" | grep -qE '<!--[[:space:]]*VERDICT:[[:space:]]*REJECTED[[:space:]]*-->'; then
    printf 'VERDICT: REJECTED\n'
    printf 'TASK_ID: %s\n' "$TaskId"
    exit 1
else
    printf 'VERDICT: NOT_FOUND\n'
    printf 'TASK_ID: %s\n' "$TaskId"
    err "No VERDICT tag found in task $TaskId. The reviewer may not have completed the review."
    exit 2
fi
EOF_READ_VERDICT

write_script write-verdict <<'EOF_WRITE_VERDICT'
#!/usr/bin/env bash
# write-verdict.sh - write a review verdict comment onto a task ticket
# Usage: bash ./scripts/write-verdict.sh <task-id> <approved|rejected> [summary] [issues] [notes]
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

TaskId="${1:-}"
Verdict="${2:-}"
Summary="${3:-}"
Issues="${4:-}"
Notes="${5:-}"

if [ -z "$TaskId" ] || [ -z "$Verdict" ]; then
    err "Usage: write-verdict.sh <task-id> <approved|rejected> [summary] [issues] [notes]"
    exit 1
fi

if ! have backlog; then
    err "Backlog.md CLI not found. Run install-deps.sh first."
    exit 1
fi

case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac

Verdict=$(printf '%s' "$Verdict" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:lower:]' '[:upper:]')
case "$Verdict" in
    APPROVE) Verdict="APPROVED" ;;
    REJECT) Verdict="REJECTED" ;;
esac
if [ "$Verdict" != "APPROVED" ] && [ "$Verdict" != "REJECTED" ]; then
    err "Verdict must be 'approved' or 'rejected'. Got: $Verdict"
    exit 1
fi

task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 1; }

if [ -z "$Summary" ]; then Summary="Review completed."; fi
if [ -z "$Issues" ]; then Issues="None"; fi
if [ -z "$Notes" ]; then Notes="None"; fi

comment=$(printf '<!-- VERDICT: %s -->\n\n## Review\n- **Verdict**: %s\n- **Summary**: %s\n- **Issues**: %s\n- **Notes**: %s' "$Verdict" "$Verdict" "$Summary" "$Issues" "$Notes")
backlog task edit "$TaskId" --comment "$comment" --comment-author "reviewer" 2>&1 || { err "Failed to write verdict to task $TaskId."; exit 1; }

sleep 1

verify_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Failed to read task $TaskId back for verification."; exit 1; }
if printf '%s\n' "$verify_text" | grep -qE "<!--[[:space:]]*VERDICT:[[:space:]]*$Verdict[[:space:]]*-->"; then
    printf 'VERDICT_WRITTEN: %s\n' "$TaskId"
    printf 'VERDICT: %s\n' "$Verdict"
    printf 'STATUS: confirmed\n'
    exit 0
else
    err "Verdict tag not found in task after writing. The comment may have failed silently."
    exit 1
fi
EOF_WRITE_VERDICT

write_script sync-worktree <<'EOF_SYNC_WORKTREE'
#!/usr/bin/env bash
# sync-worktree.sh - sync a task worktree branch with its merge target
# Usage: bash ./scripts/sync-worktree.sh <task-id> [--merge-target <branch>] [--dry-run]
set -eu

have() { command -v "$1" >/dev/null 2>&1; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
note() { printf '\033[90m%s\033[0m\n' "$*"; }

# === Pre-flight Check 1: Tool availability ===
if ! have git; then
    err "Git not found."
    exit 2
fi

# === Parse args ===
TaskId=""
MergeTargetArg=""
DryRun=0
while [ $# -gt 0 ]; do
    case "$1" in
        --merge-target) MergeTargetArg="${2:-}"; shift 2 ;;
        --merge-target=*) MergeTargetArg="${1#--merge-target=}"; shift ;;
        --dry-run) DryRun=1; shift ;;
        --*) err "Unknown option: $1"; exit 2 ;;
        *)
            if [ -z "$TaskId" ]; then TaskId="$1"; else err "Unexpected argument: $1"; exit 2; fi
            shift
            ;;
    esac
done
if [ -z "$TaskId" ]; then
    err "Usage: sync-worktree.sh <task-id> [--merge-target <branch>] [--dry-run]"
    exit 2
fi

# === Pre-flight Check 2: Task ID normalization ===
case "$TaskId" in task-*) ;; *) TaskId="task-$TaskId" ;; esac
BranchName="$TaskId"

# === Pre-flight Check 3: Repo root ===
RepoRoot=$(git rev-parse --show-toplevel 2>/dev/null) || RepoRoot=""
if [ -z "$RepoRoot" ]; then
    err "Not in a git repo."
    exit 2
fi

# === Pre-flight Check 4: Task exists ===
task_text=""
if ! have backlog; then
    if [ -z "$MergeTargetArg" ]; then
        err "Backlog.md CLI not found. Run install-deps.sh first, or pass --merge-target explicitly."
        exit 2
    fi
else
    task_text=$(backlog task view "$TaskId" --plain 2>&1) || { err "Task $TaskId not found."; exit 2; }
fi

# === Pre-flight Check 5: MergeTarget extraction ===
mergeTarget=""
if [ -n "$MergeTargetArg" ]; then
    mergeTarget=$(printf '%s' "$MergeTargetArg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
else
    mergeTarget=$(printf '%s\n' "$task_text" | sed -nE 's/^.*MergeTarget:[[:space:]]*`([^`]+)`.*/\1/p' | head -n 1 | sed -E 's/[[:space:]]+$//') || true
    if [ -z "$mergeTarget" ]; then
        err "Cannot determine merge target from ticket. The WORKTREE block is missing or malformed. Run create-worktree.sh to repair the ticket metadata, or pass --merge-target explicitly."
        exit 2
    fi
fi

# === Pre-flight Check 6: Worktree path ===
WorktreePath="$RepoRoot/backlog/worktrees/$TaskId"
if [ ! -d "$WorktreePath" ]; then
    err "Worktree not found at $WorktreePath. Run create-worktree.sh first."
    exit 2
fi
if [ ! -e "$WorktreePath/.git" ]; then
    err "Worktree is broken (.git file missing). Run create-worktree.sh to repair, or remove it and recreate."
    exit 2
fi

# === Pre-flight Check 7: Task branch exists ===
if ! git show-ref --verify --quiet "refs/heads/$BranchName" 2>/dev/null; then
    err "Branch $BranchName does not exist."
    exit 2
fi

# === Pre-flight Check 8: MergeTarget branch exists ===
if ! git show-ref --verify --quiet "refs/heads/$mergeTarget" 2>/dev/null; then
    err "Merge target branch '$mergeTarget' does not exist locally. Run: git fetch origin && git branch $mergeTarget origin/$mergeTarget"
    exit 2
fi

# === Pre-flight Check 9: Not the same branch ===
if [ "$BranchName" = "$mergeTarget" ]; then
    err "Cannot sync a branch into itself."
    exit 2
fi

# === Pre-flight Check 10: Worktree is clean ===
# Filter out .ready (infrastructure marker from create-worktree.sh) — not a source file
dirty=$(git -C "$WorktreePath" status --porcelain 2>/dev/null | grep -vE '\.ready[[:space:]]*$') || dirty=""
if [ -n "$dirty" ]; then
    printf '\033[31mSTATUS: error\033[0m\n'
    printf 'WORKTREE_PATH: %s\n' "$WorktreePath"
    printf 'BRANCH: %s\n' "$BranchName"
    printf 'MERGE_TARGET: %s\n' "$mergeTarget"
    printf '\n'
    err "Worktree has uncommitted changes. Commit or stash them first, then re-run."
    err "Refusing to merge to avoid polluting the merge with uncommitted work."
    printf '\n'
    note "Dirty files:"
    printf '\033[90m%s\033[0m\n' "$dirty"
    exit 1
fi

# === Staleness Report ===
behind_commits=$(git -C "$RepoRoot" log "$BranchName..$mergeTarget" --oneline 2>/dev/null) || behind_commits=""
behind=0
if [ -n "$behind_commits" ]; then
    behind=$(printf '%s\n' "$behind_commits" | grep -c . || true)
fi
ahead_commits=$(git -C "$RepoRoot" log "$mergeTarget..$BranchName" --oneline 2>/dev/null) || ahead_commits=""
ahead=0
if [ -n "$ahead_commits" ]; then
    ahead=$(printf '%s\n' "$ahead_commits" | grep -c . || true)
fi

if [ "$behind" -eq 0 ]; then
    printf 'STATUS: up-to-date\n'
    printf 'WORKTREE_PATH: %s\n' "$WorktreePath"
    printf 'BRANCH: %s\n' "$BranchName"
    printf 'MERGE_TARGET: %s\n' "$mergeTarget"
    printf 'BEHIND: 0\n'
    printf 'AHEAD: %s\n' "$ahead"
    printf 'MODE: none\n'
    printf '\n'
    ok "Nothing to sync — $TaskId is already up to date with $mergeTarget."
    exit 0
fi

if [ "$ahead" -eq 0 ]; then
    mode="fast-forward"
else
    mode="merge-commit"
fi

# Print report
if [ "$DryRun" = "1" ]; then
    printf 'STATUS: dry-run\n'
else
    printf 'STATUS: syncing\n'
fi
printf 'WORKTREE_PATH: %s\n' "$WorktreePath"
printf 'BRANCH: %s\n' "$BranchName"
printf 'MERGE_TARGET: %s\n' "$mergeTarget"
printf 'BEHIND: %s\n' "$behind"
printf 'AHEAD: %s\n' "$ahead"
printf 'MODE: %s\n' "$mode"
printf '\n'

if [ "$behind" -gt 0 ]; then
    note "Incoming commits:"
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            printf '\033[90m  %s\033[0m\n' "$line"
        fi
    done < <(printf '%s\n' "$behind_commits")
    printf '\n'
fi

if [ "$DryRun" = "1" ]; then
    warn "No merge performed (--dry-run). Run without --dry-run to sync."
    exit 0
fi

# === The Merge ===
info "Syncing $TaskId with $mergeTarget..."

rc=0
git -C "$WorktreePath" merge "$mergeTarget" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    # Check for conflicts
    conflicts=$(git -C "$WorktreePath" diff --name-only --diff-filter=U 2>/dev/null) || conflicts=""
    if [ -n "$conflicts" ]; then
        conflicts_list=$(printf '%s\n' "$conflicts" | awk 'NR==1{out=$0; next} {out = out ", " $0} END{printf "%s", out}')
        printf '\033[31mSTATUS: conflict\033[0m\n'
        printf '\033[31mCONFLICTS: %s\033[0m\n' "$conflicts_list"
        printf '\n'
        err "Conflicts detected. Resolve them in the worktree, then:"
        err "  cd $WorktreePath"
        err "  git add <resolved-files>"
        err "  git commit"
        err "Or to abort: git merge --abort"
        exit 1
    fi
    printf '\033[31mSTATUS: error\033[0m\n'
    printf '\033[31mMerge failed (exit %s) for non-conflict reasons.\033[0m\n' "$rc"
    exit 2
fi

# === Success Reporting ===
new_head=$(git -C "$WorktreePath" rev-parse --short HEAD 2>/dev/null) || new_head=""
ok "Synced $TaskId with $mergeTarget"
if [ "$mode" = "fast-forward" ]; then
    note "Fast-forwarded (no merge commit)"
fi
printf 'MERGE_RESULT: success\n'
printf 'COMMIT: %s\n' "$new_head"
printf 'SYNCED_AT: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit 0
EOF_SYNC_WORKTREE

# === Install ===

# 1. Workflow scripts
for s in $SCRIPT_NAMES; do
    if [ -f "$ScriptsDir/$s.sh" ]; then
        chmod +x "$ScriptsDir/$s.sh" 2>/dev/null || true
    fi
done
ok "  [OK] $written workflow scripts written ($total available)"

# 2. Backlog.md
BacklogDir="$RepoPath/backlog"
if [ ! -d "$BacklogDir" ]; then
    # Ensure git config exists so backlog init's commit doesn't hang on missing user.name/email
    if [ -z "$(git -C "$RepoPath" config --get user.name 2>/dev/null)" ]; then
        git -C "$RepoPath" config --local user.name "AI Workspace"
    fi
    if [ -z "$(git -C "$RepoPath" config --get user.email 2>/dev/null)" ]; then
        git -C "$RepoPath" config --local user.email "ai@workspace.local"
    fi
    # Prevent git from opening an editor (hangs when stdin is not a TTY)
    GIT_EDITOR=true
    export GIT_EDITOR

    rc=0
    (cd "$RepoPath" && backlog init "$ProjectName" --defaults --agent-instructions agents --auto-open-browser false --no-git >/dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "  [OK] Backlog.md initialized"
    else
        err "Backlog.md init failed (exit $rc). Cannot continue without a board."
        err "Check that backlog.md is installed and that these flags are still valid:"
        err "  backlog init \"$ProjectName\" --defaults --agent-instructions agents --auto-open-browser false --no-git"
        exit 1
    fi

    # Configure the 5-column board (Backlog.md defaults to 3: To Do, In Progress, Done)
    ConfigYml="$BacklogDir/config.yml"
    if [ -f "$ConfigYml" ]; then
        sed -E 's|^statuses: \[.*\]$|statuses: ["To Do", "In Progress", "To Review", "To Merge", "Done"]|' "$ConfigYml" > "$ConfigYml.tmp" && mv "$ConfigYml.tmp" "$ConfigYml"
        ok "  [OK] Board configured with 5 columns (To Do -> In Progress -> To Review -> To Merge -> Done)"
    fi
else
    note "  [..] Backlog.md already initialized (skipping)"
    # Ensure existing boards also have the 5-column setup
    ConfigYml="$BacklogDir/config.yml"
    if [ -f "$ConfigYml" ]; then
        if ! grep -q "To Review" "$ConfigYml"; then
            sed -E 's|^statuses: \[.*\]$|statuses: ["To Do", "In Progress", "To Review", "To Merge", "Done"]|' "$ConfigYml" > "$ConfigYml.tmp" && mv "$ConfigYml.tmp" "$ConfigYml"
            ok "  [OK] Board upgraded to 5 columns"
        fi
    fi
fi

# 3. Software Engineering Principles
PrinciplesFile="$RepoPath/SOFTWARE_ENGINEERING_PRINCIPLES.md"
if [ "$Force" = "1" ] || [ ! -f "$PrinciplesFile" ]; then
    body=$(cat <<'PRINCIPLES_EOF'
# Software Engineering Principles

These principles are requirements, not suggestions. Every line of code should be
evaluated against them before committing. This document is portable — place it in
any project's root or reference it from any AGENTS.md.

---

## SOLID Principles

- **Single Responsibility** — Every module, class, and function does one thing.
  If you can't describe what a file does in one sentence, it does too much.
  A service that handles payments should not also send emails.
  A function that calculates a fee should not also persist it.

- **Open/Closed** — Software entities should be open for extension, closed for modification.
  Add new behavior by adding new code — don't modify existing code to add a feature.
  When you find yourself editing a working function to support a new case, stop and extend instead.

- **Liskov Substitution** — Subtypes must be substitutable for their base types.
  If a function accepts an interface, any implementation of that interface must work.
  Consumers should not need to know which concrete type they received.

- **Interface Segregation** — Don't force consumers to depend on methods they don't use.
  A client that only reads data shouldn't expose write methods.
  Split large interfaces into focused, role-specific ones.

- **Dependency Inversion** — Depend on abstractions, not concretions.
  Use dependency injection over direct instantiation.
  High-level modules should not import low-level modules — both should depend on abstractions.

---

## Design Principles

- **DRY (Don't Repeat Yourself)** — Every piece of knowledge has a single, unambiguous
  representation. If you see the same logic in two places, extract it. Duplicated
  logic is duplicated bugs — fix one, forget the other.

- **KISS (Keep It Simple, Stupid)** — The simplest solution that works is the best solution.
  A 10-line function that's clear beats a 3-line function that's clever.
  Readability is a feature, not a luxury.

- **YAGNI (You Ain't Gonna Need It)** — Don't build for hypothetical future requirements.
  Build what's needed now. If you don't have two implementations of something,
  don't create an abstraction for it.

- **Separation of Concerns** — Each layer has a distinct responsibility.
  Configuration, business logic, entry points, and operational tooling should be
  clearly separated. Don't mix concerns across layers.

- **Composition over Inheritance** — Prefer composing small, focused units over
  deep class hierarchies. A module that combines a client + handler is better
  than a module that inherits from a base class.

- **Encapsulation** — Hide internal implementation details.
  Other modules shouldn't know how a service stores its data internally.
  If you change the internals, nothing outside should break.

- **Orthogonality** — Components should be independent. Changing one shouldn't
  require changes to another. If two modules always change together, they're
  not orthogonal — consider merging them.

- **Reversibility** — Design decisions that are easy to reverse.
  Prefer choices that can be undone. Avoid irreversible commitments when a
  reversible one works. A feature flag is reversible. A schema migration is not.

- **Boy Scout Rule** — Leave the code cleaner than you found it.
  If you touch a file, fix one small thing — a typo, a missing type, a stale comment.
  The codebase improves incrementally with every change.

- **Principle of Least Privilege** — A module should only access the data and
  capabilities it needs. A function that calculates a fee shouldn't have access
  to the database. Grant minimum access, not maximum convenience.

- **Single Source of Truth** — Every piece of knowledge has exactly one authoritative
  representation. Configuration, constants, business rules — define once, reference
  everywhere. If two places define the same thing, they will diverge.

- **Convention over Configuration** — Reduce the number of decisions developers need
  to make. Establish patterns and follow them. When the codebase has a convention,
  follow it — even if you'd do it differently.

- **Defensive Programming** — Validate inputs at boundaries. Assume external data is
  untrusted. Check invariants. Don't trust that callers follow the contract.
  Validate early, fail fast, and produce clear error messages.

---

## What NOT to Do

- **Don't add dependencies without justification.** Every dependency is a future migration.
  If a small utility function solves the problem, write it — don't install a library.

- **Don't catch errors you can't handle.** If a function throws and you can't recover,
  let it propagate. Catching and re-throwing with a different message is noise.

- **Don't use `any`.** TypeScript exists for a reason. If you need `any`, the type
  system is telling you something is wrong. Fix the type, don't silence the compiler.

- **Don't create abstractions for hypothetical future use.** Abstract when you have
  2+ implementations, not before. A generic interface with one implementation
  is premature abstraction.

- **Don't leave TODOs without a tracking issue.** Every TODO must reference an issue
  number or a documented decision. Untracked TODOs are untracked debt.

- **Don't skip tests for "simple" code.** Simple code is where bugs hide. If it's
  simple, the test is simple too — write it.

- **Don't commit code that doesn't pass the test suite.** The CI pipeline is the
  source of truth. If CI fails, fix it before committing.

- **Don't assume the network is reliable.** Every external call must handle failures
  gracefully. Timeouts, retries, and fallbacks are not optional.

- **Don't hardcode values that should be configurable.** URLs, ports, timeouts,
  retry counts — these belong in environment variables or config, not in source code.

- **Don't mix business logic with infrastructure.** A function that calculates
  a value should not also make HTTP calls. Separate calculation from communication.

- **Don't create God objects.** A class or module that knows too much or does too much
  is a maintenance nightmare. Split it into focused units.

- **Don't create circular dependencies.** Module A imports Module B, Module B imports
  Module A. Break the cycle by extracting a shared interface or restructuring.

- **Don't optimize prematurely.** Don't optimize until you've measured. The bottleneck
  is rarely where you think it is. Profile first, then optimize.

- **Don't nest deeply.** More than 3 levels of indentation is a code smell.
  Extract into functions. Use early returns to reduce nesting.

- **Don't use flag arguments.** A boolean parameter that changes the function's behavior
  is a code smell. Split into two functions with clear names.

- **Don't use magic strings.** Hardcoded strings that carry meaning should be
  constants or enums. `"APPLIED"` should be `TransactionStatus.APPLIED`.

- **Don't scatter conditionals.** The same `if` logic spread across multiple files
  is a maintenance hazard. Centralize the decision.

---

## Code Organization Rules

- **One concern per file.** If a file does two unrelated things, split it.

- **Imports at the top.** No inline imports except for dynamic imports in specific
  cases (e.g., avoiding circular dependencies).

- **No magic numbers.** `0.15` means nothing. Define a named constant.

- **Constants over inline values.** Define constants for repeated values.

- **Error messages must be actionable.** "Operation failed" is useless.
  "CreateTransaction failed: 400 insufficient funds" tells you exactly what went wrong.

- **Log what matters.** Log state transitions, external API calls, errors, and
  business decisions. Don't log routine operations.

- **Comments explain why, not what.** The code explains what it does.
  Comments explain why it does it that way.

---

## Testing Principles

- **Tests are documentation.** A test should explain what the code does.
  If you can't understand the code from its tests, the tests are wrong.

- **Fast, isolated, deterministic.** Tests must be fast (seconds, not minutes),
  isolated (no shared state), and deterministic (same result every time).

- **Test behavior, not implementation.** Test what the code does, not how it does it.
  If you refactor the implementation, the tests should still pass.

- **Unit tests for logic, integration tests for wiring.** Unit tests verify
  calculations and decisions. Integration tests verify that modules connect correctly.

- **Test the edges.** The most bugs live at boundaries — API calls, database queries,
  file I/O, user input. Test these first.

- **One assertion per concept.** A test can have multiple assertions, but they should
  all verify the same concept. If you're testing two things, write two tests.

---

## Lint Rules (ESLint)

These rules are enforced by the linter. Violations block commits.

| Rule | Threshold | Principle enforced |
|---|---|---|
| `no-explicit-any` | `error` | No `any` — fix the type, don't silence the compiler |
| `no-magic-numbers` | `error`, ignore `[0, 1, -1]` | Constants over inline values |
| `no-unused-vars` | `error` | DRY, no dead code |
| `explicit-function-return-type` | `error` | Explicit over implicit |
| `complexity` | `error`, 10 | Single Responsibility |
| `max-lines-per-function` | `error`, 80 | Single Responsibility, KISS |
| `max-depth` | `error`, 3 | KISS, reduce nesting |
| `max-params` | `error`, 4 | Interface Segregation |
| `naming-convention` | `error` | Convention over Configuration |
| `prevent-abbreviations` | `error` | Readability — full names for clarity |
| `no-nested-ternary` | `error` | KISS, readability |
| `no-array-reduce` | `error` | Readability |
| `no-null` | `off` | Allow null when needed |
PRINCIPLES_EOF
)
    printf '%s' "$body" > "$PrinciplesFile"
    ok "  [OK] SOFTWARE_ENGINEERING_PRINCIPLES.md"
else
    note "  [..] SOFTWARE_ENGINEERING_PRINCIPLES.md already exists (skipping)"
fi

# 4. Task templates
DocsDir="$RepoPath/backlog/docs"
mkdir -p "$DocsDir"
TemplatesFile="$DocsDir/task-templates.md"
if [ ! -f "$TemplatesFile" ]; then
    body=$(cat <<'TEMPLATES_EOF'
# Task Templates

Use these templates when creating tasks with `backlog task create`.

## Feature Template

```
backlog task create "Implement <feature-name>" --description "## Summary
<One-sentence description of what needs to be built>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] <criterion 3>

## Relevant Files
- <file1>
- <file2>

## Spec Reference
- See <SpecFile.md> section <X>

## Notes
<Any additional context, constraints, or dependencies>"
```

## Bug Fix Template

```
backlog task create "Fix: <bug-description>" --description "## Summary
<What is broken and how it manifests>

## Steps to Reproduce
1. <step 1>
2. <step 2>
3. <step 3>

## Expected Behavior
<What should happen>

## Actual Behavior
<What actually happens>

## Relevant Files
- <file1>
- <file2>

## Notes
<Any additional context>"
```

## Refactor Template

```
backlog task create "Refactor: <what-to-refactor>" --description "## Summary
<What needs to be refactored and why>

## Current State
<How it works now and what's wrong with it>

## Target State
<How it should work after refactoring>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
- [ ] All existing tests still pass

## Relevant Files
- <file1>
- <file2>

## Notes
<Any risks, dependencies, or constraints>"
```

## Documentation Template

```
backlog task create "Docs: <what-to-document>" --description "## Summary
<What documentation needs to be written or updated>

## Scope
- [ ] <doc section 1>
- [ ] <doc section 2>

## Audience
<Who will read this documentation>

## Notes
<Any references or existing docs to build on>"
```
TEMPLATES_EOF
)
    printf '%s' "$body" > "$TemplatesFile"
    ok "  [OK] Task templates"
else
    note "  [..] Task templates already exist (skipping)"
fi

# 5. .gitignore
Gitignore="$RepoPath/.gitignore"
WorktreeIgnore="backlog/worktrees/"
if [ -f "$Gitignore" ]; then
    if ! grep -qF -- "$WorktreeIgnore" "$Gitignore"; then
        printf '\n%s\n' "$WorktreeIgnore" >> "$Gitignore"
        ok "  [OK] Added backlog/worktrees/ to .gitignore"
    else
        note "  [..] .gitignore already configured"
    fi
else
    printf '%s\n' "$WorktreeIgnore" > "$Gitignore"
    ok "  [OK] Created .gitignore"
fi

# === Verification ===

printf '\n'
info "  Verifying setup..."

verify_ok=1

# Verify scripts
for s in $SCRIPT_NAMES; do
    if [ ! -f "$RepoPath/scripts/$s.sh" ]; then
        err "  [X]  Missing: scripts/$s.sh"
        verify_ok=0
    fi
done

# Verify board config has 5 columns
ConfigYml="$RepoPath/backlog/config.yml"
if [ -f "$ConfigYml" ]; then
    if ! grep -q "To Review" "$ConfigYml"; then
        err "  [X]  Board config missing 'To Review' status"
        verify_ok=0
    fi
else
    err "  [X]  Missing: backlog/config.yml"
    verify_ok=0
fi

# Verify gitignore
if [ -f "$Gitignore" ]; then
    if ! grep -q "backlog/worktrees" "$Gitignore"; then
        err "  [X]  .gitignore missing backlog/worktrees/"
        verify_ok=0
    fi
fi

# Verify principles file
if [ ! -f "$PrinciplesFile" ]; then
    err "  [X]  Missing: SOFTWARE_ENGINEERING_PRINCIPLES.md"
    verify_ok=0
fi

# Verify backlog CLI
if ! have backlog; then
    err "  [X]  Backlog.md CLI not on PATH"
    verify_ok=0
fi

if [ "$verify_ok" = "1" ]; then
    ok "  [OK] All checks passed"
else
    warn "  [!]  Some checks failed — review the errors above"
fi

printf '\n'
info "  Done. Backlog.md board and workflow scripts are ready."
note "  The coder and reviewer agents will auto-load SOFTWARE_ENGINEERING_PRINCIPLES.md"
printf '\n'

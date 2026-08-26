<#
.SYNOPSIS
    Installs board-driven workflow files into a repo for use with the "ws" OpenCode profile.

.DESCRIPTION
    Sets up a single repo with everything it needs to work with the ws profile:
    - 9 workflow scripts in scripts/ (check-board, start-task, create-worktree, complete-task, approve-task, reject-task, read-verdict, merge-task, done-task)
    - SOFTWARE_ENGINEERING_PRINCIPLES.md (SOLID, DRY, KISS, YAGNI, testing, lint rules)
    - Backlog.md initialization
    - Task templates in backlog/docs/
    - backlog/worktrees/ added to .gitignore

    Does NOT create or modify AGENTS.md — that file is repo-specific and owned by the project.

    Run once per repo. Safe to re-run (skips existing files unless -Force).

.PARAMETER RepoPath
    Path to the git repo to set up.

.PARAMETER ProjectName
    Project name for the Backlog.md board. Defaults to the repo folder name.

.PARAMETER Force
    Overwrite existing workflow scripts and SOFTWARE_ENGINEERING_PRINCIPLES.md.

.EXAMPLE
    .\setup-repo.ps1 -RepoPath "C:\Projects\my-app"
    .\setup-repo.ps1 "C:\CData\MurdochDevelopment\kinematics-prototype" -Force
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$RepoPath,

    [Parameter(Mandatory=$false)]
    [string]$ProjectName,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

# === Resolve paths ===

if ($RepoPath -eq "~") { $RepoPath = $HOME }
elseif ($RepoPath -like "~/*" -or $RepoPath -like "~\*") { $RepoPath = Join-Path $HOME $RepoPath.Substring(2) }

if (-not (Test-Path $RepoPath)) {
    Write-Error "Repo path does not exist: $RepoPath"
    exit 1
}

if (-not $ProjectName) {
    $ProjectName = Split-Path $RepoPath -Leaf
}

Write-Host ""
Write-Host "  Setting up repo: $ProjectName" -ForegroundColor Cyan
Write-Host "  Path: $RepoPath" -ForegroundColor Gray
Write-Host ""

# === Workflow scripts (self-contained) ===

$Scripts = @{
    "check-board.ps1" = @'
param([Parameter(Mandatory=$false, Position=0)][string]$Status)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if ($Status) {
    Write-Host "Tasks with status: $Status" -ForegroundColor Cyan
    Write-Host "---"
    backlog task list --status $Status
} else {
    Write-Host "Full Board:" -ForegroundColor Cyan
    Write-Host "---"
    foreach ($s in @("To Do", "In Progress", "To Review", "To Merge", "Done")) {
        Write-Host ""
        Write-Host "[$s]" -ForegroundColor Yellow
        backlog task list --status $s 2>$null
    }
}
'@
    "start-task.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
Write-Host "Starting $TaskId..." -ForegroundColor Cyan
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 1 }
$taskText = $task -join "`n"
if ($taskText -match "Status:\s*\S+\s+(.+)") {
    $currentStatus = $Matches[1].Trim()
    if ($currentStatus -ne "To Do") {
        Write-Error "Cannot start $($TaskId): current status is '$currentStatus' (expected 'To Do'). Only tasks in 'To Do' can be started."; exit 1
    }
} else {
    Write-Error "Cannot determine current status of $($TaskId). The backlog output was unexpected."; exit 1
}
backlog task edit $TaskId -s "In Progress"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update $TaskId status."; exit 1 }
Write-Host ""
Write-Host "TASK_STARTED: $TaskId"
Write-Host "STATUS: In Progress"
'@
    "create-worktree.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git not found. Install Git first."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}
$WorktreePath = Join-Path $RepoRoot "backlog" "worktrees" $TaskId
$BranchName = $TaskId
$WorktreesDir = Join-Path $RepoRoot "backlog" "worktrees"
if (-not (Test-Path $WorktreesDir)) { New-Item -ItemType Directory -Path $WorktreesDir -Force | Out-Null }
$GitDirTarget = Join-Path $RepoRoot ".git" "worktrees" $TaskId

# === Validate existing worktree (deterministic 4-point check) ===
if (Test-Path $WorktreePath) {
    $gitFileExists = Test-Path (Join-Path $WorktreePath ".git")
    $gitDirRegistered = Test-Path $GitDirTarget
    $branchExists = $false
    $null = git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null
    if ($LASTEXITCODE -eq 0) { $branchExists = $true }
    $readyExists = Test-Path (Join-Path $WorktreePath ".ready")

    # Structurally valid = directory + .git file + gitdir registration + branch all exist
    $structurallyValid = $gitFileExists -and $gitDirRegistered -and $branchExists

    if ($structurallyValid -and $readyExists) {
        # Fully valid worktree (new-style) — skip
        Write-Host "Worktree already exists and is valid at $WorktreePath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "WORKTREE_PATH: $WorktreePath"
        Write-Host "BRANCH: $BranchName"
        exit 0
    }

    if ($structurallyValid -and -not $readyExists) {
        # Legacy worktree (created by old script) — repair metadata, don't destroy
        Write-Host "Worktree exists but was created by an older script. Repairing metadata..." -ForegroundColor Yellow

        # Determine the merge target (the branch the worktree was created from)
        # Strategy: find which branch contains the parent commit of the worktree HEAD
        Push-Location $RepoRoot
        try {
            $parentCommit = $null
            Push-Location $WorktreePath
            try {
                $parentCommit = git rev-parse HEAD~1 2>$null
            } finally {
                Pop-Location
            }

            $mergeTargetBranch = $null
            if ($parentCommit) {
                # Find which branch contains the parent commit
                $branches = git branch --contains $parentCommit 2>$null
                if ($branches) {
                    # Parse branch names (strip leading * and whitespace)
                    $branchNames = $branches | ForEach-Object { ($_.Trim() -replace '^\* ', '') } | Where-Object { $_ -ne $BranchName -and $_ -ne 'HEAD' }
                    $mergeTargetBranch = $branchNames | Select-Object -First 1
                }
            }

            if (-not $mergeTargetBranch) {
                # Fallback: use current branch if not the task branch
                $currentBranch = git branch --show-current 2>$null
                if ($currentBranch -and $currentBranch -ne $BranchName) {
                    $mergeTargetBranch = $currentBranch
                }
            }
        } finally {
            Pop-Location
        }

        if (-not $mergeTargetBranch) {
            Write-Error "Cannot determine merge target for legacy worktree. Please specify it manually by editing the ticket and adding:`n<!-- WORKTREE_START -->`n## Worktree`n- Path: ``$WorktreePath```n- Branch: ``$BranchName```n- MergeTarget: ``<branch-name>```n<!-- WORKTREE_END -->"
            exit 1
        }

        Write-Host "  Detected merge target: $mergeTargetBranch" -ForegroundColor Green

        # Write worktree ref to ticket
        $worktreeBlock = "`n`n<!-- WORKTREE_START -->`n## Worktree`n- Path: ``$WorktreePath```n- Branch: ``$BranchName```n- MergeTarget: ``$mergeTargetBranch```n<!-- WORKTREE_END -->"
        backlog task edit $TaskId --comment $worktreeBlock --comment-author "system" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Worktree reference written to ticket $TaskId" -ForegroundColor Green
        } else {
            Write-Warning "  Failed to write worktree reference to ticket (non-fatal)."
        }

        # Write .ready file
        $readyFile = Join-Path $WorktreePath ".ready"
        $readyContent = "WORKTREE_PATH: $WorktreePath`nBRANCH: $BranchName`nMERGE_TARGET: $mergeTargetBranch`nCREATED_AT: $(Get-Date -Format 'o')`nREPAIRED: true"
        Set-Content -LiteralPath $readyFile -Value $readyContent -NoNewline
        Write-Host "  Ready signal written (legacy repair)." -ForegroundColor Green

        Write-Host ""
        Write-Host "WORKTREE_PATH: $WorktreePath"
        Write-Host "BRANCH: $BranchName"
        Write-Host "MERGE_TARGET: $mergeTargetBranch"
        Write-Host "READY: true (repaired)"
        exit 0
    }

    # === Genuinely broken worktree — clean up ===
    Write-Host "Existing worktree is broken or incomplete. Cleaning up..." -ForegroundColor Yellow

    # 1. Remove stale lock files
    $lockFiles = @(
        (Join-Path $GitDirTarget "lock"),
        (Join-Path $RepoRoot ".git" "refs" "heads" "$BranchName.lock")
    )
    foreach ($lf in $lockFiles) {
        if (Test-Path $lf) { Remove-Item $lf -Force; Write-Host "  Removed stale lock: $lf" -ForegroundColor DarkGray }
    }

    # 2. Let git clean up
    git worktree remove $WorktreePath --force 2>$null

    # 3. Fallback: manual removal
    if (Test-Path $WorktreePath) { Remove-Item $WorktreePath -Recurse -Force -ErrorAction SilentlyContinue }

    # 4. Remove orphaned branch
    if ($branchExists) {
        git branch -D $BranchName 2>$null
        Write-Host "  Removed orphaned branch: $BranchName" -ForegroundColor DarkGray
    }

    Write-Host "  Cleanup complete. Creating fresh worktree..." -ForegroundColor DarkGray
}

# === Create worktree ===
$dirty = git status --porcelain 2>$null
if ($dirty) { Write-Warning "Current branch has uncommitted changes. Worktree will be created from the last commit." }
$currentBranch = git branch --show-current 2>$null
if (-not $currentBranch) { $currentBranch = "main" }

Write-Host "Creating worktree for $TaskId on branch $BranchName..." -ForegroundColor Cyan
git worktree add $WorktreePath -b $BranchName
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create worktree at $WorktreePath"; exit 1 }
Write-Host "Created worktree: $WorktreePath" -ForegroundColor Green

# === Verify checkout is complete ===
Write-Host "Verifying checkout..." -ForegroundColor Cyan
Push-Location $WorktreePath
try {
    $status = git status --porcelain 2>$null
} finally {
    Pop-Location
}

if ($status) {
    $missingCount = ($status | Where-Object { $_ } | Measure-Object).Count
    Write-Host "Checkout incomplete — $missingCount files missing. Cleaning up..." -ForegroundColor Red
    git worktree remove $WorktreePath --force 2>$null
    if (Test-Path $WorktreePath) { Remove-Item $WorktreePath -Recurse -Force -ErrorAction SilentlyContinue }
    git branch -D $BranchName 2>$null
    Write-Error "Worktree checkout incomplete ($missingCount files missing). The repo may be too large or the process was interrupted. Retry or check disk space."
    exit 1
}
Write-Host "Checkout verified — all files present." -ForegroundColor Green

# === Write worktree ref to ticket ===
$worktreeBlock = "`n`n<!-- WORKTREE_START -->`n## Worktree`n- Path: ``$WorktreePath```n- Branch: ``$BranchName```n- MergeTarget: ``$currentBranch```n<!-- WORKTREE_END -->"
backlog task edit $TaskId --comment $worktreeBlock --comment-author "system" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Worktree reference written to ticket $TaskId" -ForegroundColor Green
} else {
    Write-Warning "Failed to write worktree reference to ticket (non-fatal)."
}

# === Write .ready signal file (deterministic callback for the agent) ===
$readyFile = Join-Path $WorktreePath ".ready"
$readyContent = "WORKTREE_PATH: $WorktreePath`nBRANCH: $BranchName`nMERGE_TARGET: $currentBranch`nCREATED_AT: $(Get-Date -Format 'o')"
Set-Content -LiteralPath $readyFile -Value $readyContent -NoNewline
Write-Host "Ready signal written." -ForegroundColor Green

Write-Host ""
Write-Host "WORKTREE_PATH: $WorktreePath"
Write-Host "BRANCH: $BranchName"
Write-Host "MERGE_TARGET: $currentBranch"
Write-Host "READY: true"
'@
    "complete-task.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 1 }
$taskText = $task -join "`n"
if ($taskText -match "Status:\s*\S+\s+(.+)") {
    $currentStatus = $Matches[1].Trim()
    if ($currentStatus -ne "In Progress") {
        Write-Error "Cannot complete $($TaskId): current status is '$currentStatus' (expected 'In Progress')."; exit 1
    }
} else {
    Write-Error "Cannot determine current status of $($TaskId). The backlog output was unexpected."; exit 1
}
Write-Host "Moving $TaskId to To Review..." -ForegroundColor Cyan
backlog task edit $TaskId -s "To Review"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update $TaskId status."; exit 1 }
Write-Host ""
Write-Host "TASK_COMPLETED: $TaskId"
Write-Host "STATUS: To Review"
'@
    "approve-task.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 1 }
$taskText = $task -join "`n"
if ($taskText -match "Status:\s*\S+\s+(.+)") {
    $currentStatus = $Matches[1].Trim()
    if ($currentStatus -ne "To Review") {
        Write-Error "Cannot approve $($TaskId): current status is '$currentStatus' (expected 'To Review')."; exit 1
    }
} else {
    Write-Error "Cannot determine current status of $($TaskId). The backlog output was unexpected."; exit 1
}
Write-Host "Approving $TaskId (moving to To Merge)..." -ForegroundColor Cyan
backlog task edit $TaskId -s "To Merge"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update $TaskId status."; exit 1 }
Write-Host ""
Write-Host "TASK_APPROVED: $TaskId"
Write-Host "STATUS: To Merge"
'@
    "merge-task.ps1" = @'
param(
    [Parameter(Mandatory=$true, Position=0)][string]$TaskId,
    [Parameter(Mandatory=$false)]
    [ValidateSet("no-ff", "squash")]
    [string]$Strategy = "no-ff"
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git not found."; exit 2
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$BranchName = $TaskId
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) { Write-Error "Not in a git repo."; exit 2 }
$task = & backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 2 }
$taskText = $task -join "`n"
$mergeTarget = $null
if ($taskText -match 'MergeTarget:\s*`([^`]+)`') {
    $mergeTarget = $Matches[1].Trim()
}
if (-not $mergeTarget) {
    Write-Error "Cannot determine merge target from ticket. The WORKTREE block is missing or malformed. Run create-worktree.ps1 to repair the ticket metadata."; exit 2
}
if (-not (git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null)) {
    Write-Error "Branch $BranchName does not exist."; exit 2
}
$currentBranch = git branch --show-current 2>$null
if (-not $currentBranch) { Write-Error "Cannot determine current branch."; exit 2 }
if ($currentBranch -eq $BranchName) {
    Write-Error "Cannot merge $BranchName into itself. Switch to the target branch first."; exit 2
}
$dirty = git status --porcelain 2>$null
if ($dirty) { Write-Warning "Target branch has uncommitted changes. Merge may fail." }
if ($currentBranch -ne $mergeTarget) {
    Write-Error "Cannot merge: current branch is '$currentBranch' but the worktree was created from '$mergeTarget'. Switch to '$mergeTarget' first: git checkout $mergeTarget"
    exit 2
}
# === Sanity check: refuse if too many files would be deleted ===
$deletedFiles = git diff --name-only --diff-filter=D "$mergeTarget...$BranchName" 2>$null
$deletedCount = ($deletedFiles | Where-Object { $_ } | Measure-Object).Count
if ($deletedCount -gt 50) {
    Write-Error "Refusing to merge: $deletedCount files would be deleted. This looks like a worktree checkout issue, not a real change. Aborting. If this is intentional, run the merge manually: git merge --no-ff $BranchName"
    exit 2
}
Write-Host "Diff sanity check passed ($deletedCount files would be deleted, threshold: 50)." -ForegroundColor Green
Write-Host "Merging $BranchName into $mergeTarget ($Strategy)..." -ForegroundColor Cyan
if ($Strategy -eq "squash") {
    git merge --squash $BranchName 2>&1
    if ($LASTEXITCODE -ne 0) {
        $conflicts = git diff --name-only --diff-filter=U 2>$null
        if ($conflicts) {
            Write-Host "CONFLICTS: $conflicts" -ForegroundColor Red
            exit 1
        }
        Write-Error "Merge failed."; exit 2
    }
    Write-Host "Squash staged. Commit with: git commit -m `"<message> (task-id)`"" -ForegroundColor Green
    Write-Host "MERGE_RESULT: squash-staged"
    exit 0
} else {
    git merge --no-ff $BranchName -m "Merge $TaskId into $mergeTarget" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $conflicts = git diff --name-only --diff-filter=U 2>$null
        if ($conflicts) {
            Write-Host "CONFLICTS: $conflicts" -ForegroundColor Red
            exit 1
        }
        Write-Error "Merge failed."; exit 2
    }
    Write-Host "Merge successful." -ForegroundColor Green
    Write-Host "MERGE_RESULT: success"
    exit 0
}
'@
    "done-task.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git not found."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 1 }
$taskText = $task -join "`n"
if ($taskText -match "Status:\s*\S+\s+(.+)") {
    $currentStatus = $Matches[1].Trim()
    if ($currentStatus -ne "To Merge") {
        Write-Error "Cannot finalize $($TaskId): current status is '$currentStatus' (expected 'To Merge')."; exit 1
    }
} else {
    Write-Error "Cannot determine current status of $($TaskId). The backlog output was unexpected."; exit 1
}
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$WorktreePath = Join-Path $RepoRoot "backlog" "worktrees" $TaskId
$BranchName = $TaskId
Write-Host "Finalizing $TaskId..." -ForegroundColor Cyan
backlog task edit $TaskId -s "Done"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update $TaskId status."; exit 1 }
if (Test-Path $WorktreePath) {
    git worktree remove $WorktreePath --force 2>$null
    if ($LASTEXITCODE -ne 0 -or (Test-Path $WorktreePath)) {
        Write-Warning "Failed to remove worktree at $WorktreePath. Remove manually: git worktree remove $WorktreePath --force"
        Write-Host "Skipping branch deletion — branch cannot be deleted while worktree is checked out." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "TASK_DONE: $TaskId"
        Write-Host "STATUS: Done (worktree retained — remove manually before branch deletion)"
        exit 0
    } else {
        Write-Host "Removed worktree: $WorktreePath" -ForegroundColor Green
    }
} else {
    Write-Host "Worktree not found (already removed?): $WorktreePath" -ForegroundColor DarkGray
}
if (git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null) {
    git branch -d $BranchName 2>$null
    if ($LASTEXITCODE -ne 0) {
        git branch -D $BranchName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Force-deleted branch: $BranchName" -ForegroundColor Green
        } else {
            Write-Warning "Failed to delete branch $BranchName. Remove manually: git branch -D $BranchName"
        }
    } else {
        Write-Host "Deleted branch: $BranchName" -ForegroundColor Green
    }
}
Write-Host ""
Write-Host "TASK_DONE: $TaskId"
Write-Host "STATUS: Done"
'@
    "read-verdict.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 2
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 2 }
$taskText = $task -join "`n"
if ($taskText -match "<!--\s*VERDICT:\s*APPROVED\s*-->") {
    Write-Host "VERDICT: APPROVED"
    Write-Host "TASK_ID: $TaskId"
    exit 0
} elseif ($taskText -match "<!--\s*VERDICT:\s*REJECTED\s*-->") {
    Write-Host "VERDICT: REJECTED"
    Write-Host "TASK_ID: $TaskId"
    exit 1
} else {
    Write-Host "VERDICT: NOT_FOUND"
    Write-Host "TASK_ID: $TaskId"
    Write-Error "No VERDICT tag found in task $TaskId. The reviewer may not have completed the review."
    exit 2
}
'@
    "reject-task.ps1" = @'
param([Parameter(Mandatory=$true, Position=0)][string]$TaskId)
$ErrorActionPreference = "Stop"
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Error "Backlog.md CLI not found. Run install-deps.ps1 first."; exit 1
}
if ($TaskId -notmatch "^task-") { $TaskId = "task-$TaskId" }
$task = backlog task view $TaskId --plain 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Task $TaskId not found."; exit 1 }
$taskText = $task -join "`n"
if ($taskText -match "Status:\s*\S+\s+(.+)") {
    $currentStatus = $Matches[1].Trim()
    if ($currentStatus -ne "To Review") {
        Write-Error "Cannot reject $($TaskId): current status is '$currentStatus' (expected 'To Review')."; exit 1
    }
} else {
    Write-Error "Cannot determine current status of $($TaskId). The backlog output was unexpected."; exit 1
}
Write-Host "Rejecting $TaskId (moving back to In Progress)..." -ForegroundColor Cyan
backlog task edit $TaskId -s "In Progress"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update $TaskId status."; exit 1 }
Write-Host ""
Write-Host "TASK_REJECTED: $TaskId"
Write-Host "STATUS: In Progress"
'@
}

# === Software Engineering Principles ===

$EngineeringPrinciples = @'
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
'@

# === Task templates ===

$TaskTemplates = @'
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
'@

# === Install ===

# 1. Workflow scripts
$ScriptsDir = Join-Path $RepoPath "scripts"
if (-not (Test-Path $ScriptsDir)) {
    New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null
}
foreach ($scriptName in $Scripts.Keys) {
    $scriptPath = Join-Path $ScriptsDir $scriptName
    $shouldWrite = $Force -or -not (Test-Path $scriptPath)
    if ($shouldWrite) {
        Set-Content -LiteralPath $scriptPath -Value $Scripts[$scriptName] -NoNewline
    }
}
$written = 0
foreach ($scriptName in $Scripts.Keys) {
    $scriptPath = Join-Path $ScriptsDir $scriptName
    if ($Force -or -not (Test-Path $scriptPath)) { $written++ }
}
Write-Host "  [OK] $written workflow scripts written ($($Scripts.Count) available)" -ForegroundColor Green

# 2. Backlog.md
$BacklogDir = Join-Path $RepoPath "backlog"
if (-not (Test-Path $BacklogDir)) {
    # Ensure git config exists so backlog init's commit doesn't hang on missing user.name/email
    if (-not (git config --get user.name 2>$null)) { git config --local user.name "AI Workspace" }
    if (-not (git config --get user.email 2>$null)) { git config --local user.email "ai@workspace.local" }
    # Prevent git from opening an editor (hangs on Windows when stdin is not a TTY)
    $env:GIT_EDITOR = "true"

    Push-Location $RepoPath
    try {
        $null = backlog init "$ProjectName" --defaults --agent-instructions agents --auto-open-browser false --no-git 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Backlog.md initialized" -ForegroundColor Green
        } else {
            Write-Error "Backlog.md init failed (exit $LASTEXITCODE). Cannot continue without a board.`nCheck that backlog.md is installed and that these flags are still valid:`n  backlog init `"$ProjectName`" --defaults --agent-instructions agents --auto-open-browser false --no-git"
            exit 1
        }
    } finally {
        Pop-Location
    }

    # Configure the 5-column board (Backlog.md defaults to 3: To Do, In Progress, Done)
    $ConfigYml = Join-Path $BacklogDir "config.yml"
    if (Test-Path $ConfigYml) {
        $content = Get-Content -Raw -LiteralPath $ConfigYml
        $content = $content -replace 'statuses: \[.*\]', 'statuses: ["To Do", "In Progress", "To Review", "To Merge", "Done"]'
        Set-Content -LiteralPath $ConfigYml -Value $content -NoNewline
        Write-Host "  [OK] Board configured with 5 columns (To Do -> In Progress -> To Review -> To Merge -> Done)" -ForegroundColor Green
    }
} else {
    Write-Host "  [..] Backlog.md already initialized (skipping)" -ForegroundColor Gray
    # Ensure existing boards also have the 5-column setup
    $ConfigYml = Join-Path $BacklogDir "config.yml"
    if (Test-Path $ConfigYml) {
        $content = Get-Content -Raw -LiteralPath $ConfigYml
        if ($content -notmatch 'To Review') {
            $content = $content -replace 'statuses: \[.*\]', 'statuses: ["To Do", "In Progress", "To Review", "To Merge", "Done"]'
            Set-Content -LiteralPath $ConfigYml -Value $content -NoNewline
            Write-Host "  [OK] Board upgraded to 5 columns" -ForegroundColor Green
        }
    }
}

# 3. Software Engineering Principles
$PrinciplesFile = Join-Path $RepoPath "SOFTWARE_ENGINEERING_PRINCIPLES.md"
if ($Force -or -not (Test-Path $PrinciplesFile)) {
    Set-Content -LiteralPath $PrinciplesFile -Value $EngineeringPrinciples -NoNewline
    Write-Host "  [OK] SOFTWARE_ENGINEERING_PRINCIPLES.md" -ForegroundColor Green
} else {
    Write-Host "  [..] SOFTWARE_ENGINEERING_PRINCIPLES.md already exists (skipping)" -ForegroundColor Gray
}

# 4. Task templates
$DocsDir = Join-Path $RepoPath "backlog" "docs"
if (-not (Test-Path $DocsDir)) {
    New-Item -ItemType Directory -Path $DocsDir -Force | Out-Null
}
$TemplatesFile = Join-Path $DocsDir "task-templates.md"
if (-not (Test-Path $TemplatesFile)) {
    Set-Content -LiteralPath $TemplatesFile -Value $TaskTemplates -NoNewline
    Write-Host "  [OK] Task templates" -ForegroundColor Green
} else {
    Write-Host "  [..] Task templates already exist (skipping)" -ForegroundColor Gray
}

# 5. .gitignore
$Gitignore = Join-Path $RepoPath ".gitignore"
$WorktreeIgnore = "backlog/worktrees/"
if (Test-Path $Gitignore) {
    $content = Get-Content -Raw -LiteralPath $Gitignore
    if ($content -notmatch [regex]::Escape($WorktreeIgnore)) {
        Add-Content -LiteralPath $Gitignore -Value "`n$WorktreeIgnore"
        Write-Host "  [OK] Added backlog/worktrees/ to .gitignore" -ForegroundColor Green
    } else {
        Write-Host "  [..] .gitignore already configured" -ForegroundColor Gray
    }
} else {
    Set-Content -LiteralPath $Gitignore -Value $WorktreeIgnore
    Write-Host "  [OK] Created .gitignore" -ForegroundColor Green
}

# === Verification ===

Write-Host ""
Write-Host "  Verifying setup..." -ForegroundColor Cyan

$verifyOK = $true

# Verify scripts
$expectedScripts = @("check-board.ps1", "start-task.ps1", "create-worktree.ps1", "complete-task.ps1", "approve-task.ps1", "reject-task.ps1", "read-verdict.ps1", "merge-task.ps1", "done-task.ps1")
foreach ($s in $expectedScripts) {
    $spath = Join-Path $RepoPath "scripts" $s
    if (-not (Test-Path $spath)) {
        Write-Host "  [X]  Missing: scripts/$s" -ForegroundColor Red
        $verifyOK = $false
    }
}

# Verify board config has 5 columns
$ConfigYml = Join-Path $RepoPath "backlog" "config.yml"
if (Test-Path $ConfigYml) {
    $cfgContent = Get-Content -Raw -LiteralPath $ConfigYml
    if ($cfgContent -notmatch "To Review") {
        Write-Host "  [X]  Board config missing 'To Review' status" -ForegroundColor Red
        $verifyOK = $false
    }
} else {
    Write-Host "  [X]  Missing: backlog/config.yml" -ForegroundColor Red
    $verifyOK = $false
}

# Verify gitignore
$GitignorePath = Join-Path $RepoPath ".gitignore"
if (Test-Path $GitignorePath) {
    $giContent = Get-Content -Raw -LiteralPath $GitignorePath
    if ($giContent -notmatch "backlog/worktrees") {
        Write-Host "  [X]  .gitignore missing backlog/worktrees/" -ForegroundColor Red
        $verifyOK = $false
    }
}

# Verify principles file
$PrinciplesPath = Join-Path $RepoPath "SOFTWARE_ENGINEERING_PRINCIPLES.md"
if (-not (Test-Path $PrinciplesPath)) {
    Write-Host "  [X]  Missing: SOFTWARE_ENGINEERING_PRINCIPLES.md" -ForegroundColor Red
    $verifyOK = $false
}

# Verify backlog CLI
if (-not (Get-Command backlog -ErrorAction SilentlyContinue)) {
    Write-Host "  [X]  Backlog.md CLI not on PATH" -ForegroundColor Red
    $verifyOK = $false
}

if ($verifyOK) {
    Write-Host "  [OK] All checks passed" -ForegroundColor Green
} else {
    Write-Host "  [!]  Some checks failed — review the errors above" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Done. Backlog.md board and workflow scripts are ready." -ForegroundColor Cyan
Write-Host "  The coder and reviewer agents will auto-load SOFTWARE_ENGINEERING_PRINCIPLES.md" -ForegroundColor DarkGray
Write-Host ""

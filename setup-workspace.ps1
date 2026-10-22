<#
.SYNOPSIS
    Full workspace setup orchestrator - installs deps, sets up repos, generates layout.

.DESCRIPTION
    One-command setup for a multi-agent OpenCode workspace. Calls the other 3 scripts:
    1. install-deps.ps1  - ensures git, node, bun, zellij, backlog, ocx, opencode are installed
    2. setup-repo.ps1    - for each repo: installs scripts, AGENTS.md, backlog.md
    3. generate-layout.ps1 - creates a zellij layout with tabs for each repo

    Designed to be shared with team members. They run this one script and get the full setup.

.PARAMETER ProjectName
    Display name (e.g., "My App", "PMDG Tablet"). Used ONLY for the layout name.
    Each repo's AGENTS.md uses its own folder name as the title.

.PARAMETER LayoutName
    Zellij layout name (for: zellij --config <full-config-path> --layout <name>). Defaults to a slug of ProjectName + "-dev".

.PARAMETER Repos
    Array of repo paths to set up.

.PARAMETER ProfileName
    OpenCode profile to use. Defaults to "ws" (the shared workspace profile).

.PARAMETER PlanDir
    Folder path where Plan-WS (and the Shell tab) should run. Need not be a repo —
    any existing folder is accepted. Defaults to empty: with a single repo it uses
    that repo; with multiple repos the script prompts (accept a listed number or a
    custom folder path).

.PARAMETER SkipDeps
    Skip dependency installation (assume already installed).

.PARAMETER Force
    Overwrite existing files without prompting.

.EXAMPLE
    # Interactive - prompts for everything
    .\setup-workspace.ps1

.EXAMPLE
    # Fully parameterized
    .\setup-workspace.ps1 -ProjectName "My App" -Repos @("C:\Projects\my-backend", "C:\Projects\my-frontend")

.EXAMPLE
    # Single repo, skip deps (already installed)
    .\setup-workspace.ps1 -ProjectName "PMDG Tablet" -Repos @("C:\CData\PMDG\PMDG_Tablet") -SkipDeps -Force
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectName,

    [Parameter(Mandatory=$false)]
    [string]$LayoutName,

    [Parameter(Mandatory=$false)]
    [string[]]$Repos,

    [Parameter(Mandatory=$false)]
    [string]$ProfileName = "ws",

    [Parameter(Mandatory=$false)]
    [string]$PlanDir = "",

    [switch]$SkipDeps,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

# === Helpers ===

function Write-Banner {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    Multi-Agent OpenCode Workspace - Full Setup" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Convert-ToSlug {
    param([string]$Text)
    $slug = $Text.ToLower() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

# === Resolve script directory ===

$ScriptDir = Split-Path -Parent $PSCommandPath
$InstallDepsScript = Join-Path $ScriptDir "install-deps.ps1"
$SetupRepoScript = Join-Path $ScriptDir "setup-repo.ps1"
$GenerateLayoutScript = Join-Path $ScriptDir "generate-layout.ps1"

foreach ($s in @($InstallDepsScript, $SetupRepoScript, $GenerateLayoutScript)) {
    if (-not (Test-Path $s)) {
        Write-Error "Missing script: $s`nAll 4 scripts must be in the same directory."
        exit 1
    }
}

# === Gather parameters (interactive) ===

Clear-Host
Write-Banner

if (-not $ProjectName) {
    while ($true) {
        Write-Host "    Project name (e.g., 'My App', 'PMDG Tablet'):" -ForegroundColor White
        Write-Host "    > " -ForegroundColor Cyan -NoNewline
        $ProjectName = Read-Host
        if ($ProjectName) { break }
        Write-Host "      [X] Project name is required." -ForegroundColor Red
    }
}

if (-not $LayoutName) {
    $LayoutName = "$(Convert-ToSlug $ProjectName)-dev"
}

if (-not $Repos -or $Repos.Count -eq 0) {
    Write-Host ""
    Write-Host "    Enter repo paths (one per line, empty line to finish):" -ForegroundColor White
    $Repos = @()
    while ($true) {
        Write-Host "    > " -ForegroundColor Cyan -NoNewline
        $repoPath = Read-Host
        if (-not $repoPath) { break }
        if ($repoPath -eq "~") { $repoPath = $HOME }
        elseif ($repoPath -like "~/*" -or $repoPath -like "~\*") { $repoPath = Join-Path $HOME $repoPath.Substring(2) }
        if (-not (Test-Path $repoPath)) {
            Write-Host "      [X] Path does not exist: $repoPath" -ForegroundColor Red
            continue
        }
        $Repos += $repoPath
    }
    if ($Repos.Count -eq 0) {
        Write-Error "At least one repo path is required."
        exit 1
    }
}

# === Resolve Plan dir (only prompted when multiple repos) ===

if ($Repos.Count -eq 1) {
    $PlanDir = $Repos[0]
} elseif (-not $PlanDir) {
    Write-Host ""
    Write-Host "    Which folder should Plan-WS run in? (Shell tab follows it)" -ForegroundColor White
    Write-Host "    This can be a repo below or any other existing folder." -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Repos.Count; $i++) {
        $n = $i + 1
        Write-Host "      $n. $($Repos[$i])" -ForegroundColor Gray
    }
    while ($true) {
        Write-Host "    Enter a number 1-$($Repos.Count), or a folder path [default 1]: " -ForegroundColor Cyan -NoNewline
        $choice = Read-Host
        if (-not $choice) { $choice = "1" }
        $chosen = 0
        if ([int]::TryParse($choice, [ref]$chosen)) {
            $idx = $chosen - 1
            if ($idx -ge 0 -and $idx -lt $Repos.Count) {
                $PlanDir = $Repos[$idx]
                break
            }
            Write-Host "      [X] Number out of range (valid 1-$($Repos.Count))." -ForegroundColor Red
            continue
        }
        $candidate = $choice
        if ($candidate -eq "~") { $candidate = $HOME }
        elseif ($candidate -like "~/*" -or $candidate -like "~\*") { $candidate = Join-Path $HOME $candidate.Substring(2) }
        if (Test-Path $candidate) {
            $PlanDir = $candidate
            break
        }
        Write-Host "      [X] Path does not exist: $candidate" -ForegroundColor Red
    }
} else {
    # Explicitly passed via param - validate it exists (with ~ expansion)
    $candidate = $PlanDir
    if ($candidate -eq "~") { $candidate = $HOME }
    elseif ($candidate -like "~/*" -or $candidate -like "~\*") { $candidate = Join-Path $HOME $candidate.Substring(2) }
    if (-not (Test-Path $candidate)) {
        Write-Error "PlanDir does not exist: $candidate"
        exit 1
    }
    $PlanDir = $candidate
}

# === Summary ===

Write-Host ""
Write-Host "    Setup plan:" -ForegroundColor White
Write-Host "      Project:  $ProjectName" -ForegroundColor Gray
Write-Host "      Profile:  $ProfileName" -ForegroundColor Gray
Write-Host "      Layout:   $LayoutName" -ForegroundColor Gray
Write-Host "      Repos:    $($Repos.Count)" -ForegroundColor Gray
foreach ($repo in $Repos) {
    Write-Host "        $($repo)" -ForegroundColor DarkGray
}
Write-Host "      Plan dir:  $PlanDir" -ForegroundColor Gray
if ($SkipDeps) {
    Write-Host "      Deps:     SKIPPED" -ForegroundColor Gray
} else {
    Write-Host "      Deps:     Will check/install" -ForegroundColor Gray
}
Write-Host ""

if (-not $Force) {
    Write-Host "    > Proceed? (Y/n) " -ForegroundColor Cyan -NoNewline
    $proceed = Read-Host
    if ($proceed -eq "n" -or $proceed -eq "N") {
        Write-Host "    Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# === Step 1: Install Dependencies ===

if ($SkipDeps) {
    Write-Host ""
    Write-Host "  -- Step 1: Dependencies (skipped) ---------------" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "  -- Step 1: Install Dependencies -----------------" -ForegroundColor Yellow
    & $InstallDepsScript
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Dependency install had issues. Continuing anyway..."
    }
}

# === Step 2: Set Up Repos ===

Write-Host ""
Write-Host "  -- Step 2: Set Up Repos -------------------------" -ForegroundColor Yellow

for ($i = 0; $i -lt $Repos.Count; $i++) {
    $repoArgs = @{
        RepoPath = $Repos[$i]
    }
    if ($Force) { $repoArgs["Force"] = $true }
    & $SetupRepoScript @repoArgs
}

# === Step 3: Generate Zellij Layout ===

Write-Host ""
Write-Host "  -- Step 3: Generate Zellij Layout ---------------" -ForegroundColor Yellow

$layoutArgs = @{
    LayoutName = $LayoutName
    Repos = $Repos
    ProfileName = $ProfileName
    PlanDir = $PlanDir
}
if ($Force) { $layoutArgs["Force"] = $true }
& $GenerateLayoutScript @layoutArgs

# === Done ===

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Edit AGENTS.md in each repo:" -ForegroundColor White
foreach ($repo in $Repos) {
    Write-Host "     $repo\AGENTS.md" -ForegroundColor DarkGray
}
Write-Host ""
$zellijConfigDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    Join-Path $env:APPDATA "Zellij" "config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    $base = if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
    Join-Path $base "zellij"
}
$configPath = Join-Path $zellijConfigDir "config-$LayoutName.kdl"
Write-Host "  2. Launch:" -ForegroundColor White
Write-Host "     zellij --config `"$configPath`" --layout $LayoutName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Agents available (oc -p $ProfileName):" -ForegroundColor White
Write-Host "     /agent Plan-WS    -> creates tasks" -ForegroundColor DarkGray
Write-Host "     /agent Build-WS   -> orchestrates builds" -ForegroundColor DarkGray
Write-Host "     /agent Merger-WS  -> merges tasks" -ForegroundColor DarkGray
Write-Host ""

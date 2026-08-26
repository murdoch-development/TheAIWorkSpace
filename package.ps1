<#
.SYNOPSIS
    Creates a shareable zip of The AI Workspace for distribution to teammates.

.DESCRIPTION
    Bundles everything a colleague needs:
    - install-deps.ps1, setup-repo.ps1, generate-layout.ps1, setup-workspace.ps1, package.ps1
    - README.md
    - The full ws profile (agents, skills, plugins, commands, tools, configs)
    - A bootstrap.ps1 that unpacks and runs setup-workspace.ps1

    The resulting zip is self-contained. A colleague just extracts and runs bootstrap.ps1.
    Including package.ps1 lets recipients re-package after customizing.

.EXAMPLE
    .\package.ps1
    # Creates TheAIWorkSpace-<date>.zip in the current directory
#>

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $PSCommandPath
$Date = Get-Date -Format "yyyy-MM-dd"
$ZipPath = Join-Path (Get-Location) "TheAIWorkSpace-$Date.zip"

# === Collect files ===

$StagingDir = Join-Path $env:TEMP "TheAIWorkSpace-staging"
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

# 1. Copy the 5 scripts + README
$scripts = @("install-deps.ps1", "setup-repo.ps1", "generate-layout.ps1", "setup-workspace.ps1", "package.ps1", "README.md")
foreach ($s in $scripts) {
    $src = Join-Path $SourceDir $s
    if (Test-Path $src) {
        Copy-Item $src $StagingDir -Force
    } else {
        Write-Warning "Missing: $s"
    }
}

# 2. Copy the ws profile
$ConfigDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    Join-Path $env:USERPROFILE ".config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
}
$WsProfileDir = Join-Path $ConfigDir "opencode" "profiles" "ws"

if (Test-Path $WsProfileDir) {
    $ProfileDest = Join-Path $StagingDir "profile"
    Copy-Item $WsProfileDir $ProfileDest -Recurse -Force

    # Clean up stuff that shouldn't be distributed
    $ReceiptDir = Join-Path $ProfileDest ".ocx"
    if (Test-Path $ReceiptDir) { Remove-Item $ReceiptDir -Recurse -Force }
    $NodeModules = Join-Path $ProfileDest "node_modules"
    if (Test-Path $NodeModules) { Remove-Item $NodeModules -Recurse -Force }
    $BunLock = Join-Path $ProfileDest "bun.lock"
    if (Test-Path $BunLock) { Remove-Item $BunLock -Force }

    Write-Host "[OK] Profile included" -ForegroundColor Green
} else {
    Write-Warning "ws profile not found at: $WsProfileDir"
    Write-Warning "Package will not include the profile. Colleague will need it separately."
}

# 3. Create bootstrap.ps1
$Bootstrap = @'
<#
.SYNOPSIS
    Bootstrap installer for The AI Workspace.

.DESCRIPTION
    Extracts the ws profile to ~/.config/opencode/profiles/ws,
    then runs setup-workspace.ps1 which handles everything else.

    Just run this script - it will prompt you through the rest.

.EXAMPLE
    .\bootstrap.ps1
#>
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "     The AI Workspace - Bootstrap Installer    " -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# === Step 0: Execution Policy (Windows) ===

if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -eq "Restricted" -or $policy -eq "AllSigned") {
        Write-Host "  Step 0: Fixing PowerShell execution policy..." -ForegroundColor Yellow
        Write-Host "  Current policy: $policy (blocks scripts)" -ForegroundColor Gray
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host "  [OK] Set to RemoteSigned" -ForegroundColor Green
        } catch {
            Write-Host "  [!]  Could not set automatically. Run this manually:" -ForegroundColor Yellow
            Write-Host "       Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
            Write-Host "  Then re-run: .\bootstrap.ps1" -ForegroundColor Gray
            exit 1
        }
    }
}

# === Step 1: Install Dependencies ===

Write-Host "  Step 1: Checking and installing dependencies..." -ForegroundColor Yellow
$InstallDeps = Join-Path $ScriptDir "install-deps.ps1"
if (Test-Path $InstallDeps) {
    & $InstallDeps
} else {
    Write-Host "  [X]  install-deps.ps1 not found" -ForegroundColor Red
    exit 1
}

# Refresh PATH for current session (bun may have just been installed)
if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    $bunPath = Join-Path $env:USERPROFILE ".bun" "bin"
    if ((Test-Path $bunPath) -and ($env:PATH -notlike "*$bunPath*")) {
        $env:PATH = "$bunPath;$env:PATH"
    }
    $npmPath = Join-Path $env:APPDATA "npm"
    if ((Test-Path $npmPath) -and ($env:PATH -notlike "*$npmPath*")) {
        $env:PATH = "$npmPath;$env:PATH"
    }
} else {
    $bunPath = Join-Path $HOME ".bun" "bin"
    if ((Test-Path $bunPath) -and ($env:PATH -notlike "*$bunPath*")) {
        $env:PATH = "$bunPath`:$env:PATH"
    }
}

Write-Host ""

# === Step 2: Install the ws profile ===

Write-Host "  Step 2: Installing OpenCode profile..." -ForegroundColor Yellow

$ConfigDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    Join-Path $env:USERPROFILE ".config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
}
$ProfileDest = Join-Path $ConfigDir "opencode" "profiles" "ws"
$ProfileSource = Join-Path $ScriptDir "profile"

if (Test-Path $ProfileSource) {
    if (Test-Path $ProfileDest) {
        Write-Host "  [!]  Profile 'ws' already exists at: $ProfileDest" -ForegroundColor Yellow
        $overwrite = Read-Host "  Overwrite? (y/N)"
        if ($overwrite -eq "y" -or $overwrite -eq "Y") {
            Remove-Item $ProfileDest -Recurse -Force
            Copy-Item $ProfileSource $ProfileDest -Recurse -Force
            Write-Host "  [OK] Profile overwritten" -ForegroundColor Green
        } else {
            Write-Host "  [..] Keeping existing profile" -ForegroundColor Gray
        }
    } else {
        $ProfileParent = Split-Path $ProfileDest -Parent
        if (-not (Test-Path $ProfileParent)) {
            New-Item -ItemType Directory -Path $ProfileParent -Force | Out-Null
        }
        Copy-Item $ProfileSource $ProfileDest -Recurse -Force
        Write-Host "  [OK] Profile installed" -ForegroundColor Green
    }

    # Install plugin dependencies (bun is now available from Step 1)
    Write-Host ""
    Write-Host "  Installing plugin dependencies..." -ForegroundColor Gray
    Push-Location $ProfileDest
    try {
        & bun install 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [!]  bun install failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
            Write-Host "       Run manually: cd `"$ProfileDest`" && bun install" -ForegroundColor Gray
        } else {
            Write-Host "  [OK] Dependencies installed" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }

    Push-Location $ProfileDest
    try {
        & ocx install 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [!]  ocx install failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
            Write-Host "       Run manually: cd `"$ProfileDest`" && ocx install" -ForegroundColor Gray
        } else {
            Write-Host "  [OK] OCX plugins installed" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [X]  Profile not found in package. Contact the sender." -ForegroundColor Red
}

Write-Host ""

# === Step 3: Run workspace setup ===

Write-Host "  Step 3: Workspace setup..." -ForegroundColor Yellow
$SetupWorkspace = Join-Path $ScriptDir "setup-workspace.ps1"
if (Test-Path $SetupWorkspace) {
    & $SetupWorkspace -SkipDeps -Force
} else {
    Write-Host "  [X]  setup-workspace.ps1 not found" -ForegroundColor Red
}
'@

Set-Content -LiteralPath (Join-Path $StagingDir "bootstrap.ps1") -Value $Bootstrap -NoNewline
Write-Host "[OK] bootstrap.ps1 created" -ForegroundColor Green

# 4. Create a QUICKSTART.txt
$Quickstart = @'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop or Downloads)

2. Open PowerShell in the extracted folder:
   - Right-click in the folder -> "Open in Terminal"
   - Or: Open PowerShell, cd to the folder

3. Run:
   .\bootstrap.ps1

4. Follow the prompts. It will (in order):
   a. Fix PowerShell execution policy if needed (Windows)
   b. Install any missing tools (git, node, bun, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   c. Install the OpenCode "ws" profile (agents, skills, plugins)
   d. Ask for your project name and repo paths
   e. Set up each repo with workflow scripts and Backlog.md
   f. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with -Force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, bun, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
=========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF BUN WAS JUST INSTALLED AND THINGS FAIL?
=================================================
On Windows, freshly installed bun may not be on PATH in the
current session. If you see errors about bun/ocx not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: .\bootstrap.ps1

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "scripts can't run" -> The bootstrap fixes this automatically on Windows
- "bun not found after install" -> Restart terminal, re-run bootstrap.ps1
- "zellij not found" -> See https://zellij.dev/documentation/installation
- Other issues -> Read README.md troubleshooting section
'@

Set-Content -LiteralPath (Join-Path $StagingDir "QUICKSTART.txt") -Value $Quickstart -NoNewline
Write-Host "[OK] QUICKSTART.txt created" -ForegroundColor Green

# 5. Zip it
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$StagingDir\*" -DestinationPath $ZipPath -Force
Remove-Item $StagingDir -Recurse -Force

$size = [math]::Round((Get-Item $ZipPath).Length / 1KB)
Write-Host ""
Write-Host "[OK] Package created: $ZipPath ($size KB)" -ForegroundColor Green
Write-Host "     Send this zip to your colleague." -ForegroundColor Cyan
Write-Host "     They extract it and run: .\bootstrap.ps1" -ForegroundColor Cyan
Write-Host ""

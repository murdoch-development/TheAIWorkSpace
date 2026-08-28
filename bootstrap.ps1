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
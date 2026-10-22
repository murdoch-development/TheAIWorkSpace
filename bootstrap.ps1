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

# Refresh PATH for current session (npm may have just been installed)
if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    $nodejsPath = Join-Path $env:ProgramFiles "nodejs"
    if ((Test-Path $nodejsPath) -and ($env:PATH -notlike "*$nodejsPath*")) {
        $env:PATH = "$nodejsPath;$env:PATH"
    }
    $npmPath = Join-Path $env:APPDATA "npm"
    if ((Test-Path $npmPath) -and ($env:PATH -notlike "*$npmPath*")) {
        $env:PATH = "$npmPath;$env:PATH"
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

    # Install plugin dependencies (npm is now available from Step 1)
    Write-Host ""
    Write-Host "  Installing plugin dependencies..." -ForegroundColor Gray
    Push-Location $ProfileDest
    try {
        & npm install 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [!]  npm install failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
            Write-Host "       Run manually: cd `"$ProfileDest`" && npm install" -ForegroundColor Gray
        } else {
            Write-Host "  [OK] Dependencies installed" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }

} else {
    Write-Host "  [X]  Profile not found in package. Contact the sender." -ForegroundColor Red
}

# === Step 2b: Install Zellij scripts and config ===

Write-Host ""
Write-Host "  Installing Zellij helper scripts and config..." -ForegroundColor Yellow

$ZellijConfigDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
    Join-Path $env:APPDATA "Zellij" "config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    $base = if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
    Join-Path $base "zellij"
}
$ZellijScriptsDir = Join-Path $ZellijConfigDir "scripts"

if (-not (Test-Path $ZellijScriptsDir)) {
    New-Item -ItemType Directory -Path $ZellijScriptsDir -Force | Out-Null
}

$NewBuildAgentSrc = Join-Path $ScriptDir "new-build-agent.ps1"
if (Test-Path $NewBuildAgentSrc) {
    $dest = Join-Path $ZellijScriptsDir "new-build-agent.ps1"
    Copy-Item $NewBuildAgentSrc $dest -Force
    Write-Host "  [OK] new-build-agent.ps1" -ForegroundColor Green
} else {
    Write-Host "  [!]  new-build-agent.ps1 not found (skipping)" -ForegroundColor Yellow
}

# Install config-ws.kdl (Zellij config with ws-specific keybinds)
$ConfigWsSrc = Join-Path $ScriptDir "config-ws.kdl"
if (Test-Path $ConfigWsSrc) {
    $dest = Join-Path $ZellijConfigDir "config-ws.kdl"
    Copy-Item $ConfigWsSrc $dest -Force
    Write-Host "  [OK] config-ws.kdl" -ForegroundColor Green
} else {
    Write-Host "  [!]  config-ws.kdl not found (skipping)" -ForegroundColor Yellow
}

# Add Zellij scripts dir to user PATH (so new-build-agent.ps1 is discoverable by keybinds)
$sep = [System.IO.Path]::PathSeparator
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -and $userPath.Split($sep, [StringSplitOptions]::RemoveEmptyEntries) -notcontains $ZellijScriptsDir) {
    $newUserPath = "$ZellijScriptsDir$sep$userPath"
    [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
    Write-Host "  [OK] Added $ZellijScriptsDir to user PATH" -ForegroundColor Green
} elseif (-not $userPath) {
    [Environment]::SetEnvironmentVariable("PATH", $ZellijScriptsDir, "User")
    Write-Host "  [OK] Added $ZellijScriptsDir to user PATH" -ForegroundColor Green
} else {
    Write-Host "  [..] $ZellijScriptsDir already on PATH" -ForegroundColor Gray
}
# Update current session PATH too
if ($env:PATH -notlike "*$ZellijScriptsDir*") {
    $env:PATH = "$ZellijScriptsDir$sep$env:PATH"
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
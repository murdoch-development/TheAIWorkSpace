<#
.SYNOPSIS
    Installs all dependencies for the multi-agent OpenCode workspace.

.DESCRIPTION
    Checks and installs:
    - Git (winget/brew/apt)
    - Node.js LTS (winget/brew/apt)
    - Zellij (winget/brew/cargo)
    - Backlog.md (npm global)
    - OCX (npm global)
    - OpenCode (npm global)

    Cross-platform: Windows (winget), macOS (brew), Linux (apt/curl).
    Safe to re-run: skips already-installed tools.

.PARAMETER SkipOptional
    Skip optional tools (Zellij). Core tools (git, node, backlog, ocx, opencode) always install.

.EXAMPLE
    .\install-deps.ps1
    .\install-deps.ps1 -SkipOptional
#>
param(
    [switch]$SkipOptional
)

$ErrorActionPreference = "Stop"

# === OS Detection ===

$IsWin = $false
$IsMac = $false
$IsLin = $false

if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsWin = $IsWindows
    $IsMac = $IsMacOS
    $IsLin = $IsLinux
} else {
    $IsWin = $true
}

$OS = if ($IsWin) { "Windows" } elseif ($IsMac) { "macOS" } else { "Linux" }

# === Helpers ===

function Test-Cmd {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Install-WithWinget {
    param([string]$PackageId)
    Write-Host "      winget install $PackageId" -ForegroundColor DarkGray
    winget install $PackageId --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object {
        if ($_ -is [string]) { Write-Host "      $_" -ForegroundColor DarkGray }
    }
}

function Install-WithBrew {
    param([string]$Package)
    Write-Host "      brew install $Package" -ForegroundColor DarkGray
    brew install $Package 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
}

function Install-WithApt {
    param([string]$Package)
    Write-Host "      sudo apt install -y $Package" -ForegroundColor DarkGray
    sudo apt install -y $Package 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
}

# === Start ===

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "     Multi-Agent Workspace - Dependency Setup " -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  OS: $OS" -ForegroundColor Gray
Write-Host ""

# === 1. Git ===

Write-Host "  [1/6] Git" -ForegroundColor White
if (Test-Cmd "git") {
    $gitVer = git --version 2>&1
    Write-Host "       [OK] $gitVer" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing Git..." -ForegroundColor Yellow
    if ($IsWin) { Install-WithWinget "Git.Git" }
    elseif ($IsMac) { Install-WithBrew "git" }
    else { Install-WithApt "git" }
    if (Test-Cmd "git") {
        Write-Host "       [OK] Git installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  Git install failed. Install manually." -ForegroundColor Red
    }
}

# === 2. Node.js ===

Write-Host "  [2/6] Node.js (LTS)" -ForegroundColor White
if (Test-Cmd "node") {
    $nodeVer = node --version 2>&1
    Write-Host "       [OK] Node.js $nodeVer" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing Node.js LTS..." -ForegroundColor Yellow
    if ($IsWin) { Install-WithWinget "OpenJS.NodeJS.LTS" }
    elseif ($IsMac) { Install-WithBrew "node" }
    else { Install-WithApt "nodejs" }
    if (Test-Cmd "node") {
        Write-Host "       [OK] Node.js installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  Node.js install failed. Install manually." -ForegroundColor Red
    }
}

# Refresh PATH for current session (node/npm may have just been installed)
if ($IsWin) {
    $nodejsPath = Join-Path $env:ProgramFiles "nodejs"
    if ((Test-Path $nodejsPath) -and ($env:PATH -notlike "*$nodejsPath*")) {
        $env:PATH = "$nodejsPath;$env:PATH"
    }
    $npmGlobalPath = Join-Path $env:APPDATA "npm"
    if ((Test-Path $npmGlobalPath) -and ($env:PATH -notlike "*$npmGlobalPath*")) {
        $env:PATH = "$npmGlobalPath;$env:PATH"
    }
}

# === 3. Zellij (optional) ===

if ($SkipOptional) {
    Write-Host "  [3/6] Zellij (skipped -SkipOptional)" -ForegroundColor Gray
} else {
    Write-Host "  [3/6] Zellij" -ForegroundColor White
    if (Test-Cmd "zellij") {
        $zellijVer = zellij --version 2>&1
        Write-Host "       [OK] $zellijVer" -ForegroundColor Green
    } else {
        Write-Host "       [..] Installing Zellij..." -ForegroundColor Yellow
        if ($IsWin) { Install-WithWinget "zellij.zellij" }
        elseif ($IsMac) { Install-WithBrew "zellij" }
        else {
            Write-Host "      cargo install zellij" -ForegroundColor DarkGray
            if (Test-Cmd "cargo") {
                cargo install zellij 2>&1 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "       [X]  Rust/Cargo not found. Install Rust first:" -ForegroundColor Red
                Write-Host "            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" -ForegroundColor DarkGray
            }
        }
        if (Test-Cmd "zellij") {
            Write-Host "       [OK] Zellij installed" -ForegroundColor Green
        } else {
            Write-Host "       [!]  Zellij install failed (optional). Install manually if needed." -ForegroundColor Yellow
        }
    }
}

# === 4. Backlog.md ===

Write-Host "  [4/6] Backlog.md" -ForegroundColor White
if (Test-Cmd "backlog") {
    Write-Host "       [OK] Backlog.md CLI" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing Backlog.md (npm global)..." -ForegroundColor Yellow
    Write-Host "      npm install -g backlog.md@1" -ForegroundColor DarkGray
    npm install -g backlog.md@1 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
    if (Test-Cmd "backlog") {
        Write-Host "       [OK] Backlog.md installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  Backlog.md install failed. Run: npm install -g backlog.md@1" -ForegroundColor Red
    }
}

# === 5. OCX ===

Write-Host "  [5/6] OCX (OpenCode profile manager)" -ForegroundColor White
if (Test-Cmd "ocx") {
    Write-Host "       [OK] OCX" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing OCX (npm global)..." -ForegroundColor Yellow
    Write-Host "      npm install -g ocx@2.0.15" -ForegroundColor DarkGray
    & npm install -g ocx@2.0.15 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
    if (Test-Cmd "ocx") {
        Write-Host "       [OK] OCX installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  OCX install failed. Run: npm install -g ocx@2.0.15" -ForegroundColor Red
        Write-Host "            You may need to restart your terminal first." -ForegroundColor DarkGray
    }
}

# === 6. OpenCode ===

Write-Host "  [6/6] OpenCode" -ForegroundColor White
if (Test-Cmd "opencode") {
    Write-Host "       [OK] OpenCode" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing OpenCode..." -ForegroundColor Yellow
    Write-Host "      npm install -g opencode-ai@1" -ForegroundColor DarkGray
    & npm install -g opencode-ai@1 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
    if (Test-Cmd "opencode") {
        Write-Host "       [OK] OpenCode installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  OpenCode install failed. Run: npm install -g opencode-ai@1" -ForegroundColor Red
        Write-Host "            You may need to restart your terminal first." -ForegroundColor DarkGray
    }
}

# === Summary ===

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
$allOK = $true
foreach ($cmd in @("git", "node", "backlog", "ocx", "opencode")) {
    if (Test-Cmd $cmd) {
        Write-Host "  [OK] $cmd" -ForegroundColor Green
    } else {
        Write-Host "  [X]  $cmd" -ForegroundColor Red
        $allOK = $false
    }
}
if (-not $SkipOptional) {
    if (Test-Cmd "zellij") {
        Write-Host "  [OK] zellij (optional)" -ForegroundColor Green
    } else {
        Write-Host "  [!]  zellij (optional, not installed)" -ForegroundColor Yellow
    }
}

Write-Host ""
if ($allOK) {
    Write-Host "  All core dependencies installed!" -ForegroundColor Green
} else {
    Write-Host "  Some dependencies failed. Install manually and re-run." -ForegroundColor Yellow
}
Write-Host ""

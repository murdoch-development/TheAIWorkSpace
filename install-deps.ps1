<#
.SYNOPSIS
    Installs all dependencies for the multi-agent OpenCode workspace.

.DESCRIPTION
    Checks and installs:
    - Git (winget/brew/apt)
    - Node.js LTS (winget/brew/apt)
    - Bun ( PowerShell/curl)
    - Zellij (winget/brew/cargo)
    - Backlog.md (npm global)
    - OCX (bun global)
    - OpenCode (bun global)

    Cross-platform: Windows (winget), macOS (brew), Linux (apt/curl).
    Safe to re-run: skips already-installed tools.

.PARAMETER SkipOptional
    Skip optional tools (Zellij). Core tools (git, node, bun, backlog, ocx, opencode) always install.

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

function Repair-BunShim {
    # Tests a bun-installed global tool and repairs the broken .exe shim
    # if Bun's shebang parser fails on "#!/usr/bin/env -S bun ..." syntax.
    # The fix: create a .cmd wrapper that calls `bun run <entry-point>` directly,
    # then rename the broken .exe to .exe.bak so the .cmd wins on PATH.
    param([string]$ToolName)

    # Only applies to Windows
    if (-not $IsWin) { return $true }

    # 1. Check the tool is on PATH at all
    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }

    # 2. Run it with --version to see if the shim is broken.
    #    Use --version (not -v) because some tools don't support -v.
    $output = & $ToolName --version 2>&1 | Out-String

    # 3. Only repair if we see the specific Bun -S shebang bug signature.
    #    Other errors (unknown option, etc.) mean the tool works — just
    #    doesn't support that flag. The tool is healthy.
    if ($output -notmatch 'interpreter executable|not found in %PATH%') {
        return $true
    }

    # 4. Shim is broken — find the package entry point
    Write-Host "       [!]  $ToolName shim is broken (Bun -S shebang bug). Repairing..." -ForegroundColor Yellow

    $bunBinDir = Join-Path $env:USERPROFILE ".bun" "bin"

    # Search both bun-global and npm-global locations for the package
    $searchDirs = @(
        (Join-Path $env:USERPROFILE ".bun" "install" "global" "node_modules"),
        (Join-Path $env:APPDATA "npm" "node_modules"),
        (Join-Path $env:ProgramFiles "nodejs" "node_modules")
    )

    # Also check nvm4w if present (NVM_HOME may not be set)
    $nvmNode = $null
    if ($env:NVM_HOME) {
        $nvmNode = Join-Path $env:NVM_HOME "nodejs" "node_modules"
    }
    if (-not $nvmNode -or -not (Test-Path $nvmNode)) {
        # Try common nvm4w locations
        foreach ($candidate in @("C:\nvm4w\nodejs\node_modules", "C:\nvm\nodejs\node_modules", "$env:ProgramFiles\nvm4w\nodejs\node_modules")) {
            if (Test-Path $candidate) { $nvmNode = $candidate; break }
        }
    }
    if ($nvmNode -and (Test-Path $nvmNode)) { $searchDirs += $nvmNode }

    # Also check where the tool's resolved command lives — its parent's node_modules
    if ($cmd.Source) {
        $cmdDir = Split-Path $cmd.Source -Parent
        $siblingModules = Join-Path $cmdDir "node_modules"
        if (Test-Path $siblingModules) { $searchDirs += $siblingModules }
    }

    $pkgDir = $null
    foreach ($base in $searchDirs) {
        $candidate = Join-Path $base $ToolName
        if (Test-Path $candidate) { $pkgDir = $candidate; break }
    }

    if (-not $pkgDir) {
        Write-Host "       [X]  Cannot find $ToolName package dir in any global location." -ForegroundColor Red
        Write-Host "            Searched:" -ForegroundColor DarkGray
        foreach ($s in $searchDirs) { Write-Host "              $s" -ForegroundColor DarkGray }
        return $false
    }

    # Read package.json to find the bin entry point
    $pkgJsonPath = Join-Path $pkgDir "package.json"
    if (-not (Test-Path $pkgJsonPath)) {
        Write-Host "       [X]  Cannot find $ToolName package.json at $pkgJsonPath" -ForegroundColor Red
        return $false
    }

    $pkg = Get-Content -Raw $pkgJsonPath | ConvertFrom-Json
    $entryScript = $null
    if ($pkg.bin -is [string]) {
        $entryScript = $pkg.bin
    } elseif ($pkg.bin.PSObject.Properties[$ToolName]) {
        $entryScript = $pkg.bin.$ToolName
    } else {
        # Fallback: look for common entry points
        $candidates = @("dist/index.js", "dist/cli.js", "bin/index.js", "index.js")
        foreach ($c in $candidates) {
            if (Test-Path (Join-Path $pkgDir $c)) { $entryScript = $c; break }
        }
    }

    if (-not $entryScript) {
        Write-Host "       [X]  Cannot find $ToolName entry point in package.json." -ForegroundColor Red
        return $false
    }

    $entryPath = Join-Path $pkgDir $entryScript
    if (-not (Test-Path $entryPath)) {
        Write-Host "       [X]  Entry point not found: $entryPath" -ForegroundColor Red
        return $false
    }

    # 5. Find where the broken shim lives and create the .cmd wrapper there.
    #    Prefer the bun bin dir; fall back to the resolved command's source dir.
    $wrapperDir = $bunBinDir
    if (-not (Test-Path $wrapperDir)) {
        $wrapperDir = Split-Path $cmd.Source -Parent
    }

    $cmdWrapperPath = Join-Path $wrapperDir "$ToolName.cmd"
    $wrapperContent = "@echo off`r`nbun run `"$entryPath`" %*`r`n"
    Set-Content -LiteralPath $cmdWrapperPath -Value $wrapperContent -NoNewline -Encoding ASCII

    # 6. Rename the broken .exe to .exe.bak (if it exists)
    $exePath = Join-Path $wrapperDir "$ToolName.exe"
    $bakPath = Join-Path $wrapperDir "$ToolName.exe.bak"
    if (Test-Path $exePath) {
        if (Test-Path $bakPath) { Remove-Item $bakPath -Force }
        Rename-Item $exePath $bakPath
    }

    # 7. Re-test
    $output = & $ToolName --version 2>&1 | Out-String
    if ($output -notmatch 'interpreter executable|not found in %PATH%') {
        Write-Host "       [OK] $ToolName shim repaired" -ForegroundColor Green
        return $true
    } else {
        Write-Host "       [X]  $ToolName repair did not fix the issue." -ForegroundColor Red
        Write-Host "            Manual: create a .cmd wrapper calling bun run on the entry point." -ForegroundColor DarkGray
        return $false
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

Write-Host "  [1/7] Git" -ForegroundColor White
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

Write-Host "  [2/7] Node.js (LTS)" -ForegroundColor White
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

# === 3. Bun ===

Write-Host "  [3/7] Bun" -ForegroundColor White
if (Test-Cmd "bun") {
    $bunVer = bun --version 2>&1
    Write-Host "       [OK] Bun $bunVer" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing Bun..." -ForegroundColor Yellow
    if ($IsWin) {
        Write-Host "      powershell -c `"irm bun.sh/install.ps1 | iex`"" -ForegroundColor DarkGray
        & powershell -c "irm bun.sh/install.ps1 | iex" 2>&1 | ForEach-Object {
            Write-Host "      $_" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "      curl -fsSL https://bun.sh/install | bash" -ForegroundColor DarkGray
        curl -fsSL https://bun.sh/install | bash 2>&1 | ForEach-Object {
            Write-Host "      $_" -ForegroundColor DarkGray
        }
    }
    # Refresh PATH for current session
    if ($IsWin) {
        $bunPath = Join-Path $env:USERPROFILE ".bun" "bin"
        if (Test-Path $bunPath) { $env:PATH = "$bunPath;$env:PATH" }
    } else {
        $bunPath = Join-Path $HOME ".bun" "bin"
        if (Test-Path $bunPath) { $env:PATH = "$bunPath`:$env:PATH" }
    }
    if (Test-Cmd "bun") {
        Write-Host "       [OK] Bun installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  Bun install failed. Install manually:" -ForegroundColor Red
        Write-Host "            Windows: irm bun.sh/install.ps1 | iex" -ForegroundColor DarkGray
        Write-Host "            Unix:    curl -fsSL https://bun.sh/install | bash" -ForegroundColor DarkGray
        Write-Host "            Then restart your terminal." -ForegroundColor DarkGray
    }
}

# === 4. Zellij (optional) ===

if ($SkipOptional) {
    Write-Host "  [4/7] Zellij (skipped -SkipOptional)" -ForegroundColor Gray
} else {
    Write-Host "  [4/7] Zellij" -ForegroundColor White
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

# === 5. Backlog.md ===

Write-Host "  [5/7] Backlog.md" -ForegroundColor White
if (Test-Cmd "backlog") {
    Write-Host "       [OK] Backlog.md CLI" -ForegroundColor Green
} else {
    Write-Host "       [..] Installing Backlog.md (npm global)..." -ForegroundColor Yellow
    Write-Host "      npm install -g backlog.md" -ForegroundColor DarkGray
    npm install -g backlog.md 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
    if (Test-Cmd "backlog") {
        Write-Host "       [OK] Backlog.md installed" -ForegroundColor Green
    } else {
        Write-Host "       [X]  Backlog.md install failed. Run: npm install -g backlog.md" -ForegroundColor Red
    }
}

# === 6. OCX ===

Write-Host "  [6/7] OCX (OpenCode profile manager)" -ForegroundColor White
if (Test-Cmd "ocx") {
    if (Repair-BunShim "ocx") {
        Write-Host "       [OK] OCX" -ForegroundColor Green
    } else {
        Write-Host "       [X]  OCX is on PATH but broken. See errors above." -ForegroundColor Red
    }
} else {
    Write-Host "       [..] Installing OCX (bun global)..." -ForegroundColor Yellow
    Write-Host "      bun install -g ocx" -ForegroundColor DarkGray
    & bun install -g ocx 2>&1 | ForEach-Object {
        Write-Host "      $_" -ForegroundColor DarkGray
    }
    if (Test-Cmd "ocx") {
        if (Repair-BunShim "ocx") {
            Write-Host "       [OK] OCX installed" -ForegroundColor Green
        } else {
            Write-Host "       [X]  OCX installed but shim is broken. See errors above." -ForegroundColor Red
        }
    } else {
        Write-Host "       [X]  OCX install failed. Run: bun install -g ocx" -ForegroundColor Red
        Write-Host "            You may need to restart your terminal first." -ForegroundColor DarkGray
    }
}

# === 7. OpenCode ===

Write-Host "  [7/7] OpenCode" -ForegroundColor White
if (Test-Cmd "opencode") {
    if (Repair-BunShim "opencode") {
        Write-Host "       [OK] OpenCode" -ForegroundColor Green
    } else {
        Write-Host "       [X]  OpenCode is on PATH but broken. See errors above." -ForegroundColor Red
    }
} else {
    Write-Host "       [..] Installing OpenCode..." -ForegroundColor Yellow
    if (Test-Cmd "bun") {
        Write-Host "      bun install -g opencode-ai" -ForegroundColor DarkGray
        & bun install -g opencode-ai 2>&1 | ForEach-Object {
            Write-Host "      $_" -ForegroundColor DarkGray
        }
        if (Test-Cmd "opencode") {
            if (Repair-BunShim "opencode") {
                Write-Host "       [OK] OpenCode installed" -ForegroundColor Green
            } else {
                Write-Host "       [X]  OpenCode installed but shim is broken. See errors above." -ForegroundColor Red
            }
        } else {
            Write-Host "       [X]  OpenCode install failed. Run: bun install -g opencode-ai" -ForegroundColor Red
            Write-Host "            You may need to restart your terminal first." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "       [X]  Bun not available. Install Bun first, then run:" -ForegroundColor Red
        Write-Host "            bun install -g opencode-ai" -ForegroundColor DarkGray
    }
}

# === Summary ===

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
$allOK = $true
foreach ($cmd in @("git", "node", "bun", "backlog", "ocx", "opencode")) {
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

if ($IsWin) {
    Write-Host ""
    Write-Host "  NOTE: If you just installed Bun, restart your terminal" -ForegroundColor Gray
    Write-Host "  for PATH changes to take effect, then re-run this script." -ForegroundColor Gray
}
Write-Host ""

<#
.SYNOPSIS
    Uninstalls The AI Workspace - undoes everything bootstrap.ps1 did.

.DESCRIPTION
    Phase 1: Infrastructure (undo bootstrap.ps1)
      - Remove ws profile (~/.config/opencode/profiles/ws/)
      - Remove Zellij scripts (new-build-agent.ps1)
      - Remove config-ws.kdl from Zellij config dir
      - Remove Zellij scripts dir from user PATH
      - Uninstall ocx (npm uninstall -g ocx)
      - Uninstall opencode-ai (npm uninstall -g opencode-ai)
      - Uninstall backlog.md (npm uninstall -g backlog.md)
      - Uninstall bun (if installed)

    Phase 2: Workspace artifacts (undo setup-workspace.ps1)
      - Remove generated Zellij layouts + configs
      - Remove repo workflow files (scripts/, backlog/, SOFTWARE_ENGINEERING_PRINCIPLES.md)

    Each step prompts y/n. Cross-platform.

.EXAMPLE
    .\uninstall.ps1
#>

$ErrorActionPreference = "Stop"

# === OS Detection ===

$IsWin = $false
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsWin = $IsWindows
} else {
    $IsWin = $true
}

$OS = if ($IsWin) { "Windows" } else { "macOS/Linux" }

# === Helpers ===

function Ask-YesNo {
    param([string]$Prompt)
    Write-Host "  $Prompt (y/N): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    return $response -eq "y" -or $response -eq "Y"
}

function Remove-Safely {
    param([string]$Path)
    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Path)) {
            Write-Host "       [OK] Removed: $Path" -ForegroundColor Green
        } else {
            Write-Host "       [!]  Could not fully remove: $Path" -ForegroundColor Yellow
        }
    } else {
        Write-Host "       [..] Not found: $Path" -ForegroundColor DarkGray
    }
}

# === Banner ===

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "     The AI Workspace - Uninstall              " -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  OS: $OS" -ForegroundColor Gray
Write-Host ""
Write-Host "  Each step will ask y/n. Answer N to skip." -ForegroundColor Gray
Write-Host ""

# === Resolve paths ===

$ConfigDir = if ($IsWin) {
    Join-Path $env:USERPROFILE ".config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
}

$ProfileDest = Join-Path $ConfigDir "opencode" "profiles" "ws"

$ZellijConfigDir = if ($IsWin) {
    Join-Path $env:APPDATA "Zellij" "config"
} else {
    $xdg = $env:XDG_CONFIG_HOME
    $base = if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
    Join-Path $base "zellij"
}

$ZellijScriptsDir = Join-Path $ZellijConfigDir "scripts"
$ZellijLayoutsDir = Join-Path $ZellijConfigDir "layouts"

# === Phase 1: Infrastructure ===

Write-Host "  -- Phase 1: Infrastructure ----------------------" -ForegroundColor Yellow
Write-Host ""

# 1. ws profile
if (Ask-YesNo "Remove ws profile? ($ProfileDest)") {
    Remove-Safely $ProfileDest
}
Write-Host ""

# 2. Zellij scripts - new-build-agent.ps1
if (Ask-YesNo "Remove Zellij helper script? (new-build-agent.ps1)") {
    Remove-Safely (Join-Path $ZellijScriptsDir "new-build-agent.ps1")
    # Remove scripts dir if now empty
    if (Test-Path $ZellijScriptsDir) {
        $remaining = Get-ChildItem $ZellijScriptsDir -ErrorAction SilentlyContinue
        if (-not $remaining) {
            if (Ask-YesNo "  Scripts dir is now empty. Remove it? ($ZellijScriptsDir)") {
                Remove-Safely $ZellijScriptsDir
            }
        }
    }
}
Write-Host ""

# 3. config-ws.kdl
if (Ask-YesNo "Remove config-ws.kdl from Zellij config?") {
    Remove-Safely (Join-Path $ZellijConfigDir "config-ws.kdl")
}
Write-Host ""

# 4. Remove Zellij scripts dir from user PATH
if ($IsWin) {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -and $userPath.Split([System.IO.Path]::PathSeparator, [StringSplitOptions]::RemoveEmptyEntries) -contains $ZellijScriptsDir) {
        if (Ask-YesNo "Remove Zellij scripts dir from user PATH? ($ZellijScriptsDir)") {
            $sep = [System.IO.Path]::PathSeparator
            $newPath = ($userPath.Split($sep, [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -ne $ZellijScriptsDir }) -join $sep
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Host "       [OK] Removed from user PATH" -ForegroundColor Green
        }
    } else {
        Write-Host "  [..] Zellij scripts dir not on user PATH (skipping)" -ForegroundColor Gray
    }
    Write-Host ""
}

# 5. Uninstall ocx
if (Ask-YesNo "Uninstall OCX? (npm uninstall -g ocx)") {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        & npm uninstall -g ocx 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        Write-Host "       [OK] OCX uninstalled" -ForegroundColor Green
    } else {
        Write-Host "       [X]  npm not found. Run manually: npm uninstall -g ocx" -ForegroundColor Red
    }
}
Write-Host ""

# 6. Uninstall opencode-ai
if (Ask-YesNo "Uninstall OpenCode? (npm uninstall -g opencode-ai)") {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        & npm uninstall -g opencode-ai 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        Write-Host "       [OK] OpenCode uninstalled" -ForegroundColor Green
    } else {
        Write-Host "       [X]  npm not found. Run manually: npm uninstall -g opencode-ai" -ForegroundColor Red
    }
}
Write-Host ""

# 7. Uninstall backlog.md
if (Ask-YesNo "Uninstall Backlog.md? (npm uninstall -g backlog.md)") {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        & npm uninstall -g backlog.md 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        Write-Host "       [OK] Backlog.md uninstalled" -ForegroundColor Green
    } else {
        Write-Host "       [X]  npm not found. Run manually: npm uninstall -g backlog.md" -ForegroundColor Red
    }
}
Write-Host ""

# 8. Uninstall bun (if installed)
$BunDir = if ($IsWin) {
    Join-Path $env:USERPROFILE ".bun"
} else {
    Join-Path $HOME ".bun"
}

if (Test-Path $BunDir) {
    if (Ask-YesNo "Uninstall Bun? (remove $BunDir + PATH entry)") {
        Remove-Safely $BunDir
        if ($IsWin) {
            $bunBin = Join-Path $BunDir "bin"
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -and $userPath.Split([System.IO.Path]::PathSeparator, [StringSplitOptions]::RemoveEmptyEntries) -contains $bunBin) {
                $sep = [System.IO.Path]::PathSeparator
                $newPath = ($userPath.Split($sep, [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -ne $bunBin }) -join $sep
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
                Write-Host "       [OK] Removed Bun from user PATH" -ForegroundColor Green
            }
        }
    }
    Write-Host ""
}

# === Phase 2: Workspace Artifacts ===

Write-Host "  -- Phase 2: Workspace Artifacts ----------------" -ForegroundColor Yellow
Write-Host ""

# 9. Remove generated Zellij layouts and configs
if (Ask-YesNo "Remove generated Zellij layouts and configs?") {
    $foundAny = $false

    # Layouts: *.kdl in layouts dir
    if (Test-Path $ZellijLayoutsDir) {
        $layouts = Get-ChildItem $ZellijLayoutsDir -Filter "*.kdl" -ErrorAction SilentlyContinue
        foreach ($layout in $layouts) {
            $foundAny = $true
            Write-Host "       Layout: $($layout.Name)" -ForegroundColor DarkGray
            Remove-Safely $layout.FullName
        }
    }

    # Configs: config-*.kdl in config dir (but NOT config-ws.kdl, already handled above)
    $configs = Get-ChildItem $ZellijConfigDir -Filter "config-*.kdl" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "config-ws.kdl" }
    foreach ($config in $configs) {
        $foundAny = $true
        Write-Host "       Config: $($config.Name)" -ForegroundColor DarkGray
        Remove-Safely $config.FullName
    }

    if (-not $foundAny) {
        Write-Host "       [..] No generated layouts or configs found" -ForegroundColor Gray
    }
}
Write-Host ""

# 10. Remove repo workflow files
if (Ask-YesNo "Remove repo workflow files? (scripts/, backlog/, SOFTWARE_ENGINEERING_PRINCIPLES.md)") {
    Write-Host ""
    Write-Host "    Enter repo paths to clean (one per line, empty line to finish):" -ForegroundColor White
    $repos = @()
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
        $repos += $repoPath
    }

    foreach ($repo in $repos) {
        Write-Host ""
        Write-Host "    Repo: $repo" -ForegroundColor Cyan

        # scripts/ dir
        $scriptsDir = Join-Path $repo "scripts"
        if (Test-Path $scriptsDir) {
            if (Ask-YesNo "    Remove scripts/ dir?") {
                Remove-Safely $scriptsDir
            }
        } else {
            Write-Host "      [..] scripts/ not found" -ForegroundColor DarkGray
        }

        # backlog/ dir (warn about data)
        $backlogDir = Join-Path $repo "backlog"
        if (Test-Path $backlogDir) {
            Write-Host "    WARNING: backlog/ contains board data and worktrees!" -ForegroundColor Red
            if (Ask-YesNo "    Remove backlog/ dir?") {
                Remove-Safely $backlogDir
            }
        } else {
            Write-Host "      [..] backlog/ not found" -ForegroundColor DarkGray
        }

        # SOFTWARE_ENGINEERING_PRINCIPLES.md
        $principlesFile = Join-Path $repo "SOFTWARE_ENGINEERING_PRINCIPLES.md"
        if (Test-Path $principlesFile) {
            if (Ask-YesNo "    Remove SOFTWARE_ENGINEERING_PRINCIPLES.md?") {
                Remove-Safely $principlesFile
            }
        } else {
            Write-Host "      [..] SOFTWARE_ENGINEERING_PRINCIPLES.md not found" -ForegroundColor DarkGray
        }

        # Remove backlog/worktrees/ from .gitignore
        $gitignore = Join-Path $repo ".gitignore"
        if (Test-Path $gitignore) {
            $lines = Get-Content -LiteralPath $gitignore
            $filtered = $lines | Where-Object { $_ -notmatch '^\s*backlog/worktrees/\s*$' }
            if ($filtered.Count -ne $lines.Count) {
                if (Ask-YesNo "    Remove backlog/worktrees/ from .gitignore?") {
                    Set-Content -LiteralPath $gitignore -Value $filtered
                    Write-Host "       [OK] Removed backlog/worktrees/ from .gitignore" -ForegroundColor Green
                }
            }
        }
    }
}
Write-Host ""

# === Summary ===

Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Uninstall complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note: Git, Node.js, and Zellij were NOT uninstalled" -ForegroundColor Gray
Write-Host "  (they may be used by other projects)." -ForegroundColor Gray
Write-Host "  To remove them manually:" -ForegroundColor Gray
if ($IsWin) {
    Write-Host "    Git:    winget uninstall Git.Git" -ForegroundColor DarkGray
    Write-Host "    Node:   winget uninstall OpenJS.NodeJS.LTS" -ForegroundColor DarkGray
    Write-Host "    Zellij: winget uninstall zellij.zellij" -ForegroundColor DarkGray
} else {
    Write-Host "    Git:    brew uninstall git / sudo apt remove git" -ForegroundColor DarkGray
    Write-Host "    Node:   brew uninstall node / sudo apt remove nodejs" -ForegroundColor DarkGray
    Write-Host "    Zellij: brew uninstall zellij / cargo uninstall zellij" -ForegroundColor DarkGray
}
Write-Host ""

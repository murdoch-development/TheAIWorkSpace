<#
.SYNOPSIS
    Duplicates the focused Zellij tab — same cwd, same agent, incremented name.

.DESCRIPTION
    Launched from a Zellij keybind via the Run action (floating pane, close-on-exit).
    The floating pane runs in the SOURCE tab, so the source tab stays focused.
    This script:
    1. Reads the source tab's name + position (current-tab-info)
    2. Reads the source pane's cwd (list-panes, non-plugin non-focused pane)
    3. Computes "BaseName.N" where N = max existing suffix + 1
    4. Creates a new tab with --cwd, --name, and the same agent command (new-tab)
    5. Moves the new tab to be immediately right of the source (move-tab -t)

    Agent is derived from the source tab name prefix:
      Build  -> ocx oc -p ws --agent Build-WS
      Plan   -> ocx oc -p ws --agent Plan-WS
      Merge  -> ocx oc -p ws --agent Merger-WS
      Board  -> backlog board
      Shell  -> (plain shell, no command)

.EXAMPLE
    .\new-build-agent.ps1
#>
param()

$ErrorActionPreference = "Stop"

$IsWin = $false
if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWin = $IsWindows } else { $IsWin = $true }

$logFile = Join-Path ([System.IO.Path]::GetTempPath()) "new-build-agent-debug.log"
function Log([string]$msg) {
    # $ts = Get-Date -Format "HH:mm:ss.fff"
    # "[$ts] $msg" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Log "=== new-build-agent.ps1 START ==="
Log "ZELLIJ_SESSION_NAME = $env:ZELLIJ_SESSION_NAME"
Log "PWD = $(Get-Location)"
Log "PATH first 200 = $($env:PATH.Substring(0, [Math]::Min(200, $env:PATH.Length)))"

try {
    # Step 1: Get source tab info (Run opened a floating pane in the focused tab)
    Log "Step 1: current-tab-info..."
    $sourceTabRaw = (zellij action current-tab-info -j 2>&1) -join "`n"
    Log "  raw = $sourceTabRaw"
    $sourceTabInfo = $sourceTabRaw | ConvertFrom-Json
    $sourceName = $sourceTabInfo.name
    $sourcePos = [int]$sourceTabInfo.position
    Log "  name = $sourceName"
    Log "  position = $sourcePos"

    # Step 2: Get all panes — find source cwd + build tab name list
    Log "Step 2: list-panes..."
    $panesJson = (zellij action list-panes -j -a -c -t -s 2>&1) -join "`n"
    Log "  raw length = $($panesJson.Length)"
    $panes = $panesJson | ConvertFrom-Json
    Log "  pane count = $($panes.Count)"

    # Debug: dump all non-plugin panes at source position
    $debugPanes = $panes | Where-Object { -not $_.is_plugin -and [int]$_.tab_position -eq $sourcePos }
    Log "  non-plugin panes at pos $sourcePos : $($debugPanes.Count)"
    foreach ($dp in $debugPanes) {
        Log "    pane: is_focused=$($dp.is_focused) is_floating=$($dp.is_floating) pane_cwd=$($dp.pane_cwd) pane_command=$($dp.pane_command) title=$($dp.title)"
    }

    # Source pane cwd: non-plugin, NOT floating (our Run pane is floating) at source position
    $sourcePanes = $panes | Where-Object {
        -not $_.is_plugin -and -not $_.is_floating -and [int]$_.tab_position -eq $sourcePos
    }
    Log "  sourcePanes count = @($($sourcePanes.Count))"
    $sourceCwd = ($sourcePanes | Select-Object -First 1).pane_cwd
    Log "  sourceCwd = $sourceCwd"

    # Step 3: Compute BaseName.N
    if ($sourceName -match '^(.+)\.\d+$') {
        $baseName = $Matches[1]
    } else {
        $baseName = $sourceName
    }
    Log "Step 3: baseName = $baseName"

    # Build tab list from panes (deduplicate by position)
    $seen = @{}
    $tabNames = @()
    foreach ($p in ($panes | Where-Object { -not $_.is_plugin } | Sort-Object tab_position)) {
        if (-not $seen.ContainsKey($p.tab_position)) {
            $seen[$p.tab_position] = $true
            $tabNames += $p.tab_name
        }
    }
    Log "  tabNames = $($tabNames -join ', ')"

    $maxN = 0
    foreach ($t in $tabNames) {
        if ($t -match "^$([regex]::Escape($baseName))\.(\d+)$") {
            $num = [int]$Matches[1]
            if ($num -gt $maxN) { $maxN = $num }
        }
    }
    $newName = "$baseName.$($maxN + 1)"
    Log "  newName = $newName"

    # Step 4: Derive agent from base name
    $agent = switch -Regex ($baseName) {
        '^Build'  { @("ocx", "oc", "-p", "ws", "--agent", "Build-WS"); break }
        '^Plan'   { @("ocx", "oc", "-p", "ws", "--agent", "Plan-WS"); break }
        '^Merge'  { @("ocx", "oc", "-p", "ws", "--agent", "Merger-WS"); break }
        '^Board'  { @("backlog", "board"); break }
        '^Shell'  { $null; break }
        default   { @("ocx", "oc", "-p", "ws", "--agent", "Build-WS"); break }
    }
    Log "Step 4: agent = $($agent -join ' ')"

    # Step 5: Create new tab with cwd, name, and command
    Log "Step 5: new-tab..."
    if ($agent) {
        if ($IsWin) {
            $cmdArgs = @("action", "new-tab", "--cwd", $sourceCwd, "--name", $newName, "--", "cmd", "/c") + $agent
        } else {
            $cmdArgs = @("action", "new-tab", "--cwd", $sourceCwd, "--name", $newName, "--") + $agent
        }
    } else {
        $cmdArgs = @("action", "new-tab", "--cwd", $sourceCwd, "--name", $newName)
    }
    Log "  cmdArgs = $($cmdArgs -join ' ')"
    $newTabIdRaw = (& zellij @cmdArgs 2>&1) -join "`n"
    Log "  raw = $newTabIdRaw"
    Log "  LASTEXITCODE = $LASTEXITCODE"
    $newTabId = [int]($newTabIdRaw.Trim())
    Log "  newTabId = $newTabId"

    # Step 6: Move new tab to be right after source tab
    Log "Step 6: move-tab..."
    $newPos = $tabNames.Count
    $targetPos = $sourcePos + 1
    $movesNeeded = $newPos - $targetPos
    Log "  newPos = $newPos, targetPos = $targetPos, movesNeeded = $movesNeeded"
    for ($i = 0; $i -lt $movesNeeded; $i++) {
        $null = zellij action move-tab "left" -t $newTabId 2>&1
        Log "  move left #$($i+1) done"
    }
    Log "=== DONE ==="
} catch {
    Log "!!! EXCEPTION !!!"
    Log "  Type: $($_.Exception.GetType().FullName)"
    Log "  Message: $($_.Exception.Message)"
    Log "  ScriptStackTrace: $($_.ScriptStackTrace)"
    Log "  Position: $($_.InvocationInfo.PositionMessage)"
}

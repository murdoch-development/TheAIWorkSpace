<#
.SYNOPSIS
    Generates a Zellij layout for any set of repos using the "ws" OpenCode profile.

.DESCRIPTION
    Creates a .kdl layout file with:
    - Plan tab (Plan-WS agent)
    - One Build tab + one Board tab per repo (indexed: Build 1, Board 1, ...)
    - Shell tab (plain shell)
    - new_tab_template

    Works with any number of repos. Each repo gets its own Build and Board tab.
    Cross-platform: pane commands are emitted as `cmd /c ...` on Windows and as
    direct invocations on macOS/Linux.

.PARAMETER LayoutName
    Name of the layout (what you pass to: zellij --layout <name>).

.PARAMETER Repos
    Array of repo paths. Each gets a Build tab and a Backlog board tab.

.PARAMETER ProfileName
    OpenCode profile to use in the layout. Defaults to "ws".

.PARAMETER Force
    Overwrite existing layout without prompting.

.EXAMPLE
    .\generate-layout.ps1 -LayoutName "my-app-dev" -Repos @("C:\Projects\my-backend", "C:\Projects\my-frontend")
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$LayoutName,

    [Parameter(Mandatory=$true, Position=1)]
    [string[]]$Repos,

    [Parameter(Mandatory=$false)]
    [string]$ProfileName = "ws",

    [switch]$Force
)

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

function Get-ZellijConfigDir {
    if ($IsWin) { return Join-Path $env:APPDATA "Zellij" "config" }
    $xdg = $env:XDG_CONFIG_HOME
    $base = if ($xdg) { $xdg } else { Join-Path $HOME ".config" }
    return Join-Path $base "zellij"
}

function Normalize-PathForKdl {
    param([string]$Path)
    # Strip trailing backslash/slash (Windows tolerates it but Zellij's cwd
    # resolution can be inconsistent with a trailing separator)
    $Path = $Path.TrimEnd('\', '/')
    if ($IsWin) { return ($Path -replace '\\', '\\') }
    return $Path
}

# Emits a pane block that runs the given command list. On Windows, wraps with
# `cmd /c`; on Unix, invokes the command directly. Returns an array of KDL lines.
# Zellij's KDL parser requires all args values on a single line after `args`.
function Get-PaneBlock {
    param(
        [string]$Cwd,
        [string[]]$CommandArgs,
        [switch]$Focus
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $cwdAttr = if ($Cwd) { " cwd=`"$Cwd`"" } else { "" }
    $focusAttr = if ($Focus) { " focus=true" } else { "" }
    if ($IsWin) {
        $allArgs = @("/c") + $CommandArgs
        $argsLine = ($allArgs | ForEach-Object { "`"$_`"" }) -join " "
        $lines.Add("        pane command=`"cmd`"$cwdAttr$focusAttr {")
        $lines.Add("            args $argsLine")
        $lines.Add("        }")
    } else {
        $exe = $CommandArgs[0]
        $rest = $CommandArgs[1..($CommandArgs.Length-1)]
        $argsLine = ($rest | ForEach-Object { "`"$_`"" }) -join " "
        $lines.Add("        pane command=`"$exe`"$cwdAttr$focusAttr {")
        $lines.Add("            args $argsLine")
        $lines.Add("        }")
    }
    return $lines
}

function Get-TabBarBlock {
    return @(
        "        pane size=1 borderless=true {"
        "            plugin location=`"zellij:tab-bar`""
        "        }"
    )
}

function Get-StatusBarBlock {
    return @(
        "        pane size=1 borderless=true {"
        "            plugin location=`"zellij:status-bar`""
        "        }"
    )
}

# === Validate repo paths ===

for ($i = 0; $i -lt $Repos.Count; $i++) {
    if (-not (Test-Path $Repos[$i])) {
        Write-Error "Repo path does not exist: $($Repos[$i])"
        exit 1
    }
}

$ZellijLayoutDir = Join-Path (Get-ZellijConfigDir) "layouts"
$DestLayout = Join-Path $ZellijLayoutDir "$LayoutName.kdl"

# === Check existing ===

if (Test-Path $DestLayout) {
    if ($Force) {
        Write-Warning "Layout '$LayoutName' already exists. Overwriting (-Force)."
    } else {
        Write-Warning "Layout '$LayoutName' already exists at: $DestLayout"
        $overwrite = Read-Host "Overwrite? (y/N)"
        if ($overwrite -ne "y" -and $overwrite -ne "Y") {
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
}

# === Build layout ===

$firstRepoPath = Normalize-PathForKdl $Repos[0]

$L = [System.Collections.Generic.List[string]]::new()

$L.Add("layout {")
$L.Add("    cwd `"$firstRepoPath`"")

# Tab: Plan (focus on open) — runs in the first repo's dir (where the board lives)
$L.Add("    tab name=`"Plan`" focus=true hide_floating_panes=true {")
$L.AddRange([string[]](Get-TabBarBlock))
$L.AddRange([string[]](Get-PaneBlock -Cwd $firstRepoPath -CommandArgs @("ocx", "oc", "-p", $ProfileName, "--agent", "Plan-WS")))
$L.AddRange([string[]](Get-StatusBarBlock))
$L.Add("    }")

# Tabs: one Build + one Board per repo (indexed)
for ($i = 0; $i -lt $Repos.Count; $i++) {
    $idx = $i + 1
    $repoPath = Normalize-PathForKdl $Repos[$i]

    # Build tab
    $L.Add("    tab name=`"Build $idx`" hide_floating_panes=true {")
    $L.AddRange([string[]](Get-TabBarBlock))
    $L.AddRange([string[]](Get-PaneBlock -Cwd $repoPath -CommandArgs @("ocx", "oc", "-p", $ProfileName, "--agent", "Build-WS")))
    $L.AddRange([string[]](Get-StatusBarBlock))
    $L.Add("    }")

    # Board tab
    $L.Add("    tab name=`"Board $idx`" hide_floating_panes=true {")
    $L.AddRange([string[]](Get-TabBarBlock))
    $L.AddRange([string[]](Get-PaneBlock -Cwd $repoPath -CommandArgs @("backlog", "board")))
    $L.AddRange([string[]](Get-StatusBarBlock))
    $L.Add("    }")
}

# Tab: Merge (in first repo's dir)
$L.Add("    tab name=`"Merge`" hide_floating_panes=true {")
$L.AddRange([string[]](Get-TabBarBlock))
$L.AddRange([string[]](Get-PaneBlock -Cwd $firstRepoPath -CommandArgs @("ocx", "oc", "-p", $ProfileName, "--agent", "Merger-WS")))
$L.AddRange([string[]](Get-StatusBarBlock))
$L.Add("    }")

# Tab: Shell (in first repo's dir)
$L.Add("    tab name=`"Shell`" hide_floating_panes=true {")
$L.AddRange([string[]](Get-TabBarBlock))
$L.Add("        pane cwd=`"$firstRepoPath`"")
$L.AddRange([string[]](Get-StatusBarBlock))
$L.Add("    }")

# new_tab_template
$L.Add("    new_tab_template {")
$L.AddRange([string[]](Get-TabBarBlock))
$L.Add("        pane")
$L.AddRange([string[]](Get-StatusBarBlock))
$L.Add("    }")

# Close the layout block
$L.Add("}")

# === Write + Report ===

if (-not (Test-Path $ZellijLayoutDir)) {
    New-Item -ItemType Directory -Path $ZellijLayoutDir -Force | Out-Null
}

$layoutContent = ($L -join "`n")
Set-Content -LiteralPath $DestLayout -Value $layoutContent -NoNewline

# === Report ===

$tabCount = 3 + ($Repos.Count * 2)
Write-Host ""
Write-Host "  Layout: $LayoutName ($tabCount tabs)  [$OS]" -ForegroundColor Cyan
Write-Host "  File:   $DestLayout" -ForegroundColor Gray
Write-Host ""
Write-Host "  Tabs:" -ForegroundColor White
Write-Host "    Plan              - Task creation (Plan-WS agent)" -ForegroundColor DarkGray
for ($i = 0; $i -lt $Repos.Count; $i++) {
    $idx = $i + 1
    Write-Host "    Build $idx            - Build orchestrator (Build-WS)" -ForegroundColor DarkGray
    Write-Host "    Board $idx            - Backlog.md board view" -ForegroundColor DarkGray
}
Write-Host "    Merge             - Merge orchestrator (Merger-WS)" -ForegroundColor DarkGray
Write-Host "    Shell             - Shell" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Launch:  zellij --layout $LayoutName" -ForegroundColor Cyan
Write-Host ""

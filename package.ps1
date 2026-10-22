<#
.SYNOPSIS
    Creates a shareable zip of The AI Workspace for distribution to teammates.

.DESCRIPTION
    Bundles everything a colleague needs, for any target OS (any OS can build
    all three zips - package.sh produces identical output):

    - windows: PowerShell tree (root .ps1 scripts + profile/ from the repo)
    - macos / linux: bash tree (unix/ scripts + unix/profile/ from the repo)

    Each zip includes:
    - The scripts for that OS
    - package.ps1 (windows) or package.sh (macos/linux) so recipients can re-package
    - README.md
    - The full ws profile (agents, skills, plugins, commands, tools, configs)
    - QUICKSTART.txt (OS-aware instructions)

    macos and linux zips share the bash tree and differ only in QUICKSTART.txt.
    All text in macos/linux zips is LF-normalized (bash must not see CRLF).
    Profile contents are staged from the REPO tree, never from an installed machine.

.EXAMPLE
    .\package.ps1
    # Creates TheAIWorkSpace-<date>-windows.zip (default OS)

.EXAMPLE
    .\package.ps1 -OS macos
    # Creates TheAIWorkSpace-<date>-macos.zip (bash tree)

.EXAMPLE
    .\package.ps1 -OS linux
    # Creates TheAIWorkSpace-<date>-linux.zip (bash tree)

.PARAMETER OS
    Target operating system for the package. Sets the zip name suffix and
    tailors the QUICKSTART.txt instructions included for the recipient.
    Valid values: windows, macos, linux. Default: windows.
#>
param(
    [ValidateSet('windows','macos','linux')]
    [string]$OS = 'windows'
)

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $PSCommandPath
$Date = Get-Date -Format "yyyy-MM-dd"
$ZipPath = Join-Path (Get-Location) "TheAIWorkSpace-$Date-$OS.zip"

# === Collect files ===

$StagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "TheAIWorkSpace-staging"
if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

$WindowsScripts = @(
    "bootstrap.ps1",
    "install-deps.ps1",
    "setup-repo.ps1",
    "generate-layout.ps1",
    "setup-workspace.ps1",
    "new-build-agent.ps1",
    "config-ws.kdl",
    "package.ps1",
    "uninstall.ps1",
    "README.md"
)

$UnixScripts = @(
    "bootstrap.sh",
    "install-deps.sh",
    "setup-repo.sh",
    "generate-layout.sh",
    "setup-workspace.sh",
    "new-build-agent.sh",
    "uninstall.sh",
    "config-ws.kdl"
)

# 1. Copy the scripts + README
if ($OS -eq 'windows') {
    foreach ($s in $WindowsScripts) {
        $src = Join-Path $SourceDir $s
        if (Test-Path $src) {
            Copy-Item $src $StagingDir -Force
        } else {
            Write-Warning "Missing: $s"
        }
    }
} else {
    $UnixDir = Join-Path $SourceDir "unix"
    foreach ($s in $UnixScripts) {
        $src = Join-Path $UnixDir $s
        if (Test-Path $src) {
            Copy-Item $src $StagingDir -Force
        } else {
            Write-Warning "Missing: unix/$s"
        }
    }
    # package.sh so bash recipients can re-package after customizing
    $packageSh = Join-Path $SourceDir "package.sh"
    if (Test-Path $packageSh) {
        Copy-Item $packageSh $StagingDir -Force
    } else {
        Write-Warning "Missing: package.sh"
    }
    # README.md from the repo root (same doc set as the windows zip)
    $readmeSrc = Join-Path $SourceDir "README.md"
    if (Test-Path $readmeSrc) {
        Copy-Item $readmeSrc $StagingDir -Force
    } else {
        Write-Warning "Missing: README.md"
    }
}

# 2. Copy the ws profile (from the REPO tree, never from an installed machine)
if ($OS -eq 'windows') {
    $WsProfileDir = Join-Path $SourceDir "profile"
} else {
    $WsProfileDir = Join-Path $SourceDir "unix" "profile"
}

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
    $PkgLock = Join-Path $ProfileDest "package-lock.json"
    if (Test-Path $PkgLock) { Remove-Item $PkgLock -Force }
    $DsStore = Join-Path $ProfileDest ".DS_Store"
    if (Test-Path $DsStore) { Remove-Item $DsStore -Force }

    Write-Host "[OK] Profile included" -ForegroundColor Green
} else {
    Write-Warning "ws profile not found at: $WsProfileDir"
    Write-Warning "Package will not include the profile. Colleague will need it separately."
}

# 3. Create a QUICKSTART.txt (OS-aware)
if ($OS -eq 'windows') {
    $Quickstart = @'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)

2. Open PowerShell in the extracted folder:
   - Right-click in the folder -> "Open in Terminal"
   - Or: Open PowerShell, cd to the folder

3. Run:
   .\bootstrap.ps1

4. Follow the prompts. It will (in order):
   a. Fix PowerShell execution policy if needed (Windows)
   b. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   c. Install the OpenCode "ws" profile (agents, skills, plugins)
   d. Ask for your project name and repo paths
   e. Set up each repo with workflow scripts and Backlog.md
   f. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with -Force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$env:APPDATA\Zellij\config\config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
On Windows, freshly installed npm may not be on PATH in the
current session. If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: .\bootstrap.ps1

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "scripts can't run" -> The bootstrap fixes this automatically on Windows
- "npm not found after install" -> Restart terminal, re-run .\bootstrap.ps1
- "zellij not found" -> See https://zellij.dev/documentation/installation
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.ps1 did, run:
   .\uninstall.ps1   (Windows)
   pwsh ./uninstall.ps1   (macOS/Linux)

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
'@
} elseif ($OS -eq 'macos') {
    $Quickstart = @'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)
PREREQUISITE (macOS): Homebrew is used for dependency installs (git, node,
zellij). Install it from https://brew.sh if you don't have it.

2. Open a terminal in the extracted folder:
   - Right-click the folder -> "Open Terminal Here" (many file managers)
   - Or: Open your terminal app and cd to the folder

3. Run:
   bash bootstrap.sh

4. Follow the prompts. It will (in order):
   a. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   b. Install the OpenCode "ws" profile (agents, skills, plugins)
   c. Ask for your project name and repo paths
   d. Set up each repo with workflow scripts and Backlog.md
   e. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with --force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$HOME/.config/zellij/config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
Freshly installed npm may not be on PATH in the current session.
If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: bash bootstrap.sh

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "Homebrew not found" -> Install it from https://brew.sh, then re-run bash bootstrap.sh
- "npm not found after install" -> Restart terminal, re-run bash bootstrap.sh
- "zellij not found" -> See https://zellij.dev/documentation/installation
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.sh did, run:
   bash uninstall.sh

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
'@
} else {
    $Quickstart = @'
THE AI WORKSPACE - QUICK START
================================

1. Extract this zip somewhere (e.g., Desktop/Downloads or your home folder)
PREREQUISITE (Linux): System packages install with sudo via your package
manager: apt (Debian/Ubuntu), dnf (Fedora/RHEL), or pacman (Arch).
Zellij installs as a prebuilt binary to ~/.local/bin.

2. Open a terminal in the extracted folder:
   - Right-click the folder -> "Open Terminal Here" (many file managers)
   - Or: Open your terminal app and cd to the folder

3. Run:
   bash bootstrap.sh

4. Follow the prompts. It will (in order):
   a. Install any missing tools (git, node, zellij, backlog, ocx, opencode)
      - Already have some? No problem - it skips installed ones
   b. Install the OpenCode "ws" profile (agents, skills, plugins)
   c. Ask for your project name and repo paths
   d. Set up each repo with workflow scripts and Backlog.md
   e. Generate (or overwrite) a Zellij layout

   NOTE: bootstrap runs with --force, so re-running it is safe and won't
   prompt before overwriting layouts, AGENTS.md, or workflow scripts. It
   will still prompt for project name and repo paths.

5. When done, launch:
   zellij --config "$HOME/.config/zellij/config-<your-layout-name>.kdl" --layout <your-layout-name>

6. Read README.md for the full guide.


WHAT IF I ALREADY HAVE SOME TOOLS?
====================================
The installer checks each tool individually. If you already have
git, node, etc., it detects them and skips. No re-installs,
no conflicts.


WHAT IF I ALREADY HAVE AN OPENCODE PROFILE CALLED "ws"?
========================================================
The bootstrap will ask before overwriting. You can keep your
existing profile and just use the scripts.


WHAT IF NPM WAS JUST INSTALLED AND THINGS FAIL?
================================================
Freshly installed npm may not be on PATH in the current session.
If you see errors about npm/ocx/opencode not found:

1. Close this terminal
2. Open a new one
3. cd back to the extracted folder
4. Run again: bash bootstrap.sh

It will skip already-installed tools and pick up where it left off.


TROUBLESHOOTING
===============
- "sudo: command not found" -> Install sudo, or run as root
- "No supported package manager" -> Supported: apt, dnf, pacman
- "npm not found after install" -> Restart terminal, re-run bash bootstrap.sh
- "zellij not found" -> Restart terminal so ~/.local/bin is on PATH
- Other issues -> Read README.md troubleshooting section


UNINSTALLING
============
To undo everything bootstrap.sh did, run:
   bash uninstall.sh

It will walk you through each component with y/n prompts so you can
choose exactly what to remove.
'@
}

Set-Content -LiteralPath (Join-Path $StagingDir "QUICKSTART.txt") -Value $Quickstart -NoNewline
Write-Host "[OK] QUICKSTART.txt created ($OS)" -ForegroundColor Green

# 3b. Normalize all staged text to LF (macos/linux: bash must not see CRLF)
if ($OS -ne 'windows') {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    Get-ChildItem -LiteralPath $StagingDir -Recurse -File | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        if ($text.Contains("`r")) {
            [System.IO.File]::WriteAllText($_.FullName, $text.Replace("`r`n", "`n"), $utf8NoBom)
        }
    }
    Write-Host "[OK] LF normalization done ($OS)" -ForegroundColor Green
}

# 4. Zip it (forward-slash entry names via .NET ZipFile - portable on all targets)
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $StagingDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($StagingDir.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
}
Remove-Item $StagingDir -Recurse -Force

$size = [math]::Round((Get-Item $ZipPath).Length / 1KB)
Write-Host ""
Write-Host "[OK] Package created: $ZipPath ($size KB)" -ForegroundColor Green
Write-Host "     Send this zip to your colleague." -ForegroundColor Cyan
$runHint = if ($OS -eq 'windows') { ".\bootstrap.ps1" } else { "bash bootstrap.sh" }
Write-Host "     They extract it and run: $runHint" -ForegroundColor Cyan
Write-Host ""

# create-shortcuts.ps1 - Claude Code shortcuts on the Windows desktop.
#
#   powershell -ExecutionPolicy Bypass -File create-shortcuts.ps1
#
# Creates:
#
#   %LOCALAPPDATA%\zim-claude\
#     start-all.bat     - bring the whole stack up, then run zim-claude
#     new-session.bat   - just a new independent zim-claude session
#     wsl--shrink.bat   - reclaim disk space held by the WSL virtual disk
#
#   Desktop:
#     Claude Code.lnk              - start-all.bat, in a Windows Terminal window
#     Claude Code - session.lnk    - new-session.bat, in a Windows Terminal window
#     Claude Folder.lnk            - the WSL home directory in Explorer
#     WSL Shrink.lnk               - wsl--shrink.bat (asks for admin rights)
#
# Everything is placed under %LOCALAPPDATA% rather than a fixed drive path, so
# the layout is the same on every machine regardless of user name or where
# Windows lives.
#
# Every launch is a new window and a new independent session. Without Windows
# Terminal the .bat falls back to a plain console window.
#
# Encoding: this file is pure ASCII, with no BOM, and so are the .bat files it
# writes. Windows PowerShell 5.1 decodes a BOM-less script with the machine's
# ANSI codepage rather than UTF-8, so one non-ASCII character can end a string
# early and break the file hundreds of lines later; cmd.exe misreads a BOM as
# part of the first command. Keeping everything ASCII removes the codepage from
# the equation. This matches windows/ in the repo root.

param(
    [string]$Distro = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'

$AppDir  = Join-Path $env:LOCALAPPDATA 'zim-claude'
$IconDir = Join-Path $AppDir 'icons'
$Desktop = [Environment]::GetFolderPath('Desktop')

New-Item -ItemType Directory -Force -Path $AppDir, $IconDir | Out-Null

function Write-Say($m) { Write-Host "  $m" }
function Write-Ok($m)  { Write-Host "  [+] $m" -ForegroundColor Green }

# --- .bat: two launch scenarios ----------------------------------------------

$startAllBat = @'
@echo off
chcp 65001 >nul
rem Bring the whole stack up: Docker, SearxNG, proxies :4000 (terminal) and
rem :4002 (Claude Desktop gateway), and finally zim-claude. Own window.
setlocal
set "DISTRO=__DISTRO__"
set "CMD=./start-all.sh"

where wt.exe >nul 2>&1
if errorlevel 1 goto plain
wt.exe new-tab --title "Claude Code" wsl.exe -d %DISTRO% --cd "~" -- bash -lic "%CMD%"
exit /b 0

:plain
wsl.exe -d %DISTRO% --cd "~" -- bash -lic "%CMD%"
exit /b 0
'@

$newSessionBat = @'
@echo off
chcp 65001 >nul
rem A new independent zim-claude session, without restarting the stack.
rem If the proxy is down, zim-claude starts it itself.
rem Drag a folder onto this file to start the session in that folder.
setlocal
set "DISTRO=__DISTRO__"
set "CMD=zim-claude --dangerously-skip-permissions"

rem Start folder: the argument, else the WSL home directory.
set "WORKDIR=%~1"
if "%WORKDIR%"=="" set "WORKDIR=~"

where wt.exe >nul 2>&1
if errorlevel 1 goto plain
wt.exe new-tab --title "zim-claude" wsl.exe -d %DISTRO% --cd "%WORKDIR%" -- bash -lic "%CMD%"
exit /b 0

:plain
wsl.exe -d %DISTRO% --cd "%WORKDIR%" -- bash -lic "%CMD%"
exit /b 0
'@

$startAllBat   = $startAllBat.Replace('__DISTRO__', $Distro) -replace "`r?`n", "`r`n"
$newSessionBat = $newSessionBat.Replace('__DISTRO__', $Distro) -replace "`r?`n", "`r`n"

$ascii = New-Object System.Text.ASCIIEncoding
[System.IO.File]::WriteAllText((Join-Path $AppDir 'start-all.bat'),   $startAllBat,   $ascii)
[System.IO.File]::WriteAllText((Join-Path $AppDir 'new-session.bat'), $newSessionBat, $ascii)

# wsl--shrink.bat ships as a file beside this script: it is long enough that
# embedding it as a here-string would make it painful to edit. Copied with CRLF
# preserved - cmd.exe needs it.
$shrinkSrc = Join-Path $PSScriptRoot 'wsl--shrink.bat'
$shrinkBat = Join-Path $AppDir 'wsl--shrink.bat'
if (Test-Path $shrinkSrc) {
    $text = [System.IO.File]::ReadAllText($shrinkSrc) -replace "`r?`n", "`r`n"
    [System.IO.File]::WriteAllText($shrinkBat, $text, $ascii)
    Write-Ok "wsl--shrink.bat"
} else {
    Write-Say "no wsl--shrink.bat beside the script - skipping the disk cleaner"
}

Write-Ok "launch scripts: $AppDir"

# --- icons ------------------------------------------------------------------
# Copied from icons/ beside this script. Without them the shortcuts still work,
# they just get the default terminal icon.
$IconsSrc = Join-Path $PSScriptRoot 'icons'
foreach ($name in @('claude-launch.ico', 'claude-session.ico')) {
    $src = Join-Path $IconsSrc $name
    $dst = Join-Path $IconDir $name
    if (Test-Path $src) {
        Copy-Item -Force -Path $src -Destination $dst
        Write-Ok "icon: $name"
    } else {
        Write-Say "no icon: $name - the shortcut will use the default one"
    }
}
$LaunchIcon  = Join-Path $IconDir 'claude-launch.ico'
$SessionIcon = Join-Path $IconDir 'claude-session.ico'

# --- shortcuts --------------------------------------------------------------
$shell = New-Object -ComObject WScript.Shell

function New-Shortcut {
    param(
        [string]$Name,
        [string]$Target,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = '',
        [string]$Description = ''
    )
    $final = Join-Path $Desktop ($Name + '.lnk')

    $sc = $shell.CreateShortcut($final)
    $sc.TargetPath       = $Target
    $sc.Arguments        = $Arguments
    $sc.WorkingDirectory = $WorkingDirectory
    if ($IconLocation -and (Test-Path ($IconLocation -split ',')[0])) {
        $sc.IconLocation = $IconLocation
    }
    $sc.Description = $Description
    $sc.Save()
    Write-Ok "shortcut: $Name"
}

$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'

# 1. Everything at once: the stack, then zim-claude.
New-Shortcut -Name 'Claude Code' `
    -Target $cmdExe `
    -Arguments ('/c ""{0}""' -f (Join-Path $AppDir 'start-all.bat')) `
    -WorkingDirectory $AppDir `
    -IconLocation "$LaunchIcon,0" `
    -Description 'Claude Code - start everything (docker, searxng, proxies, Computer, zim-claude)'

# 2. A new independent session.
New-Shortcut -Name 'Claude Code - session' `
    -Target $cmdExe `
    -Arguments ('/c ""{0}""' -f (Join-Path $AppDir 'new-session.bat')) `
    -WorkingDirectory $AppDir `
    -IconLocation "$SessionIcon,0" `
    -Description 'Claude Code - a new independent session in its own window'

# 3. The WSL home directory in Explorer.
# Ask WSL itself: its user name does not have to match the Windows one.
$wslHome = $null
try {
    $rel = & wsl.exe -d $Distro -- bash -lc 'echo $HOME' 2>$null
    $rel = ($rel | Out-String).Trim() -replace "`0", ''
    if ($rel -match '^/home/(.+)$') { $wslHome = "\\wsl.localhost\$Distro\home\$($Matches[1])" }
} catch { }
if (-not $wslHome) { $wslHome = "\\wsl.localhost\$Distro" }

New-Shortcut -Name 'Claude Folder' -Target $wslHome `
    -Description "WSL home directory ($Distro)"

# 4. WSL disk shrink. Runs the .bat directly: it raises its own UAC prompt, so
# the shortcut itself needs no admin rights and works for every user.
if (Test-Path $shrinkBat) {
    New-Shortcut -Name 'WSL Shrink' `
        -Target $shrinkBat `
        -WorkingDirectory $AppDir `
        -Description 'Reclaim disk space used by the WSL virtual disk'
}

Write-Host ''
Write-Ok "done: $Desktop"

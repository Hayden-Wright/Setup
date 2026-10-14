#Requires -Version 5.1
<#
    Установка настроек Sublime Text из репозитория setup.

    Одной командой (PowerShell):
        irm "https://raw.githubusercontent.com/Hayden-Wright/setup/main/3.%20%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Sublime%20Text/install.ps1" | iex
#>

$ErrorActionPreference = 'Stop'

$base = 'https://raw.githubusercontent.com/Hayden-Wright/setup/main/3.%20%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Sublime%20Text'

$sublimeDir  = Join-Path $env:APPDATA 'Sublime Text'
$packagesDir = Join-Path $sublimeDir 'Packages'
$userDir     = Join-Path $packagesDir 'User'
$themeDir    = Join-Path $packagesDir 'AuraTheme'
$installedDir = Join-Path $sublimeDir 'Installed Packages'

# --- Проверка, что Sublime Text стоит ------------------------------------
if (-not (Test-Path $sublimeDir)) {
    Write-Warning "Sublime Text не найден: $sublimeDir"
    Write-Host  "Поставь и запусти его один раз, потом повтори."
    Write-Host  "Скачать: https://www.sublimetext.com/download"
    exit 1
}

# --- Бэкап текущих настроек ---------------------------------------------
$stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$backupDir = Join-Path $sublimeDir "Packages_backup_$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

foreach ($item in @('User', 'AuraTheme')) {
    $src = Join-Path $packagesDir $item
    if (Test-Path $src) {
        Copy-Item $src -Destination $backupDir -Recurse -Force
    }
}
Write-Host "Бэкап: $backupDir"

# --- Скачивание конфигов -------------------------------------------------
New-Item -ItemType Directory -Path $userDir  -Force | Out-Null
New-Item -ItemType Directory -Path $themeDir -Force | Out-Null

$files = @(
    @{ Url = "$base/Packages/User/Preferences.sublime-settings";       Dst = $userDir  },
    @{ Url = "$base/Packages/User/Markdown.sublime-settings";          Dst = $userDir  },
    @{ Url = "$base/Packages/User/Package%20Control.sublime-settings"; Dst = $userDir  },
    @{ Url = "$base/Packages/AuraTheme/aura-theme-soft.tmTheme";       Dst = $themeDir }
)

foreach ($f in $files) {
    $name = [uri]::UnescapeDataString(($f.Url -split '/')[-1])
    $dest = Join-Path $f.Dst $name
    Invoke-WebRequest -Uri $f.Url -OutFile $dest -UseBasicParsing
    Write-Host "Скачано: $name"
}

# --- Package Control (ставит и доустанавливает пакеты сам) ----------------
New-Item -ItemType Directory -Path $installedDir -Force | Out-Null
$pcPath = Join-Path $installedDir 'Package Control.sublime-package'

if (-not (Test-Path $pcPath)) {
    Invoke-WebRequest -Uri 'https://download.sublimetext.com/Package%20Control.sublime-package' `
        -OutFile $pcPath -UseBasicParsing
    Write-Host "Package Control установлен."
} else {
    Write-Host "Package Control уже стоит."
}

Write-Host @"

Готово. Открой Sublime Text — он сам доустановит MarkdownEditing и Markdown Extended
(список лежит в Package Control.sublime-settings, Package Control его подхватит).

Бэкап прежних настроек: $backupDir
"@

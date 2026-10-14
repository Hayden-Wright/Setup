#Requires -Version 5.1
<#
    Установка настроек Sublime Text из этого репозитория.

    Запуск (из папки "3. Конфиги/Sublime Text"):
        powershell -ExecutionPolicy Bypass -File .\install.ps1
#>

$ErrorActionPreference = 'Stop'

$source     = Join-Path $PSScriptRoot 'Packages'
$sublimeDir = Join-Path $env:APPDATA 'Sublime Text'
$packagesDir = Join-Path $sublimeDir 'Packages'

if (-not (Test-Path $source)) {
    throw "Не найдена папка Packages рядом со скриптом: $source"
}

if (-not (Test-Path $sublimeDir)) {
    Write-Warning "Sublime Text не найден в $sublimeDir"
    Write-Host  "Поставь его, запусти один раз, потом запусти этот скрипт снова."
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
        Write-Host "Бэкап: $item -> $backupDir"
    }
}
Write-Host ""

# --- Копирование конфигов ------------------------------------------------
foreach ($item in @('User', 'AuraTheme')) {
    $src = Join-Path $source $item
    $dst = Join-Path $packagesDir $item
    if (-not (Test-Path $src)) { continue }

    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item (Join-Path $src '*') -Destination $dst -Recurse -Force
    Write-Host "Скопировано: $item"
}

# --- Проверка темы -------------------------------------------------------
$theme = Join-Path $packagesDir 'AuraTheme\aura-theme-soft.tmTheme'
if (Test-Path $theme) {
    Write-Host "Тема Aura на месте."
} else {
    Write-Warning "Тема Aura не найдена: $theme"
}

Write-Host @"

Готово. Осталось:
  1. Открыть Sublime Text.
  2. Ctrl+Shift+P -> Install Package Control  (если ещё не установлен).
  3. Ctrl+Shift+P -> Install Package -> MarkdownEditing, Markdown Extended.

Бэкап прежних настроек: $backupDir
"@

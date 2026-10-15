#Requires -Version 5.1
<#
    Полная установка Sublime Text с настройками из репозитория setup.

    Одной командой (PowerShell):
        Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Sublime-Text/install.ps1" -OutFile $env:TEMP\sublime-setup.ps1; & $env:TEMP\sublime-setup.ps1

    Или из клона репозитория:
        .\install.ps1

    Что делает:
      1. Ставит Sublime Text через winget, если его нет.
      2. Закрывает запущенный редактор (иначе он перезапишет настройки при выходе).
      3. Делает бэкап текущих настроек.
      4. Кладёт конфиги и тему Aura.
      5. Ставит Package Control и пакеты MarkdownEditing + Markdown Extended.

    Файл сохранён с BOM: без него PowerShell 5.1 читает кириллицу как ANSI
    и портит все строки при запуске скрипта по пути.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Base = 'https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Sublime-Text'

$SublimeDir   = Join-Path $env:APPDATA 'Sublime Text'
$PackagesDir  = Join-Path $SublimeDir 'Packages'
$InstalledDir = Join-Path $SublimeDir 'Installed Packages'
$UserDir      = Join-Path $PackagesDir 'User'
$ThemeDir     = Join-Path $PackagesDir 'AuraTheme'

$TempRoot = Join-Path $env:TEMP ("sublime-setup-" + (Get-Random))

function Write-Step { param([string]$Text) Write-Host "  $Text" }
function Write-Ok   { param([string]$Text) Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Bad  { param([string]$Text) Write-Host "  [!] $Text"  -ForegroundColor Yellow }

function Get-SublimeExe {
    @(
        (Join-Path $env:ProgramFiles 'Sublime Text\sublime_text.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Sublime Text\sublime_text.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Sublime Text\sublime_text.exe')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

# Скачивает файл. Net.WebClient нужен явный UTF-8, иначе кириллица в
# настройках превратится в мусор.
function Save-File {
    param([string]$Url, [string]$Destination)
    $dir = Split-Path $Destination -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $wc.DownloadFile($Url, $Destination)
}

# Кладёт файл конфига: из клона репозитория рядом со скриптом, иначе из сети.
function Install-ConfigFile {
    param([string]$RelativePath, [string]$UrlPath, [string]$Destination)
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $RelativePath } else { $null }
    if ($local -and (Test-Path $local)) {
        $dir = Split-Path $Destination -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $local -Destination $Destination -Force
    } else {
        Save-File -Url "$Base/$UrlPath" -Destination $Destination
    }
}

# Распаковывает пакет с GitHub: внутри архива один корневой каталог.
function Expand-Package {
    param([string]$Url, [string]$Destination)
    $zip = Join-Path $TempRoot ("pkg-" + (Get-Random) + '.zip')
    $extract = Join-Path $TempRoot ("x-" + (Get-Random))

    Save-File -Url $Url -Destination $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $root = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
    $source = if ($root) { $root.FullName } else { $extract }

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # -Force обязателен, иначе не скопируются скрытые файлы
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

Write-Host ''
Write-Host 'Sublime Text: установка настроек' -ForegroundColor Cyan
Write-Host ''

# --- 1. Sublime Text ------------------------------------------------------

Write-Step 'Проверяю, установлен ли Sublime Text...'

$sublimeExe = Get-SublimeExe

if (-not $sublimeExe) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host ''
        Write-Bad 'Sublime Text не найден, и winget недоступен.'
        Write-Host '  Поставь вручную: https://www.sublimetext.com/download'
        Write-Host '  Потом запусти эту команду снова.'
        return
    }

    Write-Step 'Не найден — ставлю через winget (займёт около минуты)...'
    & winget install --id SublimeHQ.SublimeText.4 --exact `
        --accept-package-agreements --accept-source-agreements --silent | Out-Null

    $sublimeExe = Get-SublimeExe
    if (-not $sublimeExe) {
        Write-Bad 'winget отработал, но sublime_text.exe не найден.'
        Write-Host '  Запусти Sublime один раз и повтори команду.'
        return
    }
}

$build = [int](Get-Item $sublimeExe).VersionInfo.FileVersion
Write-Ok "Sublime Text найден (build $build)"

# --- 2. Закрыть редактор --------------------------------------------------

$running = Get-Process sublime_text -ErrorAction SilentlyContinue
if ($running) {
    Write-Step 'Sublime запущен — закрываю, иначе он перезапишет настройки при выходе...'
    $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process sublime_text -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process sublime_text -ErrorAction SilentlyContinue) {
        Write-Bad 'Не закрылся сам. Закрой его вручную и запусти команду снова.'
        return
    }
    Write-Ok 'Закрыт (несохранённые вкладки восстановятся при следующем запуске)'
}

# --- 3. Бэкап -------------------------------------------------------------

New-Item -ItemType Directory -Path $PackagesDir  -Force | Out-Null
New-Item -ItemType Directory -Path $InstalledDir -Force | Out-Null

$stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$backupDir = Join-Path $SublimeDir "Packages_backup_$stamp"
$hasOld    = $false

foreach ($item in @('User', 'AuraTheme')) {
    $src = Join-Path $PackagesDir $item
    if (Test-Path $src) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $backupDir -Recurse -Force
        $hasOld = $true
    }
}

if ($hasOld) { Write-Ok "Бэкап прежних настроек: $backupDir" }
else         { Write-Ok 'Прежних настроек не было — бэкап не нужен' }

# --- 4. Конфиги и тема ----------------------------------------------------

Install-ConfigFile -RelativePath 'Packages\User\Preferences.sublime-settings' `
                   -UrlPath 'Packages/User/Preferences.sublime-settings' `
                   -Destination (Join-Path $UserDir 'Preferences.sublime-settings')

Install-ConfigFile -RelativePath 'Packages\User\Markdown.sublime-settings' `
                   -UrlPath 'Packages/User/Markdown.sublime-settings' `
                   -Destination (Join-Path $UserDir 'Markdown.sublime-settings')

Install-ConfigFile -RelativePath 'Packages\User\Package Control.sublime-settings' `
                   -UrlPath 'Packages/User/Package%20Control.sublime-settings' `
                   -Destination (Join-Path $UserDir 'Package Control.sublime-settings')

Install-ConfigFile -RelativePath 'Packages\AuraTheme\aura-theme-soft.tmTheme' `
                   -UrlPath 'Packages/AuraTheme/aura-theme-soft.tmTheme' `
                   -Destination (Join-Path $ThemeDir 'aura-theme-soft.tmTheme')

Write-Ok 'Настройки и тема Aura на месте'

# --- 5. Пакеты ------------------------------------------------------------

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

try {
    Save-File -Url 'https://packagecontrol.io/Package%20Control.sublime-package' `
              -Destination (Join-Path $InstalledDir 'Package Control.sublime-package')
    Write-Ok 'Package Control'
} catch {
    Write-Bad "Package Control не поставился: $($_.Exception.Message)"
}

# У MarkdownEditing отдельные сборки под старые и новые версии Sublime
$meUrl = if ($build -ge 4200) {
    'https://codeload.github.com/SublimeText-Markdown/MarkdownEditing/zip/4200-3.6.4'
} else {
    'https://codeload.github.com/SublimeText-Markdown/MarkdownEditing/zip/4107-3.6.4'
}

try {
    Expand-Package -Url $meUrl -Destination (Join-Path $PackagesDir 'MarkdownEditing')
    Write-Ok 'MarkdownEditing'
} catch {
    Write-Bad "MarkdownEditing не поставился: $($_.Exception.Message)"
}

try {
    Expand-Package -Url 'https://codeload.github.com/jonschlinkert/sublime-markdown-extended/zip/master' `
                   -Destination (Join-Path $PackagesDir 'Markdown Extended')
    Write-Ok 'Markdown Extended'
} catch {
    Write-Bad "Markdown Extended не поставился: $($_.Exception.Message)"
}

Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue

# --- Итог -----------------------------------------------------------------

Write-Host ''
Write-Host 'Готово.' -ForegroundColor Green
Write-Host ''
Write-Host "  Настройки : $UserDir"
Write-Host "  Тема      : $ThemeDir"
if ($hasOld) { Write-Host "  Бэкап     : $backupDir" }
Write-Host ''
Write-Host 'Открой Sublime Text — тема и подсветка Markdown уже должны работать.'
Write-Host ''

#Requires -Version 5.1
<#
    Полная настройка Windows Terminal из репозитория Setup.

    Одной командой (PowerShell):
        irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Windows%20Terminal/install.ps1" -OutFile $env:TEMP\wt-setup.ps1; & $env:TEMP\wt-setup.ps1

    Или из клона репозитория:
        .\install.ps1

    Что делает:
      1. Ставит Windows Terminal через winget, если его нет.
      2. Ставит шрифт JetBrainsMono Nerd Font, если его нет.
      3. Делает бэкап текущего settings.json.
      4. Кладёт settings.json: тема Catppuccin Mocha, прозрачность 80%, шрифт.

    Терминал при этом не закрывается: он перечитывает settings.json сам,
    а закрывать его нельзя — скрипт обычно выполняется внутри него же.

    Файл сохранён с BOM: без него PowerShell 5.1 читает кириллицу как ANSI
    и портит все строки при запуске скрипта по пути.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# URL закодирован вручную: так он не зависит от кодировки самого файла
$Base = 'https://raw.githubusercontent.com/Hayden-Wright/Setup/main/%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Windows%20Terminal'

# Имя семейства шрифта, как его видит Windows. По нему проверяем, стоит ли шрифт.
$FontFamily = 'JetBrainsMono NFM'

function Write-Step { param([string]$Text) Write-Host "  $Text" }
function Write-Ok   { param([string]$Text) Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Bad  { param([string]$Text) Write-Host "  [!] $Text"  -ForegroundColor Yellow }

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

# Кладёт settings.json: из клона репозитория рядом со скриптом, иначе из сети.
function Install-Settings {
    param([string]$Destination)
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'settings.json' } else { $null }
    if ($local -and (Test-Path $local)) {
        Copy-Item -LiteralPath $local -Destination $Destination -Force
    } else {
        Save-File -Url "$Base/settings.json" -Destination $Destination
    }
}

# Ищет settings.json. У Terminal их три возможных места: Store-версия,
# Preview и распакованная (scoop). Берём первое существующее.
function Get-SettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($found) { return $found }
    # Ни одного нет — Terminal ещё не запускался. Вернём путь Store-версии.
    $candidates[0]
}

# Проверяет, установлен ли шрифт: смотрим реестр, а не файлы, потому что
# шрифт может стоять и для пользователя, и для всей системы.
function Test-FontInstalled {
    foreach ($hive in @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )) {
        if (-not (Test-Path $hive)) { continue }
        $props = (Get-ItemProperty $hive).PSObject.Properties |
                 Where-Object { $_.Name -like "$FontFamily*" }
        if ($props) { return $true }
    }
    return $false
}

Write-Host ''
Write-Host 'Windows Terminal: установка настроек' -ForegroundColor Cyan
Write-Host ''

# --- 1. Windows Terminal --------------------------------------------------

Write-Step 'Проверяю, установлен ли Windows Terminal...'

$wt = Get-AppxPackage -Name '*WindowsTerminal*' -ErrorAction SilentlyContinue |
      Select-Object -First 1

if (-not $wt) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host ''
        Write-Bad 'Windows Terminal не найден, и winget недоступен.'
        Write-Host '  Поставь вручную из Microsoft Store: https://aka.ms/terminal'
        Write-Host '  Потом запусти эту команду снова.'
        return
    }

    Write-Step 'Не найден — ставлю через winget (займёт около минуты)...'
    & winget install --id Microsoft.WindowsTerminal --exact `
        --accept-package-agreements --accept-source-agreements --silent | Out-Null

    $wt = Get-AppxPackage -Name '*WindowsTerminal*' -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $wt) {
        Write-Bad 'winget отработал, но Windows Terminal не появился.'
        Write-Host '  Поставь из Microsoft Store и повтори команду.'
        return
    }
}

Write-Ok "Windows Terminal найден ($($wt.Version))"

# --- 2. Шрифт -------------------------------------------------------------

Write-Step 'Проверяю шрифт JetBrainsMono Nerd Font...'

if (Test-FontInstalled) {
    Write-Ok 'Шрифт уже стоит'
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Step 'Шрифта нет — ставлю через winget...'
    try {
        & winget install --id DEVCOM.JetBrainsMonoNerdFont --exact `
            --accept-package-agreements --accept-source-agreements --silent | Out-Null
        if (Test-FontInstalled) {
            Write-Ok 'Шрифт поставлен'
        } else {
            Write-Bad 'winget отработал, но шрифт не зарегистрировался. Перезагрузись и проверь.'
        }
    } catch {
        Write-Bad "Шрифт не поставился: $($_.Exception.Message)"
        Write-Host '  Скачай вручную: https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
    }
} else {
    Write-Bad 'Шрифта нет, и winget недоступен.'
    Write-Host '  Скачай вручную: https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
}

# --- 3. Бэкап и настройки -------------------------------------------------

# Терминал НЕ закрываем — в отличие от Sublime, он не перезапишет настройки
# при выходе: он следит за settings.json и перечитывает его сам, на лету.
# Да и закрывать его нельзя: этот скрипт обычно выполняется внутри него же,
# и закрытие убило бы сам скрипт на середине.
if (Get-Process WindowsTerminal -ErrorAction SilentlyContinue) {
    Write-Step 'Терминал запущен — настройки подхватятся сами, закрывать не нужно'
}

$settingsPath = Get-SettingsPath
$settingsDir  = Split-Path $settingsPath -Parent
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }

if (Test-Path $settingsPath) {
    $stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backup    = Join-Path $settingsDir "settings_backup_$stamp.json"
    Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
    Write-Ok "Бэкап прежних настроек: $backup"
} else {
    Write-Ok 'Прежних настроек не было — бэкап не нужен'
}

Install-Settings -Destination $settingsPath
Write-Ok 'Настройки на месте'

# --- Итог -----------------------------------------------------------------

Write-Host ''
Write-Host 'Готово.' -ForegroundColor Green
Write-Host ''
Write-Host "  Настройки : $settingsPath"
Write-Host "  Шрифт     : $FontFamily"
Write-Host ''
Write-Host 'Настройки подхватятся сами — открытые окна терминала перечитывают файл на лету.'
Write-Host ''

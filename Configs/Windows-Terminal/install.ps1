#Requires -Version 5.1
<#
    Полная настройка Windows Terminal + Fastfetch из репозитория Setup.

    Одной командой (PowerShell):
        Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Windows-Terminal/install.ps1" -OutFile $env:TEMP\wt-setup.ps1; & $env:TEMP\wt-setup.ps1

    Или из клона репозитория:
        .\install.ps1

    Что делает:
      1. Ставит Windows Terminal через winget, если его нет.
      2. Ставит шрифт JetBrainsMono Nerd Font, если его нет.
      3. Ставит Fastfetch через winget, если его нет.
      4. Кладёт конфиг Fastfetch и ASCII-арт в %USERPROFILE%\.config\fastfetch.
      5. Добавляет блок в профиль PowerShell — в тот, который уже есть на машине.
      6. Делает бэкап settings.json и кладёт настройки терминала.

    Ничего не затирается: конфиг терминала бэкапится, а в профиль PowerShell
    дописывается помеченный блок, чужое содержимое остаётся на месте.

    Файл сохранён с BOM: без него PowerShell 5.1 читает кириллицу как ANSI
    и портит все строки при запуске скрипта по пути.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Base = 'https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Windows-Terminal'

# Имя семейства шрифта, как его видит Windows. По нему проверяем, стоит ли шрифт.
$FontFamily = 'JetBrainsMono NFM'

# Метки блока, который скрипт дописывает в профиль PowerShell.
$MarkerStart = '# >>> Setup: fastfetch >>>'
$MarkerEnd   = '# <<< Setup: fastfetch <<<'

# Заголовки, которые стояли в файле-блоке выше метки до 16.10.2026. Из-за них
# каждый запуск добавлял в профиль ещё одну копию; строки с таким началом
# вычищаются при установке.
$LegacyHeaders = @(
    '# Профиль PowerShell: UTF-8 + Fastfetch.',
    '# Блок ниже добавлен установщиком из репозитория Setup.'
)

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

# Берёт файл из клона репозитория рядом со скриптом, иначе из сети.
function Install-RepoFile {
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

# Ищет, в какой профиль PowerShell дописывать блок.
#  1. Профиль, который уже правил этот скрипт (по метке) — чтобы не завести второй.
#  2. Любой существующий профиль — чтобы fastfetch не запускался дважды.
#  3. Если профилей нет — тот, что указан в гайде.
#
# $PROFILE может оказаться пустым: например, если папка «Документы» перенесена
# на другой диск или недоступна. Тогда собираем путь сами.
function Get-ProfilePath {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
    $psDir = Join-Path $docs 'WindowsPowerShell'

    $allHosts    = if ($PROFILE.CurrentUserAllHosts)    { $PROFILE.CurrentUserAllHosts }
                   else { Join-Path $psDir 'profile.ps1' }
    $currentHost = if ($PROFILE.CurrentUserCurrentHost) { $PROFILE.CurrentUserCurrentHost }
                   else { Join-Path $psDir 'Microsoft.PowerShell_profile.ps1' }

    foreach ($p in @($allHosts, $currentHost)) {
        if ($p -and (Test-Path $p) -and (Test-Path $p -PathType Leaf)) {
            if ((Read-TextFile -Path $p) -like "*$MarkerStart*") { return $p }
        }
    }
    foreach ($p in @($allHosts, $currentHost)) {
        if ($p -and (Test-Path $p -PathType Leaf)) { return $p }
    }
    return $currentHost
}

# Читает текстовый файл как UTF-8, не полагаясь на кодировку по умолчанию.
# Get-Content в PowerShell 5.1 читает UTF-8 без BOM как ANSI и портит
# кириллицу — а чужие профили вполне могут быть в UTF-8 без BOM.
function Read-TextFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    # Снимаем BOM, если он есть.
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    try {
        return [Text.Encoding]::GetEncoding('utf-8', [Text.EncoderFallback]::ExceptionFallback,
                                            [Text.DecoderFallback]::ExceptionFallback).GetString($bytes)
    } catch {
        # Не UTF-8 — значит файл в другой кодировке, читаем как есть.
        return [IO.File]::ReadAllText($Path)
    }
}

# Дописывает блок в профиль, сохраняя всё, что там было.
function Install-ProfileBlock {
    param([string]$Path, [string]$Block)

    if (-not $Path) { throw 'Не удалось определить путь к профилю PowerShell.' }

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $existing = @()
    if (Test-Path $Path -PathType Leaf) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        Copy-Item -LiteralPath $Path -Destination "$Path.backup_$stamp" -Force
        $existing = @((Read-TextFile -Path $Path) -split "`r?`n")
    }

    # Выкидываем прежний блок этого скрипта, если он там уже был, — чтобы
    # повторный запуск обновлял блок, а не плодил копии.
    #
    # Вместе с блоком убираем и осиротевшие строки-заголовки от прежних версий
    # файла: раньше заголовок стоял ВЫШЕ метки и потому не вырезался, а каждый
    # запуск добавлял ещё одну копию. На живом профиле их накопилось четыре.
    # Строки-заголовки узнаём по началу строки и убираем только перед меткой,
    # чтобы не тронуть похожий текст в чужом коде ниже.
    $kept = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($line in $existing) {
        if ($line.Contains($MarkerStart)) { $inside = $true;  continue }
        if ($line.Contains($MarkerEnd))   { $inside = $false; continue }
        if ($inside) { continue }
        $t = $line.TrimStart()
        $isLegacy = $false
        foreach ($h in $LegacyHeaders) { if ($t -like "$h*") { $isLegacy = $true; break } }
        if ($isLegacy) { continue }
        $kept.Add($line)
    }

    # Хвостовые пустые строки убираем, потом ставим один разделитель.
    while ($kept.Count -gt 0 -and $kept[$kept.Count - 1].Trim() -eq '') {
        $kept.RemoveAt($kept.Count - 1)
    }
    if ($kept.Count -gt 0) { $kept.Add('') }

    $lines = @($kept) + @($Block -split "`r?`n")
    $text  = ($lines -join "`r`n").TrimEnd() + "`r`n"

    # UTF-8 с BOM: без него PowerShell 5.1 читает кириллицу как ANSI.
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($true)))
}

Write-Host ''
Write-Host 'Windows Terminal + Fastfetch: установка настроек' -ForegroundColor Cyan
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

# --- 3. Fastfetch ---------------------------------------------------------

Write-Step 'Проверяю Fastfetch...'

if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    Write-Ok 'Fastfetch уже стоит'
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Step 'Fastfetch не найден — ставлю через winget...'
    try {
        & winget install --id Fastfetch-cli.Fastfetch --exact `
            --accept-package-agreements --accept-source-agreements --silent | Out-Null
        if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
            Write-Ok 'Fastfetch поставлен'
        } else {
            Write-Bad 'winget отработал, но fastfetch не появился. Перезапусти терминал и проверь.'
        }
    } catch {
        Write-Bad "Fastfetch не поставился: $($_.Exception.Message)"
        Write-Host '  Скачай вручную: https://github.com/fastfetch-cli/fastfetch/releases'
    }
} else {
    Write-Bad 'Fastfetch не найден, и winget недоступен.'
    Write-Host '  Скачай вручную: https://github.com/fastfetch-cli/fastfetch/releases'
}

# --- 4. Конфиг Fastfetch --------------------------------------------------

$ffDir = Join-Path $env:USERPROFILE '.config\fastfetch'
New-Item -ItemType Directory -Path $ffDir -Force | Out-Null

# Бэкап прежнего конфига, если он был.
foreach ($name in @('config.jsonc', 'ascii.txt')) {
    $old = Join-Path $ffDir $name
    if (Test-Path $old) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        Copy-Item -LiteralPath $old -Destination "$old.backup_$stamp" -Force
    }
}

Install-RepoFile -RelativePath 'Fastfetch\config.jsonc' `
                 -UrlPath 'Fastfetch/config.jsonc' `
                 -Destination (Join-Path $ffDir 'config.jsonc')

Install-RepoFile -RelativePath 'Fastfetch\ascii.txt' `
                 -UrlPath 'Fastfetch/ascii.txt' `
                 -Destination (Join-Path $ffDir 'ascii.txt')

Write-Ok "Конфиг Fastfetch: $ffDir"

# --- 5. Профиль PowerShell ------------------------------------------------

$profilePath = Get-ProfilePath

# Блок берём из файла репозитория: он же кладётся в профиль как есть.
$blockFile = Join-Path $env:TEMP ("wt-block-" + (Get-Random) + '.ps1')
try {
    Install-RepoFile -RelativePath 'Fastfetch\profile.ps1' `
                     -UrlPath 'Fastfetch/profile.ps1' `
                     -Destination $blockFile
    $block = Read-TextFile -Path $blockFile
} finally {
    Remove-Item $blockFile -Force -ErrorAction SilentlyContinue
}

Install-ProfileBlock -Path $profilePath -Block $block
Write-Ok "Профиль PowerShell: $profilePath"

# --- 6. Настройки терминала -----------------------------------------------

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
    $stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backup = Join-Path $settingsDir "settings_backup_$stamp.json"
    Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
    Write-Ok "Бэкап прежних настроек: $backup"
} else {
    Write-Ok 'Прежних настроек не было — бэкап не нужен'
}

Install-RepoFile -RelativePath 'settings.json' `
                 -UrlPath 'settings.json' `
                 -Destination $settingsPath
Write-Ok 'Настройки на месте'

# --- Итог -----------------------------------------------------------------

Write-Host ''
Write-Host 'Готово.' -ForegroundColor Green
Write-Host ''
Write-Host "  Настройки : $settingsPath"
Write-Host "  Шрифт     : $FontFamily"
Write-Host "  Fastfetch : $ffDir"
Write-Host "  Профиль   : $profilePath"
Write-Host ''
Write-Host 'Открой новый терминал — картинка и тема уже должны быть на месте.'
Write-Host ''

# Setup

- 💿 [Образы Windows](Windows-Images)
- 🪟 [Настройка Windows](Windows-Setup)
- 🐧 [WSL](WSL)
- 📦 [Программы](Programs)
- ⚙️ [Конфиги](Configs)
- 🖼 [Обои](Wallpapers)

Это не гайды и не сборник инструкций — просто сложенное в одном месте, чтобы
не искать.

## Что в разделах

| Раздел | Что внутри |
|---|---|
| 💿 Образы Windows | Оригинальные ISO с серверов Microsoft, без сборок с торрентов |
| 🪟 Настройка Windows | Активация, драйверы и оптимизация |
| 🐧 WSL | Linux внутри Windows |
| 📦 Программы | Полезности |
| ⚙️ Конфиги | Ого настройки |
| 🖼 Обои | Прикинь |

## Установка одной командой

Для конфигов есть установщики: скачивают настройки из репозитория, ставят
зависимости и делают бэкап того, что было. Запускать в PowerShell.

**Windows Terminal** — тема Catppuccin Mocha, шрифт JetBrainsMono Nerd Font,
Fastfetch с ASCII-артом при запуске. Ставит Terminal, шрифт и Fastfetch через
`winget`, если их нет.

```powershell
irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Windows-Terminal/install.ps1" -OutFile $env:TEMP\wt-setup.ps1; & $env:TEMP\wt-setup.ps1
```

**Sublime Text** — тема Aura, шрифт Consolas, подсветка Markdown. Ставит
редактор и все пакеты.

```powershell
irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Sublime-Text/install.ps1" -OutFile $env:TEMP\sublime-setup.ps1; & $env:TEMP\sublime-setup.ps1
```

Оба скрипта можно запускать повторно — они обновляют настройки, а прежние
сохраняют рядом с меткой времени. Подробности и разбор ошибок — в README
соответствующего раздела.

## Если скрипты не запускаются

PowerShell по умолчанию запрещает выполнение скачанных скриптов. Разрешить
для текущего пользователя:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

`irm` не распознан — значит, открыта старая командная строка (`cmd.exe`)
вместо PowerShell. Win+X → «Терминал».


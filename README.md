# Setup

- 💿 [Образы Windows](Windows-Images)
- 🪟 [Настройка Windows](Windows-Setup)
- 🐧 [WSL](WSL)
- 📦 [Программы](Programs)
- ⚙️ [Конфиги](Configs)
- 🤖 [Claude Code](Claude-Code)
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
| 🤖 Claude Code | Claude Code через локальный прокси: терминал и браузер |
| 🖼 Обои | Прикинь |

## Установка одной командой

Для конфигов есть установщики: скачивают настройки из репозитория, ставят
зависимости и делают бэкап того, что было. Windows-скрипты — в PowerShell,
Claude Code — в WSL.

**Windows Terminal** — тема Catppuccin Mocha, шрифт JetBrainsMono Nerd Font,
Fastfetch с ASCII-артом при запуске. Ставит Terminal, шрифт и Fastfetch через
`winget`, если их нет.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Windows-Terminal/install.ps1" -OutFile $env:TEMP\wt-setup.ps1; & $env:TEMP\wt-setup.ps1
```

**Sublime Text** — тема Aura, шрифт Consolas, подсветка Markdown. Ставит
редактор и все пакеты.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Sublime-Text/install.ps1" -OutFile $env:TEMP\sublime-setup.ps1; & $env:TEMP\sublime-setup.ps1
```

**Claude Code** — терминальный Claude Code и чат в браузере с доступом к
машине. Надстройка над [zim-claude](https://github.com/Mr-Destroyer/zim-claude):
ставит пакеты, Docker, cptr, Open WebUI и ярлыки на рабочем столе. Ключ Token
Juice спросит при установке. Запускать в WSL Ubuntu.

```bash
cd ~
curl -fsSL https://github.com/Hayden-Wright/Setup/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=2 --one-top-level=zim-setup Setup-main/Claude-Code
cd zim-setup
./install-stack.sh
```

Оба скрипта можно запускать повторно — они обновляют настройки, а прежние
сохраняют рядом с меткой времени. Подробности и разбор ошибок — в README
соответствующего раздела.

## Если скрипты не запускаются

Первая часть команд PowerShell выше снимает запрет на время работы окна. Если
запускаешь скрипт иначе, добавь её перед запуском:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

Так команда действует только внутри текущего окна PowerShell: закроешь его —
политика вернётся к прежней. На свежей Windows политика `Restricted`, и без
этого запуск падает с «выполнение сценариев отключено в этой системе».

Установщик терминала дополнительно ставит `RemoteSigned` для твоего
пользователя: он дописывает профиль PowerShell, а при `Restricted` тот не
загружается, и ошибка вылезает в каждом новом окне. Для Sublime это не нужно —
он профиль не трогает.

`irm` не распознан — значит, открыта старая командная строка (`cmd.exe`)
вместо PowerShell. Win+X → «Терминал».

`curl` или `tar` не найден при установке Claude Code — значит, команда
запущена в PowerShell, а не в WSL Ubuntu.


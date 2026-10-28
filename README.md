# Setup

- 💿 [Образы Windows](Windows-Images)
- 🪟 [Настройка Windows](Windows-Setup)
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
| 📦 Программы | Полезности |
| ⚙️ Конфиги | Ого настройки |
| 🖼 Обои | Прикинь |

## Установка одной командой

Для конфигов есть установщики: скачивают настройки из репозитория, ставят
зависимости и делают бэкап того, что было. Оба — в PowerShell, Windows.

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

Оба установщика можно запускать повторно — они обновляют настройки, а прежние
сохраняют рядом с меткой времени. Подробности и разбор ошибок — в README
соответствующего раздела.

## Агент

**[deploychan](Configs/Agents)** — MCP-каталог знаний, скиллов и маршрутов
прокачки для кодинг-агента. Бесплатно, без ключей, ставить нечего: открой
[mcp.deploychan.webcam](https://mcp.deploychan.webcam) в агентной сессии и
скажи «подключи» — остальное агент сделает сам.

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


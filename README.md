# Setup

- 💿 [Образы Windows](Образы%20Windows)
- 🪟 [Настройка Windows](Настройка%20Windows)
- 🐧 [WSL](WSL)
- 📦 [Программы](Программы)
- ⚙️ [Конфиги](Конфиги)
- 🖼 [Обои](Обои)

Мой личный архив: конфиги, программы и заметки по настройке Windows и WSL.
Всё, что я ставлю и настраиваю на новой системе, лежит здесь.

Это не гайды и не сборник инструкций — просто сложенное в одном месте, чтобы
не искать заново. Где настройка сводится к одной команде, есть установщик;
где нет — короткая заметка.

## Что в разделах

| Раздел | Что внутри |
|---|---|
| 💿 Образы Windows | оригинальные ISO с серверов Microsoft, без сборок с торрентов |
| 🪟 Настройка Windows | активация, драйверы, оптимизация, мелочи вроде InputSwitch |
| 🐧 WSL | установка Linux внутри Windows |
| 📦 Программы | что у меня стоит, по категориям |
| ⚙️ Конфиги | Windows Terminal и Sublime Text — вместе с установщиками |
| 🖼 Обои | где беру обои |

## Установка одной командой

Для конфигов есть установщики: скачивают настройки из репозитория, ставят
зависимости и делают бэкап того, что было. Запускать в PowerShell.

**Windows Terminal** — тема Catppuccin Mocha, шрифт JetBrainsMono Nerd Font,
Fastfetch с ASCII-артом при запуске. Ставит Terminal, шрифт и Fastfetch через
`winget`, если их нет.

```powershell
irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Windows%20Terminal/install.ps1" -OutFile $env:TEMP\wt-setup.ps1; & $env:TEMP\wt-setup.ps1
```

**Sublime Text** — тема Aura, шрифт Consolas, подсветка Markdown. Ставит
редактор и все пакеты.

```powershell
irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Sublime%20Text/install.ps1" -OutFile $env:TEMP\sublime-setup.ps1; & $env:TEMP\sublime-setup.ps1
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

## Структура

Папки названы по-русски, навигация — через README в каждой из них.
Нумерации нет: порядок задаёт список в самом верху.

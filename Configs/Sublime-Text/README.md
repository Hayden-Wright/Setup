Тема Aura (soft), шрифт Consolas 10, подсветка Markdown.

![](screenshot.png)

## Установка одной командой

Открой PowerShell (Win+X → «Терминал») и вставь:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Sublime-Text/install.ps1" -OutFile $env:TEMP\sublime-setup.ps1; & $env:TEMP\sublime-setup.ps1
```

Первая часть (`Set-ExecutionPolicy ... -Scope Process`) нужна на свежей
Windows: там политика `Restricted`, и без неё запуск скрипта падает с
«выполнение сценариев отключено в этой системе». `-Scope Process` действует
только внутри этого окна PowerShell и ничего в системе не меняет — закроешь
окно, и всё как было.

Больше ничего делать не нужно: скрипт сам поставит Sublime Text (если его нет),
закроет запущенный редактор, сделает бэкап старых настроек, положит конфиги с
темой и поставит все пакеты. В конце напишет `Готово.`

## Что именно он делает

1. **Ищет Sublime Text.** Если не находит — ставит через `winget`.
2. **Закрывает редактор**, если тот открыт. Это обязательно: Sublime записывает
   настройки на диск при выходе и затрёт то, что мы только что положили.
   Несохранённые вкладки не пропадут — редактор восстановит их при следующем запуске.
3. **Делает бэкап** текущих `User` и `AuraTheme` в
   `%APPDATA%\Sublime Text\Packages_backup_ГГГГ-ММ-ДД_ЧЧ-ММ-СС`.
4. **Кладёт настройки**: `Preferences.sublime-settings`, `Markdown.sublime-settings`,
   `Package Control.sublime-settings` и тему `aura-theme-soft.tmTheme`.
5. **Добавляет в контекстное меню** пункт «Open with Sublime Text» — правая
   кнопка на любом файле. Пишется в профиль пользователя, права администратора
   не нужны.
6. **Ставит пакеты**: Package Control, MarkdownEditing, Markdown Extended.

## Как проверить, что всё получилось

Открой Sublime Text и посмотри:

- **Тема.** Фон тёмно-синий, а не серый стандартный. Если фон серый — тема не встала.
- **Markdown.** Открой любой `.md` файл: заголовки, ссылки и код должны быть
  разноцветными. Синтаксис переключается через `View` → `Syntax` → `Markdown`.
- **Пакеты.** `Ctrl+Shift+P` → набери `Install Package` — если команда есть,
  Package Control на месте.
- **Контекстное меню.** Правая кнопка на любом файле — там должен быть пункт
  «Open with Sublime Text».

Настройки лежат в `%APPDATA%\Sublime Text\Packages\User`. Быстро открыть эту
папку: в Sublime `Preferences` → `Browse Packages…`.

## Если что-то пошло не так

**`irm` не распознан / команда не найдена.**
Ты в старой командной строке (`cmd.exe`) вместо PowerShell. Открой именно
PowerShell: Win+X → «Терминал», или `Win+R` → `powershell`.

**«выполнение сценариев отключено в этой системе».**
Так и должно быть на свежей Windows — политика там `Restricted`. Команда в
разделе «Установка» уже снимает это на время работы окна. Если запускаешь
скрипт иначе, добавь перед ним:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

Это действует только внутри текущего окна PowerShell: закроешь его — политика
вернётся к прежней. Менять настройку навсегда (`-Scope CurrentUser`) не нужно.

**Sublime не закрылся сам.**
Закрой его вручную (сохранив что нужно) и запусти команду снова.

**Не ставится какой-то пакет** (нет интернета, упал GitHub).
Скрипт напишет `[!] ... не поставился`, но остальное поставит. Пакеты можно
добавить позже вручную: `Ctrl+Shift+P` → `Install Package` → имя пакета.

**Хочу откатить всё назад.**
Скопируй содержимое папки `Packages_backup_...` обратно в
`%APPDATA%\Sublime Text\Packages`.

## Установка из клона репозитория

Если репозиторий уже склонирован, интернет не нужен — скрипт возьмёт конфиги
из папки рядом с собой:

```powershell
cd "путь\к\Setup\Configs\Sublime-Text"
.\install.ps1
```

## Вручную, без скрипта

1. Поставить [Sublime Text](https://www.sublimetext.com/download).
2. `Preferences` → `Browse Packages…`.
3. Скопировать туда папки `Packages/User` и `Packages/AuraTheme` из этого репозитория.
4. Поставить [Package Control](https://packagecontrol.io/installation).
5. `Ctrl+Shift+P` → `Install Package` → **MarkdownEditing**, **Markdown Extended**.
6. Пункт «Open with Sublime Text» в контекстном меню — примени `.reg` ниже.

### Пункт в контекстном меню

Сохрани это в файл `open-with-sublime.reg` и запусти двойным щелчком.
Поправь путь, если Sublime стоит не в `Program Files`. Права администратора
не нужны — ключ пишется в профиль пользователя.

```reg
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Sublime Text]
@="Open with Sublime Text"
"Icon"="C:\\Program Files\\Sublime Text\\sublime_text.exe,0"

[HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Sublime Text\command]
@="\"C:\\Program Files\\Sublime Text\\sublime_text.exe\" \"%1\""
```

Пишем в `HKEY_CURRENT_USER`, а не в `HKEY_CLASSES_ROOT` как обычно в готовых
`.reg` из интернета: для проводника это одно и то же, но HKCU не требует прав
администратора и не трогает другие учётные записи. Откатить — удалить эту
ветку в `regedit`.

Если при запуске выскочило «The specified file is not a registry file» —
файл сохранён в UTF-8, а `reg import` понимает только UTF-16 или ANSI. В
Блокноте: `Файл` → `Сохранить как` → кодировка **Unicode** (это UTF-16 LE).

## Полезно знать

- `Ctrl+0` — сбросить случайно увеличенный шрифт (`Ctrl+колесо`, `Ctrl+=`, `Ctrl+-`).
- Перенос строк включается в `Preferences` → `Settings`:
  `"word_wrap": true` и `"wrap_width": 0` (перенос по ширине окна).

## Файлы

| Путь | Что это |
|---|---|
| `Packages/User/Preferences.sublime-settings` | шрифт, тема, цветовая схема |
| `Packages/User/Markdown.sublime-settings` | настройки Markdown |
| `Packages/User/Package Control.sublime-settings` | список пакетов |
| `Packages/AuraTheme/aura-theme-soft.tmTheme` | тема Aura (ставится вручную, не из Package Control) |
| `install.ps1` | установщик |

Тема Aura лежит в репозитории намеренно: она не стоит из Package Control, а
подключена по пути `Packages/AuraTheme/...`. Без этого файла Sublime молча
откатится на стандартную цветовую схему.

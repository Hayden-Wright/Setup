# Sublime Text

Тема Aura (soft), шрифт Consolas 10, подсветка Markdown.

![](screenshot.png)

## Как поставить

Одной командой в PowerShell:

```powershell
irm "https://raw.githubusercontent.com/Hayden-Wright/setup/main/3.%20%D0%9A%D0%BE%D0%BD%D1%84%D0%B8%D0%B3%D0%B8/Sublime%20Text/install.ps1" | iex
```

Скрипт скачает настройки и тему, сделает бэкап старых и поставит Package Control.

Потом открыть Sublime — он сам доустановит **MarkdownEditing** и **Markdown Extended**.

## Вручную

1. Поставить [Sublime Text](https://www.sublimetext.com/download).
2. `Preferences` → `Browse Packages…`.
3. Скопировать туда папки `Packages/User` и `Packages/AuraTheme`.
4. Поставить [Package Control](https://packagecontrol.io/installation).
5. `Ctrl+Shift+P` → `Install Package` → **MarkdownEditing**, **Markdown Extended**.

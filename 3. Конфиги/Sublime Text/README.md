# Sublime Text

Настройки редактора: шрифт Consolas 10, перенос строк, тёмная тема Aura (soft),
подсветка Markdown.

## Что внутри

| Путь | Что это |
|---|---|
| `Packages/User/Preferences.sublime-settings` | основные настройки: шрифт, тема, цветовая схема |
| `Packages/User/Markdown.sublime-settings` | настройки Markdown |
| `Packages/User/Package Control.sublime-settings` | список пакетов — по нему они доустановятся сами |
| `Packages/AuraTheme/aura-theme-soft.tmTheme` | тема Aura, установлена вручную (не из Package Control) |

Пакеты, которые подтянет Package Control: **MarkdownEditing**, **Markdown Extended**.

## Как поставить

Автоматически — из PowerShell:

```powershell
.\install.ps1
```

Скрипт сделает бэкап текущих настроек, скопирует конфиги и тему, и напомнит
доустановить пакеты.

Вручную:

1. Поставить [Sublime Text](https://www.sublimetext.com/download).
2. `Preferences` → `Browse Packages…` — откроется папка `Packages`.
3. Скопировать туда `Packages/User` и `Packages/AuraTheme` из этого репозитория.
4. Открыть Sublime: `Ctrl+Shift+P` → `Install Package Control` (если ещё нет).
5. `Ctrl+Shift+P` → `Install Package` → поставить **MarkdownEditing** и
   **Markdown Extended** (можно просто дождаться предложения Package Control —
   он видит список в `Package Control.sublime-settings`).

## Настройки

```json
{
    "font_face": "Consolas",
    "font_size": 10,
    "line_padding_top": 1,
    "line_padding_bottom": 1,
    "ui_scale": 1.0,
    "theme": "Adaptive.sublime-theme",
    "color_scheme": "Packages/AuraTheme/aura-theme-soft.tmTheme",
    "ignored_packages": ["Vintage"],
    "index_files": true
}
```

Полезно помнить:

- `Ctrl+0` — сбросить случайный зум шрифта (`Ctrl+колесо`, `Ctrl+=`, `Ctrl+-`).
- `Ctrl+Shift+P` → `Markdown Preview` — рендер Markdown в браузере.

## Если тема не применилась

Цветовая схема подключена по пути `Packages/AuraTheme/aura-theme-soft.tmTheme`.
Если файл не скопирован, Sublime молча откатится на дефолтную схему. Проверить:
`Preferences` → `Browse Packages…` → папка `AuraTheme` должна содержать
`aura-theme-soft.tmTheme`.

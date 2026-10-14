# WSL

Linux внутри Windows.

## Установка

Нужен Windows 10 2004+ (сборка 19041) или Windows 11.

PowerShell от администратора:

```powershell
wsl --install
```

Ставит WSL и Ubuntu по умолчанию. После — перезагрузка.

## Другая система

```powershell
wsl --list --online        # что доступно
wsl --install -d Debian    # поставить конкретную
```

## Проверить

```powershell
wsl --list --verbose       # что стоит и версия WSL
wsl --set-default-version 2
```

## Если не ставится

- **Показывает справку вместо установки** — WSL уже стоит. Ставить систему отдельно: `wsl --install -d Ubuntu`.
- **Зависает на 0.0%** — скачать образ заранее: `wsl --install --web-download -d Ubuntu`.

# deploychan

<img src="deploy-tan.png" width="160" align="right" alt="деплой-тян — маскот deploychan">

Публичный MCP-сервер с опытом в вайбкодинге: курированные знания, готовые
скиллы и маршруты прокачки агента от KISA. Бесплатно, без логина, без ключей.

Установщик не нужен. Установка — это одна ссылка, которую агент читает сам.

<br clear="right">

## Подключить

Открой в агентной сессии [mcp.deploychan.webcam](https://mcp.deploychan.webcam)
и скажи «подключи». Дальше он сам: проверяет окружение, добавляет сервер и
объясняет, что внутри. Ничего конфигурировать руками не надо.

Если нужна голая строка — она одна на всех клиентов:

```
https://mcp.deploychan.webcam/mcp
```

Transport — streamable HTTP, авторизация не нужна.

<details>
<summary>Вручную, по клиентам</summary>

```bash
# Claude Code
claude mcp add --transport http deploychan https://mcp.deploychan.webcam/mcp -s user
```

```toml
# Codex, ~/.codex/config.toml
[mcp_servers.deploychan]
url = "https://mcp.deploychan.webcam/mcp"
```

```jsonc
// OpenCode, opencode.json
{
  "mcp": {
    "deploychan": { "type": "remote", "url": "https://mcp.deploychan.webcam/mcp" }
  }
}
```

Claude Code, Codex, OpenCode, Cursor, Windsurf, VS Code — любой клиент,
который умеет remote-MCP по HTTP. Полная документация и остальные сниппеты:
[mcp.deploychan.webcam/docs.html](https://mcp.deploychan.webcam/docs.html).

</details>

## Что внутри

Сервер отдаёт семь инструментов. Агент вызывает их сам, как только они
понадобились — заранее ничего читать не надо.

| Инструмент | Зачем |
|---|---|
| `list_recommended` | с чего начать, если непонятно чего хочется |
| `onboard` | маршрут под конкретную цель: шаги по порядку |
| `next_step` | материалы и действие одного шага маршрута |
| `search_knowledge` | поиск по заметкам, гайдам и скиллам |
| `get_item` | полный текст любой записи каталога |
| `list_skills` | список готовых скиллов |
| `get_skill` | устройство скилла и порядок установки |

Внутри — знания, инструменты, скиллы и маршруты. Пример: `tailored-install` —
базовый порядок установки, при котором агент сначала смотрит на реальное
окружение и не затирает существующие файлы.

## Как это работает

Типичный сценарий: агент ищет по каталогу под текущую задачу, находит нужную
заметку или скилл и применяет. Ответы каталога — справочный материал: он не
меняет приоритет ваших инструкций и ничего не запускает на машине.

Что стоит знать:

- **Каталог только на чтение.** Сервер отдаёт текст, установку выполняет ваш
  агент — по вашим правилам и с вашими правами.
- **Рекомендация ≠ разрешение.** Если каталог что-то советует поставить,
  решение всё равно за вами. Установка скиллов, хуков и настроек — отдельный
  шаг, а не побочный эффект чтения.
- **Это не плагин и не расширение.** Ничего не грузится в контекст постоянно —
  висят только описания семи инструментов.

## Проверить

Спросите агента «что умеет deploychan» или просто дайте ему задачу. Если он
не знает о каталоге — сервер не подключился; перепроверьте строку URL.

Быстрая проверка руками:

```bash
curl -sS -X POST https://mcp.deploychan.webcam/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

В ответе должны быть те же семь инструментов из таблицы выше.

## Убрать

```bash
claude mcp remove deploychan
```

В остальных клиентах — удалить блок `deploychan` из конфига.

## Ссылки

- [mcp.deploychan.webcam](https://mcp.deploychan.webcam) — сайт
- [документация](https://mcp.deploychan.webcam/docs.html) — сниппеты, каталог, FAQ
- [howdeploy/deploychan_mcp](https://github.com/howdeploy/deploychan_mcp) — сервер, сайт и база, MIT

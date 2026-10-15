MCP-сервер с подборкой знаний и готовых скиллов для агентов. Публичный,
read-only, без регистрации и ключей.

```
https://mcp.deploychan.webcam/mcp
```

## Claude Code

```bash
claude mcp add --transport http deploychan https://mcp.deploychan.webcam/mcp
```

Проверить: `claude mcp list`.

## Codex

`~/.codex/config.toml`:

```toml
[mcp_servers.deploychan]
url = "https://mcp.deploychan.webcam/mcp"
transport = "http"
```

## Другие

В `mcp.json`:

```json
{
  "mcpServers": {
    "deploychan": {
      "type": "http",
      "url": "https://mcp.deploychan.webcam/mcp"
    }
  }
}
```

Транспорт — Streamable HTTP, так что подойдёт любому клиенту, который его
понимает.

## Что отдаёт

Четыре группы инструментов: поиск по знаниям, готовые скиллы, маршруты
прокачки по шагам и список рекомендованного.

- **[deploychan](https://mcp.deploychan.webcam)** — сайт
- **[deploychan_mcp](https://github.com/howdeploy/deploychan_mcp)** — исходники, MIT

![](deploy-tan.png)

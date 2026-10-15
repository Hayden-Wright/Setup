MCP-сервер с подборкой знаний и готовых скиллов для агентов. Публичный,
read-only, без регистрации и ключей.

```bash
claude mcp add --transport http deploychan https://mcp.deploychan.webcam/mcp
```

Проверить, что подключился:

```bash
claude mcp list
```

Отдаёт четыре группы инструментов: поиск по знаниям, готовые скиллы, маршруты
прокачки по шагам и список рекомендованного.

- **[deploychan](https://mcp.deploychan.webcam)** — сайт
- **[deploychan_mcp](https://github.com/howdeploy/deploychan_mcp)** — исходники, MIT

![](deploy-tan.png)

# Claude Code

## Установка

В WSL Ubuntu:

```bash
cd ~
curl -fsSL https://github.com/Hayden-Wright/Setup/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=2 --one-top-level=zim-setup Setup-main/Claude-Code
cd zim-setup
./install-stack.sh
```

Ключ Token Juice спросит установщик (ввод скрыт). Для неинтерактивной
установки — `ZIM_CLAUDE_TOKEN=tj_… ./install-stack.sh`.

Прервётся один раз, и это нормально: после установки Docker (закрой терминал,
открой заново и запусти снова).

Браузерного чата (Open WebUI + cptr) в наборе больше нет: его заменил Claude
Desktop, который работает напрямую с шлюзом на `:4002`. Настройка приложения —
в README `zim-claude`, раздел «Claude Desktop — the `zim` gateway».

## Если что-то не так

**`Package 'docker.io' has no installation candidate`.** Скрипт лечит сам:
включает компонент `universe` и пробует снова. Вручную:

```bash
sudo add-apt-repository -y universe && sudo apt update
sudo apt install -y docker.io
```

**Терминал завис на «Handling...».** Не поднят прокси `:4000`:

```bash
~/.local/bin/start-litellm.sh status
~/.local/bin/start-litellm.sh restart
```

**Веб-поиск не работает (Claude Code или Claude Desktop отвечает ошибкой на
`web_search`).** Нужен SearxNG — движок, через который прокси ищет сам:

```bash
docker ps --format '{{.Names}}' | grep searxng || docker start searxng
curl -sf 'http://127.0.0.1:8888/search?q=test&format=json' >/dev/null && echo ok
```

**Остался старый Open WebUI / cptr.** Набор их больше не ставит и не
поднимает. Удалить окончательно (история чатов в томе `open-webui` пропадёт):

```bash
docker rm -f open-webui
pkill -f cptr
rm -rf ~/.local/share/cptr-venv ~/start-cptr.sh   # ~/start-all.sh перезапишет Setup
```

**SearxNG не запускается.** Образ весит ~380 МБ и качается один раз:

```bash
docker pull searxng/searxng:latest
docker logs searxng
```

**Автообновление не срабатывает.** Смотри логи:

```bash
tail -20 ~/.local/share/zim-deploy/update.log
tail -20 ~/.local/share/zim-claude/update.log
```

`checkout has local changes` — в чекауте есть правки, обновление их не
трогает. `has diverged` — история разошлась. В обоих случаях разбираться
руками, force не жать.

**Ярлыки не создались.** Запусти скрипт вручную:

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\<user>\zim-setup\files\windows\create-shortcuts.ps1
```

**Нет статус-строки с процентом контекста.** Она появляется после перезапуска
Claude Code (читается при старте сессии). Проверить, что скрипт на месте:

```bash
ls -l ~/.claude/statusline.py
python3 -c 'import json; print(json.load(open("'"$HOME"'/.claude/settings.json"))["statusLine"])'
```

Если `statusLine` в конфиге свой (не `python3 ~/.claude/statusline.py`),
установщик его не перетирает — удали ключ и запусти `./deploy.sh` снова.

Вид строки: `~/проект │ ctx 34% (89k/262k)`. Цвет процента: зелёный до 50 %,
жёлтый до 75 %, дальше красный. Пустая сессия — `ctx —`.


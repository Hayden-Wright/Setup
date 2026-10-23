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

Прервётся дважды, и это нормально: после установки Docker (закрой терминал,
открой заново и запусти снова) и перед настройкой cptr (открой напечатанную
ссылку, зарегистрируйся, запусти снова).

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

**Веб-поиск отвечает только короткими сниппетами.** Контейнер Open WebUI
поднят не через `run-openwebui.sh`:

```bash
cd ~/.config/zim-claude/openwebui && ./run-openwebui.sh
```

**SearxNG не запускается.** Образ весит ~380 МБ и качается один раз:

```bash
docker pull searxng/searxng:latest
docker logs searxng
```

**В Open WebUI «No models available».** Проверь, что cptr отдаёт модель:

```bash
KEY=$(grep '^OPENAI_API_KEY=' ~/.config/zim-claude/openwebui/openwebui.env | cut -d= -f2)
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8100/v1/models
```

Пусто — у cptr нет рабочей папки: запусти `./install-stack.sh` ещё раз либо
открой `http://127.0.0.1:8100` и выбери папку. Модель есть, а в браузере
нет — `docker restart open-webui`.

**В чате «No API model connections configured».** У cptr нет пакета
`claude-agent-sdk`:

```bash
~/.local/share/cptr-venv/bin/pip install 'claude-agent-sdk>=0.1.62'
~/start-cptr.sh restart
```

**Обновил cptr — пропали картинки из чата.** Обновление затирает патчи:

```bash
PKG=$(ls -d ~/.local/share/cptr-venv/lib/python*/site-packages/cptr)
patch -p1 -d "$PKG" < ~/.config/zim-claude/patches/gateway-images.patch
patch -p1 -d "$PKG" < ~/.config/zim-claude/patches/config-multiline-toml.patch
~/start-cptr.sh restart
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


# Claude Code

Claude Code через локальный прокси: терминал и браузер, плюс агент с доступом
к диску. Надстройка над [zim-claude](https://github.com/Mr-Destroyer/zim-claude):
сам CLI и прокси ставит его `install.sh`, а здесь то, чего в нём нет.

## Установка

Одна команда. Скачивает только эту папку:

```bash
cd ~
curl -fsSL https://github.com/Hayden-Wright/Setup/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=2 --one-top-level=zim-setup Setup-main/Claude-Code
cd zim-setup
./install-stack.sh
```

Скрипт можно запускать сколько угодно раз: уже сделанное пропускает.

Прервётся дважды, и это нормально:

1. **После установки Docker** — закрой терминал, открой заново и запусти
   `./install-stack.sh` снова (нужно, чтобы применились права на Docker).
2. **Перед настройкой cptr** — скрипт напечатает ссылку вида
   `http://127.0.0.1:8100/?token=...`. Открой её, зарегистрируйся (логин и
   пароль локальные, никуда не уходят) и запусти скрипт ещё раз.

### Ключ Token Juice

Ключа в репозитории нет — его спрашивает `install.sh` из zim-claude при
установке (ввод скрыт). Свой ключ каждый берёт в
[личном кабинете Token Juice](https://tokenjuice.ai): оплата и лимиты у
каждого свои.

Для неинтерактивной установки ключ можно передать заранее:

```bash
ZIM_CLAUDE_TOKEN=tj_… ./install-stack.sh
```

## После установки

| Команда | Что |
|---|---|
| `zim-claude` | терминальный Claude Code |
| `http://127.0.0.1:3000` | чат в браузере |
| `zim-memory search "запрос"` | поиск по заметкам и истории |
| `~/start-all.sh` | поднять всё сразу после перезагрузки |

Ярлыки на рабочем столе:

| Ярлык | Что делает |
|---|---|
| **Claude Code** | поднимает весь стек и открывает `zim-claude` |
| **Claude Code - session** | новая независимая сессия, стек не трогает |
| **Claude Folder** | домашний каталог WSL в проводнике |

## Как это устроено

Две вещи, которые важно не перепутать:

- **`~/zim-claude`** — чекаут апстрима `Mr-Destroyer/zim-claude`. Он
  обновляется своим автообновлением по fast-forward. **Ничего своего мы в
  него не кладём:** любой наш файл внутри чужого репозитория рано или поздно
  упрётся в «untracked file would be overwritten», и обновления встанут
  навсегда.
- **`~/.config/zim-claude/`** — то, что принадлежит этому набору: конфиг
  Open WebUI, патчи cptr, настройки SearxNG.

| Путь | Что |
|---|---|
| `install-stack.sh` | ставит всё одной командой |
| `deploy.sh` | раскладывает файлы и настройки (без sudo, идемпотентен) |
| `files/` | конфиги, патчи, скрипты |
| `files/zim-deploy-update.sh` | автообновление набора |
| `files/setup-cptr.sh` | настройки cptr в его базу |
| `files/windows/create-shortcuts.ps1` | ярлыки на рабочем столе |

`deploy.sh` можно запускать отдельно — он не требует пароля и не трогает
Docker:

```bash
./deploy.sh            # установить / обновить
./deploy.sh --dry-run  # показать, что будет сделано
```

## Автообновление

Набор — надстройка, поэтому одного обновления апстрима мало: `install.sh`
из zim-claude переустанавливает своё и затирает то, что положено поверх
(первым делом — конфиг LiteLLM с перехватом веб-поиска). Поэтому обновление
идёт в три шага, и делает их `zim-deploy-update.sh`:

1. запускает обновление zim-claude (его собственные правила: fast-forward,
   отказ на грязном чекауте, свой лог);
2. подтягивает этот репозиторий так же — fast-forward, без merge и reset;
3. прогоняет `deploy.sh`, который возвращает доработки на место.

Запускается он сам:

- **при старте каждой сессии** — хук `SessionStart` в `~/.claude/settings.json`
  запускает его в фоне, поэтому старт не задерживается;
- **раз в сутки через cron** — на случай, если терминал неделю не открывали.

Сам себя ограничивает: не чаще раза в час, с `flock` (две сессии не будут
обновляться одновременно). Лог: `~/.local/share/zim-deploy/update.log`.

Проверить вручную:

```bash
zim-deploy-update.sh --now      # не ждать интервала
tail -20 ~/.local/share/zim-deploy/update.log
```

Отключить: `ZIM_DEPLOY_NO_UPDATE=1` в окружении, либо убрать хук из
`~/.claude/settings.json`, либо `ZIM_DEPLOY_AUTO_UPDATE=0` в
`~/.local/share/zim-deploy/update.conf`.

## Порты

| Порт | Что | Доступ |
|---|---|---|
| 4000 | LiteLLM для CLI | локально |
| 4002 | LiteLLM для Claude Desktop и агента cptr | локально |
| 8100 | cptr — веб-интерфейс агента | только 127.0.0.1 |
| 8888 | SearxNG | только 127.0.0.1 |
| 3000 | Open WebUI | все интерфейсы |

## Что меняется в Claude Code

`deploy.sh` правит `~/.claude/settings.json`, не затирая чужие ключи:

- `permissions.allow` — объединяется с тем, что уже есть (только чтение и
  базовые команды; `deny` не трогается);
- `hooks.SessionStart` — хук `~/.claude/zim-memory/hook-session-start.sh`,
  который доиндексирует память и запускает обновление набора.

Плюс подключается MCP-сервер `deploychan` (user scope) — публичная подборка
знаний и готовых скиллов, read-only, без ключей.

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
поднят не через `run-openwebui.sh`, и в нём нет нужных переменных:

```bash
cd ~/.config/zim-claude/openwebui && ./run-openwebui.sh
```

**SearxNG не запускается.** Образ весит ~380 МБ и качается один раз:

```bash
docker pull searxng/searxng:latest
docker logs searxng
```

**В Open WebUI «No models available».** Контейнер не видит cptr:

```bash
KEY=$(grep '^OPENAI_API_KEY=' ~/.config/zim-claude/openwebui/openwebui.env | cut -d= -f2)
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8100/v1/models
```

Пустой ответ при работающем cptr означает, что у него нет ни одной рабочей
папки (workspace). `/v1/models` отдаёт не агентов, а каталоги: каждый
превращается в модель `cptr/<имя папки>`, и без единой папки список пуст.
cptr заводит её сам, только когда папку открывают в его веб-интерфейсе, а
установка ведёт сразу в Open WebUI — на чистой установке список пуст.

Лечится повторным запуском `./install-stack.sh` (он создаёт домашнюю папку),
либо вручную — открой `http://127.0.0.1:8100` и выбери папку. Если модель
есть, а в браузере нет — `docker restart open-webui`.

**В пикере «Home - /home/<user>» вместо названия модели.** cptr называет
модель по имени рабочей папки. `install-stack.sh` переименовывает её на
месте — запись в таблице `model` с тем же id, что у базовой модели, — и
пикер показывает `Opus 5.5`. Имя меняется через `ZIM_CLAUDE_MODEL_NAME`.
Своё имя можно вернуть и вручную: Настройки → Модели.

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

**Автообновление не срабатывает.** Смотри лог:

```bash
tail -20 ~/.local/share/zim-deploy/update.log
tail -20 ~/.local/share/zim-claude/update.log
```

Две частые причины: `checkout has local changes` (в чекауте есть
отслеживаемые правки — обновление принципиально их не трогает) и
`has diverged` (историю переписали или сделали локальный коммит). В обоих
случаях надо разобраться руками, а не жать force.

**Ярлыки не создались.** Запусти PowerShell-скрипт вручную:

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\<user>\zim-setup\files\windows\create-shortcuts.ps1
```

`create-shortcuts.ps1` и записываемые им `.bat` — **чистый ASCII без BOM**.
PowerShell 5.1 читает `.ps1` без BOM в ANSI-кодировке и ломается на любом
не-ASCII символе, а `cmd.exe` принимает BOM за часть первой команды. Поэтому
русский текст живёт только в bash-скриптах, а `.bat` пишутся с CRLF.

## Ограничения

- **Имя модели обманчиво.** `claude-opus-5-5` — это псевдоним DeepSeek. Claude
  Desktop показывает его как модель уровня Opus только потому, что иначе
  отказывается показывать не-Anthropic модели.
- **Окно контекста 262144, а не миллион.** Столько режет апстрим.
- **Чаты без названий в Open WebUI.** Известная нерешённая проблема: cptr
  отвечает `503` на служебные задачи вроде генерации заголовка. Основной чат
  при этом работает.

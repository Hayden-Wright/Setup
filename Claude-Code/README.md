# Claude Code

Claude Code через локальный прокси: терминал и браузер. Временная папка.

## Что ставится

- **zim-claude** — Claude Code, у которого запросы идут не в Anthropic, а в
  локальный LiteLLM, который переводит их в DeepSeek.
- **zim-memory** — поиск по заметкам и истории сессий.
- **Open WebUI** — чат в браузере, с веб-поиском через локальный SearxNG.
- **cptr** — агент с полным доступом к диску, которым можно управлять из браузера.

## Установка

Одна команда. Скачивает только эту папку:

```bash
cd ~
curl -fsSL https://github.com/Hayden-Wright/Setup/archive/refs/heads/main.tar.gz \
  | tar xz --strip-components=2 --one-top-level=zim-setup Setup-main/Claude-Code
cd zim-setup
./install-friend.sh
```

Скрипт поставит пакеты, Docker, Claude Code, zim-claude, доработки, SearxNG,
cptr и Open WebUI. Можно запускать повторно — уже сделанное пропускает.

Прервётся дважды, и это нормально:

1. **После установки Docker** — закрой терминал, открой заново и запусти
   `./install-friend.sh` снова.
2. **Перед настройкой cptr** — скрипт напечатает ссылку вида
   `http://127.0.0.1:8100/?token=...`. Открой её, зарегистрируйся (логин и
   пароль локальные, никуда не уходят) и запусти скрипт ещё раз.

Дальше всё доделается само.

## После установки

| Команда | Что |
|---|---|
| `zim-claude` | терминальный Claude Code |
| `http://127.0.0.1:3000` | чат в браузере |
| `zim-memory search "запрос"` | поиск по заметкам и истории |
| `~/start-all.sh` | поднять всё сразу после перезагрузки |

## Что внутри

| Файл | Зачем |
|---|---|
| `install-friend.sh` | ставит всё одной командой |
| `deploy.sh` | раскладывает доработки поверх `install.sh` из zim-claude |
| `setup-cptr.sh` | настройки cptr в его базу |
| `guide.html` | руководство, открой в браузере |
| `files/` | конфиги, патчи, скрипты |

## Если что-то не так

**`Package 'docker.io' has no installation candidate`.** Скрипт лечит сам:
включает компонент `universe` и пробует снова. Если не помогло вручную:

```bash
sudo add-apt-repository -y universe && sudo apt update
sudo apt install -y docker.io
```

**Не качается Claude Code.** Соединение с `downloads.claude.ai` не проходит —
обычно из-за VPN или прокси. Скрипт сам пробует запасной путь через npm и
печатает, что делать. Вручную:

```bash
curl -I --max-time 10 https://claude.ai/install.sh   # ждём 302
```

**`zim-claude` не найден.** Открой новый терминал — путь
`~/.local/bin` подхватывается из `~/.zshrc` или `~/.bashrc`. Скрипт установки
добавляет его себе сам, так что при повторном запуске проблема не возникает.

**SearxNG не запускается.** Образ весит ~380 МБ и качается один раз. Если
скачать не вышло, скрипт скажет об этом и покажет ошибку докера. Вручную:

```bash
docker pull searxng/searxng:latest
docker run -d --name searxng --restart unless-stopped \
  -p 127.0.0.1:8888:8080 \
  -v ~/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro \
  searxng/searxng:latest
docker logs searxng          # если не поднялся
```

**Прокси не отвечает.**

```bash
~/.local/bin/start-litellm.sh status
~/.local/bin/start-litellm.sh restart
```

**Веб-поиск отвечает только короткими сниппетами.** Контейнер Open WebUI
поднят не через `run-openwebui.sh`, и в нём нет нужных переменных. Поднимай
заново:

```bash
cd ~/zim-claude/openwebui && ./run-openwebui.sh
```

**Чаты без названий в Open WebUI.** Известная нерешённая проблема: cptr
отвечает `503` на служебные задачи вроде генерации заголовка. Основной чат
при этом работает.

**Обновил cptr — пропали картинки из чата.** Обновление затирает патчи:

```bash
PKG=$(ls -d ~/.local/share/cptr-venv/lib/python*/site-packages/cptr)
patch -p1 -d "$PKG" < ~/zim-claude/patches/gateway-images.patch
patch -p1 -d "$PKG" < ~/zim-claude/patches/config-multiline-toml.patch
~/start-cptr.sh restart
```

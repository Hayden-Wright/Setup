#!/usr/bin/env bash
# start-all.sh — поднять весь стек после перезагрузки.
#
#   ~/start-all.sh
#
# Поднимает: Docker, сеть zim-net, SearxNG, оба прокси (:4000 для терминала,
# :4002 для Claude Desktop) и в конце запускает zim-claude.

# Подтягиваем PATH из профиля оболочки — какой бы она ни была.
[[ -f ~/.profile ]] && . ~/.profile
[[ -f ~/.bashrc ]] && . ~/.bashrc 2>/dev/null
export PATH="$HOME/.local/bin:$PATH"

# Отключаем предупреждения о неизвестной модели
export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1

echo "=== 1. Запуск Docker ==="
# Правило sudoers на эту одну команду кладёт install-stack.sh, поэтому
# пароль здесь не спрашивается. Если правила нет — Docker и так уже поднят
# systemd'ом, и ошибка безобидна.
sudo -n service docker start >/dev/null 2>&1 || true
if ! docker ps >/dev/null 2>&1; then
  echo "Docker не отвечает — смотри: sudo service docker status" >&2
fi

# Сеть zim-net. Раньше она связывала SearxNG с Open WebUI; браузерного чата
# больше нет, но сеть оставляем: контейнер уже привязан к ней, и пересоздание
# ради косметики сломало бы настройки у тех, кто ставил раньше.
echo "=== 2. Сеть для поиска ==="
docker network inspect zim-net >/dev/null 2>&1 || docker network create zim-net >/dev/null 2>&1

echo "=== 3. Запуск SearxNG ==="
docker start searxng >/dev/null 2>&1 || docker run -d --name searxng --restart unless-stopped \
  -p 127.0.0.1:8888:8080 \
  -v ~/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro \
  searxng/searxng:latest >/dev/null 2>&1
docker network connect zim-net searxng 2>/dev/null

echo "=== 4. Запуск прокси ==="
~/.local/bin/start-litellm.sh start >/dev/null 2>&1 && echo "CLI-прокси: :4000"
( cd ~/zim-claude/claude-desktop-integration && ./start-desktop-proxy.sh start ) >/dev/null 2>&1 \
  && echo "Desktop-шлюз: :4002"

sleep 2

echo "=== 5. Запуск zim-claude ==="
zim-claude --dangerously-skip-permissions

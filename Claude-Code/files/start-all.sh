#!/usr/bin/env bash

# Подтягиваем PATH из профиля оболочки — какой бы она ни была. Раньше здесь
# был только ~/.zshrc, и на системе без zsh (обычный Ubuntu из wsl --install)
# ~/.local/bin в PATH не попадал, а вместе с ним не находились zim-claude и
# zim-memory.
[[ -f ~/.profile ]] && . ~/.profile
[[ -f ~/.zshrc ]] && . ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"

# Отключаем предупреждения о неизвестной модели
export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1

echo "=== 1. Запуск Docker ==="
sudo service docker start >/dev/null 2>&1

# Общая сеть для Open WebUI и SearxNG.
#
# Без неё оба контейнера живут в default bridge, где у Docker НЕТ внутреннего
# DNS для имён контейнеров (резолвер = 172.31.144.1, перехваченный FlClash).
# Тогда имя `searxng` уходит наружу и возвращается fake-ip 198.18.0.104 —
# соединение «есть», а за ним пусто. Веб-поиск в Open WebUI молча ломается.
echo "=== 2. Сеть для поиска ==="
docker network inspect zim-net >/dev/null 2>&1 || docker network create zim-net >/dev/null 2>&1

echo "=== 3. Запуск SearxNG ==="
docker start searxng >/dev/null 2>&1 || docker run -d --name searxng --restart unless-stopped \
  -p 127.0.0.1:8888:8080 \
  -v ~/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro \
  searxng/searxng:latest >/dev/null 2>&1
docker network connect zim-net searxng 2>/dev/null

echo "=== 4. Запуск Open WebUI (браузерный чат) ==="
# Раньше здесь стояло «Open WebUI отключён» — от старой схемы, когда браузер
# был отдельным контейнером :3000. Сейчас Open WebUI это и есть cptr, он
# поднимается шагом ниже.
if docker ps -a --format '{{.Names}}' | grep -qx open-webui; then
  docker start open-webui >/dev/null 2>&1 && echo "Open WebUI: http://127.0.0.1:3000"
fi

echo "=== 5. Запуск прокси Desktop-шлюза ==="
cd ~/zim-claude/claude-desktop-integration && ./start-desktop-proxy.sh >/dev/null 2>&1 &

echo "=== 6. Запуск cptr (агент с доступом к диску) ==="
# Ссылку печатаем только если cptr её выдал: на уже настроенной базе токена
# в логе нет, и раньше выводилось «Computer: http://.../?token=» — пустышка.
if ~/start-cptr.sh start >/dev/null 2>&1; then
  CTRL_URL="$(~/start-cptr.sh url 2>/dev/null || true)"
  if [[ -n "$CTRL_URL" ]]; then
    echo "Computer: $CTRL_URL"
  else
    echo "Computer: http://127.0.0.1:8100"
  fi
else
  echo "Computer не запустился — смотри /tmp/cptr.log" >&2
fi

sleep 2

echo "=== 7. Запуск zim-claude ==="
zim-claude --dangerously-skip-permissions

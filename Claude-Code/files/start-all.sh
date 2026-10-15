#!/bin/zsh

# Загружаем конфигурацию zsh, чтобы подтянулись все алиасы и PATH
[[ -f ~/.zshrc ]] && source ~/.zshrc

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

echo "=== 4. Open WebUI отключён (оставлен только Computer на :8100) ==="

echo "=== 5. Запуск прокси ==="
cd ~/zim-claude/claude-desktop-integration && ./start-desktop-proxy.sh >/dev/null 2>&1 &

echo "=== 6. Запуск Open WebUI Computer ==="
~/start-cptr.sh start >/dev/null 2>&1 && echo "Computer: $(~/start-cptr.sh url 2>/dev/null)"

sleep 2

echo "=== 7. Запуск zim-claude ==="
zim-claude --dangerously-skip-permissions

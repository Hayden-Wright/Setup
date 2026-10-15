#!/usr/bin/env bash
# Open WebUI — запуск с настройками «обычный чат + веб-поиск».
#
# Контейнер был пересоздан вручную (docker run), а не через compose, поэтому
# команда запуска зафиксирована здесь: при пересоздании легко потерять
# ENABLE_LOCAL_WEB_FETCH и WEB_FETCH_FILTER_LIST, и поиск молча деградирует
# до сниппетов (страницы перестают загружаться).
#
#   ./run-openwebui.sh          — пересоздать и запустить
#   ./run-openwebui.sh status   — показать состояние
set -euo pipefail

NAME=open-webui
IMAGE="ghcr.io/open-webui/open-webui@sha256:e597ba2ca4425ff40f1f677930baae1278cc1e44cea399d5f588d5ce53611910"
VOLUME=open-webui
ENV_FILE="$(dirname "$0")/openwebui.env"

if [[ "${1:-run}" == "status" ]]; then
  docker ps -a --filter "name=^${NAME}$" --format '{{.Names}}\t{{.Status}}'
  exit 0
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped --network host \
  -v "${VOLUME}:/app/backend/data" \
  --env-file "$ENV_FILE" \
  "$IMAGE" >/dev/null
echo "запущен: http://127.0.0.1:3000"

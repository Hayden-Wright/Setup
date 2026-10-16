#!/usr/bin/env bash
# install-friend.sh — поставить весь стек одной командой.
#
# Скрипт можно запускать сколько угодно раз: он смотрит, что уже сделано, и
# доделывает только оставшееся. Если чего-то не хватает (например, ты ещё не
# зарегистрировался в cptr), он скажет, что сделать, и попросит запустить себя
# снова.
#
# Запускать из каталога, куда склонирован репозиторий:
#
#   ./install-friend.sh
#
# Своё окружение не трогает: ставит только то, чего нет.

set -uo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES="$SRC/files"

# ── оформление вывода ────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else
  B=''; D=''; G=''; Y=''; R=''; C=''; N=''
fi

step()  { printf '\n%s▸ %s%s\n' "$B$C" "$*" "$N"; }
ok()    { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
have()  { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
fail()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }

# Что осталось сделать после текущего шага. Если непусто — в конце скажем
# «запусти ещё раз».
TODO=()
todo() { TODO+=("$1"); }

need() { command -v "$1" >/dev/null 2>&1; }

# ── проверки окружения ───────────────────────────────────────────────────────

[[ -d "$FILES" ]] || { fail "нет каталога files/ рядом со скриптом — запусти из корня репозитория"; exit 1; }

# ~/.local/bin добавляем в PATH СРАЗУ. Иначе на повторном запуске уже
# установленный claude (и zim-claude, и zim-memory) не находится: install.sh
# правит PATH только в конфигах, а текущий терминал его не видит — скрипт
# решает, что ничего не установлено, и идёт ставить заново.
export PATH="$HOME/.local/bin:$PATH"

printf '%sZim-стек: установка%s\n' "$B" "$N"
printf '%sМожно запускать повторно — уже сделанное пропускается.%s\n' "$D" "$N"

# ── 1. базовые пакеты ────────────────────────────────────────────────────────

step "1/8  Базовые пакеты"

MISSING=()
for pkg in git curl python3; do
  need "$pkg" || MISSING+=("$pkg")
done

# `import venv` проходит и БЕЗ пакета python3-venv: сам модуль venv лежит в
# libpython3-stdlib, а пакет python3-venv приносит только ensurepip — без него
# `python3 -m venv` создаёт окружение без pip и падает позже. Поэтому
# проверяем именно ensurepip.
python3 -c 'import ensurepip' >/dev/null 2>&1 || MISSING+=("python3-venv")

if (( ${#MISSING[@]} )); then
  warn "не хватает: ${MISSING[*]}"
  echo "      сейчас установим (понадобится пароль от системы)"
  # update обязателен: на свежей WSL списки пакетов пусты, и apt не знает даже
  # про docker.io — установка падает с "has no installation candidate".
  sudo apt-get update -qq || warn "apt update прошёл с ошибками, продолжаю"
  sudo apt-get install -y "${MISSING[@]}" || { fail "не удалось установить пакеты"; exit 1; }
  ok "пакеты установлены"
else
  have "git, curl, python3, venv — уже есть"
fi

# ── 2. Docker ────────────────────────────────────────────────────────────────

step "2/8  Docker"

if need docker; then
  if docker ps >/dev/null 2>&1; then
    ok "Docker работает без пароля"
  else
    warn "Docker стоит, но нужен доступ к нему"
    if ! id -nG | tr ' ' '\n' | grep -qx docker; then
      sudo usermod -aG docker "$USER" && have "добавил тебя в группу docker"
    fi
    fail "закрой это окно терминала, открой заново и запусти скрипт снова"
    exit 0
  fi
else
  warn "Docker не установлен"
  # docker.io лежит в компоненте universe. На свежей Ubuntu он обычно включён,
  # но если выключен (или система ставилась минимальной), apt отвечает
  #   Package 'docker.io' has no installation candidate
  # и предлагает только "is only available from another source".
  if ! sudo apt-get install -y docker.io; then
    warn "не вышло напрямую — включаю компонент universe и пробую снова"
    sudo apt-get install -y software-properties-common >/dev/null 2>&1
    sudo add-apt-repository -y universe >/dev/null 2>&1
    sudo apt-get update -qq || warn "apt update прошёл с ошибками, продолжаю"
    sudo apt-get install -y docker.io || { fail "не удалось поставить Docker"; exit 1; }
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1
  sudo usermod -aG docker "$USER" >/dev/null 2>&1
  fail "Docker поставлен. Закрой это окно терминала, открой заново и запусти скрипт снова"
  exit 0
fi

# start-all.sh поднимает Docker командой `sudo service docker start`, и без
# правила sudoers она спрашивает пароль при КАЖДОМ запуске. Правило — только
# на эту одну команду, ничего больше оно не разрешает.
#
# Проверяем именно наличие правила, а не `sudo -n service docker status`:
# та команда возвращает ошибку и когда Docker просто остановлен, и скрипт
# решил бы, что правила нет, и полез бы писать его повторно.
SUDOERS=/etc/sudoers.d/docker-service
if sudo -n -l 2>/dev/null | grep -q 'NOPASSWD.*service docker'; then
  have "Docker стартует без пароля"
else
  SERVICE_BIN="$(command -v service || echo /usr/sbin/service)"
  have "разрешаю запуск Docker без пароля (только «service docker»)"
  # Через visudo -cf: битый файл в sudoers.d ломает sudo целиком, поэтому
  # сначала проверяем синтаксис на временном файле и только потом кладём.
  # Проверка идёт БЕЗ sudo: visudo -cf читает файл и root для этого не нужен,
  # а с sudo она молча провалилась бы, если пароль уже спрошен.
  SUDOERS_TMP="$(mktemp)"
  printf '%s ALL=(ALL) NOPASSWD: %s docker *\n' "$USER" "$SERVICE_BIN" >"$SUDOERS_TMP"
  if visudo -cf "$SUDOERS_TMP" >/dev/null 2>&1; then
    sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS"
    ok "правило добавлено: $SUDOERS"
  else
    warn "правило не прошло проверку синтаксиса — sudoers не трогаю"
    warn "start-all.sh будет спрашивать пароль; можно убрать sudo из строки"
    warn "«sudo service docker start» в ~/start-all.sh — Docker и так стартует"
  fi
  rm -f "$SUDOERS_TMP"
fi

# ── 3. Claude Code ───────────────────────────────────────────────────────────

step "3/8  Claude Code"

# Сам Claude Code в репозитории zim-claude НЕ лежит — там только обёртка,
# которая запускает уже установленный `claude`. Поэтому бинарь берётся с
# официального сайта, ровно как это делает install.sh самого zim-claude.
# Пробуем два источника: сначала официальный установщик, потом npm.
install_claude() {
  local tmp; tmp="$(mktemp)"
  have "качаю установщик (официальный сайт)..."
  # --max-time: без него curl висит до двух минут на мёртвом соединении
  # вместо того, чтобы сразу сказать, что связи нет.
  if curl -fsSL --connect-timeout 15 --max-time 120 \
       https://claude.ai/install.sh -o "$tmp" 2>/dev/null; then
    bash "$tmp" && rm -f "$tmp" && return 0
  fi
  rm -f "$tmp"

  warn "официальный сайт недоступен — пробую через npm"
  if need npm; then
    npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && return 0
  else
    warn "npm не установлен — ставлю nodejs и пробую снова"
    sudo apt-get install -y nodejs npm >/dev/null 2>&1 \
      && npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 && return 0
  fi
  return 1
}

if need claude; then
  ok "уже установлен: $(claude --version 2>/dev/null | head -1)"
else
  if install_claude; then
    export PATH="$HOME/.local/bin:$PATH"
    need claude && ok "установлен" || { fail "установился, но не виден — запусти скрипт ещё раз"; exit 0; }
  else
    fail "не удалось скачать Claude Code"
    cat <<'EOF'

      Скорее всего мешает VPN или прокси: соединение с downloads.claude.ai
      не проходит. Что попробовать по порядку:

        1. Выключи VPN и запусти скрипт снова.
        2. Если включён прокси (FlClash и подобные) — выключи его или добавь
           downloads.claude.ai и registry.npmjs.org в исключения.
        3. Проверь связь вручную:
             curl -I --max-time 10 https://claude.ai/install.sh
           Должен вернуться код 302. Таймаут означает, что сеть закрыта.

      После этого запусти ./install-friend.sh снова.

EOF
    exit 1
  fi
fi

# Диалог «Do you trust the files in this folder?» при каждом запуске. Claude
# Code хранит ответ в ~/.claude.json, в projects[<каталог>].hasTrustDialogAccepted,
# и спрашивает заново, пока ключа нет. Доверие наследуется вложенными
# каталогами, поэтому одной записи на $HOME хватает на всё внутри — и на
# терминал, и на агента cptr, который стартует в воркспейсе.
#
# --dangerously-skip-permissions этот диалог НЕ снимает (проверено): флаг
# отвечает за права на инструменты, а не за доверие к папке.
have "снимаю запрос доверия к папке"
python3 -I - "$HOME" <<'PY'
import json, pathlib, sys

home = pathlib.Path(sys.argv[1])
path = home / ".claude.json"

try:
    data = json.loads(path.read_text()) if path.exists() else {}
except ValueError:
    # Битый файл не трогаем: Claude Code пересоздаст его сам, а затирать
    # чужую историю сессий ради одной строки не стоит.
    print("  ! ~/.claude.json не читается — пропускаю, доверие спросят один раз")
    raise SystemExit(0)

if not isinstance(data, dict):
    raise SystemExit(0)

projects = data.get("projects")
if not isinstance(projects, dict):
    # Ключа нет или он не тот, чем кажется — заводим свой, чужое не трогаем.
    projects = {}
    data["projects"] = projects

entry = projects.get(str(home))
if not isinstance(entry, dict):
    entry = {}
    projects[str(home)] = entry

if entry.get("hasTrustDialogAccepted") is True:
    print(f"  · доверие уже стоит: {home}")
else:
    entry["hasTrustDialogAccepted"] = True
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"  ✓ доверие записано: {home}")
PY

# ── 4. zim-claude ────────────────────────────────────────────────────────────

step "4/8  zim-claude (CLI и прокси)"

ZIM_DIR="$HOME/zim-claude"

if [[ -d "$ZIM_DIR/.git" ]]; then
  have "репозиторий уже склонирован"
else
  git clone --quiet https://github.com/Mr-Destroyer/zim-claude "$ZIM_DIR" \
    || { fail "не удалось склонировать репозиторий"; exit 1; }
  ok "склонирован в ~/zim-claude"
fi

# litellm ставим ЗАРАНЕЕ, в тот самый venv, который ищет install.sh. Иначе
# установщик спросит разрешения и, если терминал не интерактивный, просто
# пропустит шаг — прокси останется без litellm и не поднимется.
VENV="$HOME/.local/share/zim-claude/venv"
if [[ -x "$VENV/bin/litellm" ]]; then
  have "litellm уже стоит в $VENV"
else
  have "ставлю litellm — это займёт пару минут и ~300 МБ"
  mkdir -p "$HOME/.local/share/zim-claude"
  chmod 700 "$HOME/.local/share/zim-claude"
  python3 -m venv "$VENV" || { fail "не удалось создать venv"; exit 1; }
  "$VENV/bin/pip" install --quiet --disable-pip-version-check -U pip
  if "$VENV/bin/pip" install --quiet --disable-pip-version-check 'litellm[proxy]>=1.100.1' 'uvloop>=0.22.1'; then
    ok "litellm установлен"
  else
    fail "не удалось поставить litellm"; exit 1
  fi
fi

have "запускаю установщик zim-claude (теперь он ничего не спрашивает)"
# Код возврата install.sh теряется в конвейере с sed, поэтому смотрим на него
# явно через PIPESTATUS: иначе провалившийся установщик выглядел бы как успех,
# а дальше всё падало бы на отсутствующем zim-claude с непонятной ошибкой.
( cd "$ZIM_DIR" && ./install.sh ) 2>&1 | sed 's/^/      /'
INSTALL_RC="${PIPESTATUS[0]}"

if [[ ! -x "$HOME/.local/bin/zim-claude" ]]; then
  fail "zim-claude не установился — смотри вывод выше"
  exit 1
elif (( INSTALL_RC != 0 )); then
  warn "установщик завершился с кодом $INSTALL_RC, но zim-claude на месте"
  warn "проверь вывод выше: возможно, что-то пропущено"
  ok "zim-claude установлен"
else
  ok "zim-claude установлен"
fi

# Запускаем оба прокси СРАЗУ после установки. Без этого:
#   :4000 — терминал зависает на «Handling...», потому что claude стучится
#           в прокси, которого нет (zim-claude поднял бы его сам, но только
#           если конфиг уже на месте — а доработки кладутся следующим шагом);
#   :4002 — агент cptr в Open WebUI получает 400 на каждую модель.
#
# Проверяем результат по порту, а не по коду возврата: вывод идёт через
# конвейер с tail, и код возврата берётся от tail, который всегда 0. Упавший
# прокси иначе выглядел бы как поднявшийся, а всплывало это позже — зависшим
# на «Handling...» терминалом.
proxy_up() {
  curl -sf "http://127.0.0.1:$1/health/liveliness" -o /dev/null --max-time 3 2>/dev/null
}

have "поднимаю прокси :4000 (для терминала)"
"$HOME/.local/bin/start-litellm.sh" restart 2>&1 | tail -2 | sed 's/^/      /'
if proxy_up 4000; then
  ok "прокси :4000 отвечает"
else
  warn "прокси :4000 не поднялся — терминал будет висеть на «Handling...»"
  warn "смотри /tmp/litellm-proxy.log"
  todo "поднять прокси :4000 (~/.local/bin/start-litellm.sh restart)"
fi

if [[ -x "$ZIM_DIR/claude-desktop-integration/start-desktop-proxy.sh" ]]; then
  have "поднимаю прокси :4002 (для агента cptr)"
  ( cd "$ZIM_DIR/claude-desktop-integration" && ./start-desktop-proxy.sh restart ) \
    2>&1 | tail -2 | sed 's/^/      /'
  if proxy_up 4002; then
    ok "прокси :4002 отвечает"
  else
    warn "прокси :4002 не поднялся — агент в Open WebUI будет отвечать ошибкой"
    warn "смотри /tmp/litellm-desktop.log"
    todo "поднять прокси :4002 (cd ~/zim-claude/claude-desktop-integration && ./start-desktop-proxy.sh restart)"
  fi
fi

# ── 5. доработки ─────────────────────────────────────────────────────────────

step "5/8  Доработки (веб-поиск, zim-memory, конфиги)"

( cd "$SRC" && ./deploy.sh ) 2>&1 | sed 's/^/      /'
if (( PIPESTATUS[0] != 0 )); then
  fail "deploy.sh завершился с ошибкой — смотри вывод выше"
  exit 1
fi

# deploy.sh заменил ~/litellm-config.yaml (добавил перехват веб-поиска), но
# уже запущенный прокси держит в памяти СТАРЫЙ конфиг. Без перезапуска
# веб-поиск не заработает: LiteLLM продолжит отдавать 400 на web_search.
# Перезапускаем ПОСЛЕ доработок — на шаге 4 конфиг был ещё исходный.
have "перезапускаю прокси, чтобы подхватил новый конфиг"
"$HOME/.local/bin/start-litellm.sh" restart 2>&1 | tail -1 | sed 's/^/      /'
proxy_up 4000 || warn "прокси :4000 не поднялся после перезапуска — смотри /tmp/litellm-proxy.log"
if [[ -x "$ZIM_DIR/claude-desktop-integration/start-desktop-proxy.sh" ]]; then
  ( cd "$ZIM_DIR/claude-desktop-integration" && ./start-desktop-proxy.sh restart ) \
    2>&1 | tail -1 | sed 's/^/      /'
  proxy_up 4002 || warn "прокси :4002 не поднялся — смотри /tmp/litellm-desktop.log"
fi

# PATH для zsh: install.sh прописывает только ~/.bashrc, а оболочка по
# умолчанию в Ubuntu — zsh, если её поставили.
if [[ -f "$HOME/.zshrc" ]] && ! grep -q '.local/bin' "$HOME/.zshrc"; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.zshrc"
  have "добавил ~/.local/bin в ~/.zshrc"
fi

# ── 6. SearxNG ───────────────────────────────────────────────────────────────

step "6/8  SearxNG (локальный веб-поиск)"

docker network inspect zim-net >/dev/null 2>&1 || docker network create zim-net >/dev/null 2>&1

# Образ весит ~380 МБ, и на свежей машине его нужно скачать. Раньше это шло
# с заглушённым выводом: терминал молчал несколько минут, а потом появлялось
# «не удалось запустить» без причины. Теперь скачивание видно, а ошибка
# докера печатается как есть.
SEARXNG_OK=0

if docker ps -a --format '{{.Names}}' | grep -qx searxng; then
  docker start searxng >/dev/null 2>&1
  have "контейнер уже есть — запущен"
  SEARXNG_OK=1
else
  have "скачиваю образ SearxNG (~380 МБ, один раз)"
  # Вывод забираем в переменную, а не в конвейер: в `if docker pull ... | tail`
  # проверяется код возврата tail, который всегда 0, — провал скачивания
  # прошёл бы как успех.
  PULL_OUT="$(docker pull searxng/searxng:latest 2>&1)"
  PULL_RC=$?
  printf '%s\n' "$PULL_OUT" | tail -3 | sed 's/^/      /'

  if (( PULL_RC == 0 )); then
    if docker run -d --name searxng --restart unless-stopped \
         -p 127.0.0.1:8888:8080 \
         -v "$HOME/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro" \
         searxng/searxng:latest >/dev/null 2>&1; then
      ok "запущен"
      SEARXNG_OK=1
    else
      warn "образ есть, но контейнер не запустился — вот причина:"
      docker run -d --name searxng --restart unless-stopped \
        -p 127.0.0.1:8888:8080 \
        -v "$HOME/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro" \
        searxng/searxng:latest 2>&1 | sed 's/^/      /'
      docker rm -f searxng >/dev/null 2>&1
    fi
  else
    warn "не удалось скачать образ SearxNG — проверь связь с интернетом"
    warn "вручную:  docker pull searxng/searxng:latest"
  fi
fi
docker network connect zim-net searxng >/dev/null 2>&1

# Ждём, пока поднимется, и проверяем именно JSON: без formats: json SearxNG
# отвечает 403, и LiteLLM получает пустую выдачу.
if (( SEARXNG_OK )); then
  SEARXNG_UP=0
  for _ in $(seq 1 30); do
    if curl -sf 'http://127.0.0.1:8888/search?q=test&format=json' -o /dev/null 2>/dev/null; then
      ok "отвечает"
      SEARXNG_UP=1
      break
    fi
    sleep 1
  done
  if (( ! SEARXNG_UP )); then
    # Раньше здесь просто заканчивался цикл — и дальше всё шло молча, будто
    # всё в порядке, а веб-поиск потом не работал.
    warn "контейнер запущен, но не отвечает на 127.0.0.1:8888 за 30 с"
    warn "смотри лог:  docker logs searxng"
    SEARXNG_OK=0
  fi
fi

if (( ! SEARXNG_OK )); then
  warn "веб-поиск работать не будет, пока SearxNG не поднимется"
  todo "запустить SearxNG (см. README, раздел «Если что-то не так»)"
fi

# ── 7. cptr ──────────────────────────────────────────────────────────────────

step "7/8  cptr (агент с доступом к диску)"

CPTR_VENV="$HOME/.local/share/cptr-venv"
CPTR_PY="$CPTR_VENV/bin/python"

if [[ -x "$CPTR_VENV/bin/cptr" ]]; then
  have "уже установлен"
else
  # [agents] обязателен: поддержка Claude Code у cptr — опциональная
  # зависимость (claude-agent-sdk). Без неё профиль агента получает статус
  # missing_dependency, gateway.model из setup-cptr.sh не разрешается, и чат
  # отвечает 503 No API model connections configured.
  have "ставлю cptr 0.9.21 (версия зафиксирована — под неё написаны патчи)"
  python3 -m venv "$CPTR_VENV" || { fail "не удалось создать venv"; exit 1; }
  "$CPTR_VENV/bin/pip" install --quiet --disable-pip-version-check -U pip
  "$CPTR_VENV/bin/pip" install --quiet --disable-pip-version-check 'cptr[agents]==0.9.21' \
    || { fail "не удалось поставить cptr"; exit 1; }
  ok "установлен"
fi

# На уже стоящем cptr доработка не применилась бы: ветка выше пропускается.
# Проверяем SDK отдельно, чтобы починка дошла и до тех, кто ставил раньше.
if [[ -x "$CPTR_VENV/bin/cptr" ]] && ! "$CPTR_VENV/bin/python" -c 'import claude_agent_sdk' >/dev/null 2>&1; then
  have "дописываю claude-agent-sdk (нужен cptr для работы агента)"
  "$CPTR_VENV/bin/pip" install --quiet --disable-pip-version-check 'claude-agent-sdk>=0.1.62' \
    || warn "не удалось поставить claude-agent-sdk — чат будет отвечать ошибкой"
fi

# Патчи идемпотентны не полностью: повторное применение к уже пропатченному
# файлу выдаст «Reversed (or previously applied) patch detected». Поэтому
# сначала проверяем --dry-run: если он молчит, патч уже стоит.
CPTR_PKG="$(ls -d "$CPTR_VENV"/lib/python*/site-packages/cptr 2>/dev/null | head -1)"
if [[ -n "$CPTR_PKG" ]]; then
  for p in gateway-images config-multiline-toml; do
    pf="$ZIM_DIR/patches/$p.patch"
    [[ -f "$pf" ]] || continue
    if patch -p1 --dry-run -d "$CPTR_PKG" <"$pf" >/dev/null 2>&1; then
      patch -p1 -d "$CPTR_PKG" <"$pf" >/dev/null 2>&1 && ok "патч $p применён"
    else
      have "патч $p уже стоит"
    fi
  done
fi

# Стартуем cptr (если ещё не запущен) — дальше нужен его пользователь.
# Вывод НЕ глушим: раньше ошибка запуска уходила в /dev/null, и наверху
# появлялось только «cptr не отвечает» без причины. Самая частая причина —
# shebang скрипта, указывающий на отсутствующий интерпретатор.
CPTR_START_OUT="$("$HOME/start-cptr.sh" start 2>&1)"
CPTR_START_RC=$?

CPTR_UP=0
for _ in $(seq 1 20); do
  if curl -sf http://127.0.0.1:8100/api/config -o /dev/null 2>/dev/null; then
    CPTR_UP=1
    break
  fi
  sleep 1
done

if (( CPTR_UP )); then
  ok "cptr работает на http://127.0.0.1:8100"
else
  warn "cptr не отвечает"
  if (( CPTR_START_RC != 0 )); then
    printf '%s\n' "$CPTR_START_OUT" | sed 's/^/      /'
  fi
  if ! command -v zsh >/dev/null 2>&1 && grep -q 'bad interpreter' <<<"$CPTR_START_OUT"; then
    warn "скрипту нужен zsh, которого нет — установи его и запусти снова:"
    warn "    sudo apt install -y zsh"
  fi
  warn "смотри лог:  tail -30 /tmp/cptr.log"
fi

# ── 7b. пользователь cptr ────────────────────────────────────────────────────

CPTR_USER=""
if [[ -f "$HOME/.cptr/app.db" ]]; then
  CPTR_USER="$("$CPTR_PY" -I -c "
import sqlite3, pathlib
try:
    con = sqlite3.connect(f\"file:{pathlib.Path.home()/'.cptr/app.db'}?mode=ro\", uri=True)
    row = con.execute('select id from users limit 1').fetchone()
    print(row[0] if row else '')
except Exception:
    print('')
" 2>/dev/null)"
fi

if [[ -z "$CPTR_USER" ]]; then
  step "7b/8  Нужен твой шаг: регистрация в cptr"

  # Токен есть только при первом запуске на чистой базе. Если cptr не поднялся,
  # ссылки нет вовсе — раньше в этом случае печаталось «?token=» с пустым
  # значением, и это выглядело как рабочая ссылка, хотя вела никуда.
  URL="$("$HOME/start-cptr.sh" url 2>/dev/null)"
  if [[ -z "$URL" ]]; then
    fail "cptr не запущен, поэтому ссылки для регистрации нет"
    cat <<'EOF'

      Сначала подними cptr:

          ~/start-cptr.sh start

      Если он не стартует — посмотри причину:

          tail -30 /tmp/cptr.log

      Затем запусти этот скрипт снова.

EOF
    exit 1
  fi

  cat <<EOF

  Открой в браузере эту ссылку (она с одноразовым токеном доступа):

      $URL

  Зарегистрируйся — придумай логин и пароль, они локальные, никуда не уходят.
  После этого запусти этот скрипт ещё раз, и он доделает остальное.

EOF
  exit 0
fi

have "пользователь cptr заведён"

# Настройки cptr в базу (модель для чата, профиль агента).
"$SRC/setup-cptr.sh" 2>&1 | sed 's/^/      /'
if (( PIPESTATUS[0] != 0 )); then
  fail "не удалось записать настройки cptr — смотри вывод выше"
  exit 1
fi

# ── 8. Open WebUI ────────────────────────────────────────────────────────────

step "8/8  Open WebUI (браузерный чат)"

ENV_FILE="$ZIM_DIR/openwebui/openwebui.env"

# WEBUI_SECRET_KEY подписывает сессионные куки Open WebUI. В наборе лежит
# ключ Хейдена, а двум разным установкам он не нужен: сгенерируем свой. Делаем
# это ровно один раз — при повторном запуске значение уже не тронем, иначе
# после каждого запуска всех выкидывало бы из аккаунта.
if grep -q '^WEBUI_SECRET_KEY=$' "$ENV_FILE" 2>/dev/null; then
  have "генерирую свой ключ сессий для Open WebUI"
  SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  python3 -I - "$ENV_FILE" "$SECRET" <<'PY'
import pathlib, re, sys
path, secret = pathlib.Path(sys.argv[1]), sys.argv[2]
path.write_text(re.sub(r'^WEBUI_SECRET_KEY=.*$', f'WEBUI_SECRET_KEY={secret}',
                       path.read_text(), flags=re.M))
PY
  ok "ключ сессий сгенерирован"
fi

# API-ключ cptr создаём сами: он привязан к id пользователя, а JWT подписывается
# секретом из config.toml. Так друг не проходит через админку руками.
#
# KEY объявляем пустым заранее: при повторном запуске ключ уже прописан, ветка
# else не выполняется, а ниже он всё равно подставляется в базу Open WebUI.
# Без этого `set -u` роняет скрипт на последнем шаге.
KEY=""
if grep -q '^OPENAI_API_KEY=sk-cptr-' "$ENV_FILE" 2>/dev/null; then
  have "ключ cptr уже прописан"
  KEY="$(sed -n 's/^OPENAI_API_KEY=//p' "$ENV_FILE" | head -1)"
else
  KEY="$("$CPTR_PY" -I - "$HOME" <<'PY' 2>/dev/null
import json, pathlib, sqlite3, sys, time, uuid, urllib.request, tomllib

home = pathlib.Path(sys.argv[1])
try:
    secret = tomllib.loads((home / ".cptr/config.toml").read_text())["server"]["secret"]
    con = sqlite3.connect(f"file:{home/'.cptr/app.db'}?mode=ro", uri=True)
    uid, name, role = con.execute("select id, display_name, role from users limit 1").fetchone()
    con.close()
    import jwt
    tok = jwt.encode({"sub": uid, "username": name, "role": role,
                      "exp": time.time() + 300, "jti": str(uuid.uuid4())},
                     secret, algorithm="HS256")
    req = urllib.request.Request(
        "http://127.0.0.1:8100/v1/keys",
        data=json.dumps({"name": "open-webui"}).encode(),
        headers={"Content-Type": "application/json",
                 "Cookie": f"cptr_session={tok}"},
        method="POST")
    print(json.loads(urllib.request.urlopen(req, timeout=10).read())["key"])
except Exception:
    print("")
PY
)"

  if [[ -n "$KEY" ]]; then
    python3 -I - "$ENV_FILE" "$KEY" <<'PY'
import pathlib, re, sys
path, key = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
if re.search(r'^OPENAI_API_KEY=.*$', text, flags=re.M):
    text = re.sub(r'^OPENAI_API_KEY=.*$', f'OPENAI_API_KEY={key}', text, flags=re.M)
else:
    text += f'\nOPENAI_API_KEY={key}\n'
path.write_text(text)
PY
    ok "ключ cptr создан и прописан"
  else
    warn "не удалось создать ключ автоматически"
    warn "сделай вручную: открой http://127.0.0.1:8100, создай API-ключ"
    warn "и вставь его в $ENV_FILE в строку OPENAI_API_KEY="
    todo "прописать ключ cptr в openwebui.env"
  fi
fi

if docker ps --format '{{.Names}}' | grep -qx open-webui; then
  have "контейнер уже запущен"
else
  ( cd "$ZIM_DIR/openwebui" && ./run-openwebui.sh ) 2>&1 | sed 's/^/      /'
  if (( PIPESTATUS[0] != 0 )); then
    fail "Open WebUI не запустился — смотри вывод выше"
    exit 1
  fi
  ok "запущен"
fi

# Ждём, пока контейнер поднимется, и ДОписываем настройки в его базу.
#
# Почему в базу, а не только в env: Open WebUI с ENABLE_PERSISTENT_CONFIG=true
# (значение по умолчанию) хранит провайдеров в своей webui.db и читает env
# только при ПЕРВОМ старте на пустой базе. Если контейнер уже создавался —
# например, при повторном запуске скрипта — ключ и адрес из env игнорируются,
# и в пикере моделей остаётся «No models available».
have "проверяю настройки в базе Open WebUI"

WEBUI_SETTINGS_RC=0
for _ in $(seq 1 30); do
  if docker exec open-webui python -c 'import sqlite3' >/dev/null 2>&1; then
    WEBUI_SETTINGS_RC=1
    break
  fi
  sleep 2
done

if (( WEBUI_SETTINGS_RC )); then
  docker exec -i open-webui python - "$KEY" <<'PY' 2>&1 | sed 's/^/      /'
import json, os, sqlite3, sys

# Ключ передаём аргументом, а если он пуст (создать не удалось) — берём из env
# контейнера, чтобы не затереть уже рабочее значение пустым.
key = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.environ.get("OPENAI_API_KEY", "")
base = os.environ.get("OPENAI_API_BASE_URL", "http://127.0.0.1:8100/v1")

con = sqlite3.connect("/app/backend/data/webui.db")
now = __import__("time").time()

rows = {
    "openai.enable": json.dumps(True),
    "openai.api_base_urls": json.dumps([base]),
    "openai.api_keys": json.dumps([key] if key else []),
    # Заголовки нужны cptr, чтобы связать ветки чата Open WebUI с сессией агента.
    "openai.api_configs": json.dumps({"0": {
        "enable": True, "tags": [], "prefix_id": "", "model_ids": [],
        "connection_type": "local", "auth_type": "bearer",
        "headers": {
            "X-OpenWebUI-User-Name": "{{USER_NAME}}",
            "X-OpenWebUI-User-Id": "{{USER_ID}}",
            "X-OpenWebUI-User-Email": "{{USER_EMAIL}}",
            "X-OpenWebUI-Chat-Id": "{{CHAT_ID}}",
            "X-OpenWebUI-Message-Id": "{{MESSAGE_ID}}",
            "X-OpenWebUI-Task": "{{TASK}}",
        },
    }}),
}

for k, v in rows.items():
    con.execute(
        "INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
        (k, v, now),
    )
    print(f"  ✓ {k}")
con.commit()
PY

  # Контейнер держит настройки в памяти — перезапуск, чтобы прочитал новые.
  docker restart open-webui >/dev/null 2>&1
  have "контейнер перезапущен с новыми настройками"
else
  warn "не удалось заглянуть в базу Open WebUI"
  todo "проверить настройки Open WebUI вручную (Настройки → Подключения)"
fi

# ── итог ─────────────────────────────────────────────────────────────────────

printf '\n%s────────────────────────────────────────────%s\n' "$D" "$N"
if (( ${#TODO[@]} )); then
  printf '%sОсталось:%s\n' "$B" "$N"
  for t in "${TODO[@]}"; do printf '  · %s\n' "$t"; done
  printf '\nЗатем запусти этот скрипт ещё раз.\n'
else
  printf '%s%sВсё готово.%s\n' "$B" "$G" "$N"
fi

cat <<EOF

  Терминал:   zim-claude
  Чат:        http://127.0.0.1:3000
  Поиск:      zim-memory search "запрос"
  Запуск всего сразу:  ~/start-all.sh

EOF

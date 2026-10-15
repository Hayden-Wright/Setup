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

printf '%sZim-стек: установка%s\n' "$B" "$N"
printf '%sМожно запускать повторно — уже сделанное пропускается.%s\n' "$D" "$N"

# ── 1. базовые пакеты ────────────────────────────────────────────────────────

step "1/8  Базовые пакеты"

MISSING=()
for pkg in git curl python3; do
  need "$pkg" || MISSING+=("$pkg")
done
python3 -c 'import venv' >/dev/null 2>&1 || MISSING+=("python3-venv")

if (( ${#MISSING[@]} )); then
  warn "не хватает: ${MISSING[*]}"
  echo "      сейчас установим (понадобится пароль от системы)"
  sudo apt update -qq && sudo apt install -y "${MISSING[@]}" || { fail "не удалось установить пакеты"; exit 1; }
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
  sudo apt install -y docker.io || { fail "не удалось поставить Docker"; exit 1; }
  sudo systemctl enable --now docker >/dev/null 2>&1
  sudo usermod -aG docker "$USER" >/dev/null 2>&1
  fail "Docker поставлен. Закрой это окно терминала, открой заново и запусти скрипт снова"
  exit 0
fi

# ── 3. Claude Code ───────────────────────────────────────────────────────────

step "3/8  Claude Code"

if need claude; then
  ok "уже установлен: $(claude --version 2>/dev/null | head -1)"
else
  have "устанавливаю с официального сайта..."
  curl -fsSL https://claude.ai/install.sh | bash || { fail "не удалось установить Claude Code"; exit 1; }
  export PATH="$HOME/.local/bin:$PATH"
  need claude && ok "установлен" || { fail "установился, но не виден — запусти скрипт ещё раз"; exit 0; }
fi

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
( cd "$ZIM_DIR" && ./install.sh ) 2>&1 | sed 's/^/      /'
[[ -x "$HOME/.local/bin/zim-claude" ]] && ok "zim-claude установлен" || warn "проверь вывод выше"

# ── 5. доработки ─────────────────────────────────────────────────────────────

step "5/8  Доработки (веб-поиск, zim-memory, конфиги)"

( cd "$SRC" && ./deploy.sh ) 2>&1 | sed 's/^/      /'

# PATH для zsh: install.sh прописывает только ~/.bashrc, а оболочка по
# умолчанию в Ubuntu — zsh, если её поставили.
if [[ -f "$HOME/.zshrc" ]] && ! grep -q '.local/bin' "$HOME/.zshrc"; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.zshrc"
  have "добавил ~/.local/bin в ~/.zshrc"
fi

# ── 6. SearxNG ───────────────────────────────────────────────────────────────

step "6/8  SearxNG (локальный веб-поиск)"

docker network inspect zim-net >/dev/null 2>&1 || docker network create zim-net >/dev/null 2>&1

if docker ps -a --format '{{.Names}}' | grep -qx searxng; then
  docker start searxng >/dev/null 2>&1
  have "контейнер уже есть — запущен"
else
  docker run -d --name searxng --restart unless-stopped \
    -p 127.0.0.1:8888:8080 \
    -v "$HOME/.config/zim-claude/searxng/settings.yml:/etc/searxng/settings.yml:ro" \
    searxng/searxng:latest >/dev/null 2>&1 \
    && ok "запущен" || { fail "не удалось запустить SearxNG"; exit 1; }
fi
docker network connect zim-net searxng >/dev/null 2>&1

# Ждём, пока поднимется, и проверяем именно JSON: без formats: json SearxNG
# отвечает 403, и LiteLLM получает пустую выдачу.
for _ in $(seq 1 20); do
  if curl -sf 'http://127.0.0.1:8888/search?q=test&format=json' -o /dev/null 2>/dev/null; then
    ok "отвечает"; break
  fi
  sleep 1
done

# ── 7. cptr ──────────────────────────────────────────────────────────────────

step "7/8  cptr (агент с доступом к диску)"

CPTR_VENV="$HOME/.local/share/cptr-venv"
CPTR_PY="$CPTR_VENV/bin/python"

if [[ -x "$CPTR_VENV/bin/cptr" ]]; then
  have "уже установлен"
else
  have "ставлю cptr 0.9.21 (версия зафиксирована — под неё написаны патчи)"
  python3 -m venv "$CPTR_VENV" || { fail "не удалось создать venv"; exit 1; }
  "$CPTR_VENV/bin/pip" install --quiet --disable-pip-version-check -U pip
  "$CPTR_VENV/bin/pip" install --quiet --disable-pip-version-check 'cptr==0.9.21' \
    || { fail "не удалось поставить cptr"; exit 1; }
  ok "установлен"
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
"$HOME/start-cptr.sh" start >/dev/null 2>&1
if curl -sf http://127.0.0.1:8100/api/config -o /dev/null 2>/dev/null; then
  ok "cptr работает на http://127.0.0.1:8100"
else
  warn "cptr не отвечает — смотри /tmp/cptr.log"
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
  URL="$("$HOME/start-cptr.sh" url 2>/dev/null)"
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
if grep -q '^OPENAI_API_KEY=sk-cptr-' "$ENV_FILE" 2>/dev/null; then
  have "ключ cptr уже прописан"
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
  ok "запущен"
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

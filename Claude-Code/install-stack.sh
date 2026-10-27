#!/usr/bin/env bash
# install-stack.sh — поставить весь стек одной командой.
#
#   cd ~/zim-claude/deploy && ./install-stack.sh
#
# Скрипт можно запускать сколько угодно раз: он смотрит, что уже сделано, и
# доделывает только оставшееся.
#
# Ставит: Docker, доработки zim-claude (веб-поиск, zim-memory, настройки
# Claude Code), SearxNG, плюс ярлыки на рабочем столе Windows. Браузерного
# чата (Open WebUI + cptr) здесь больше нет: его заменяет Claude Desktop,
# который работает напрямую с шлюзом zim-claude на :4002. Сам zim-claude и прокси ставит install.sh из корня репозитория —
# этот скрипт вызывает его, если их нет.

set -uo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES="$SRC/files"

# Чекаут zim-claude. Здесь он нужен ровно затем, чтобы его запустить
# (install.sh) и позже поднять Desktop-шлюз. Своих файлов туда не кладём —
# см. комментарий в deploy.sh.
ZIM_CLAUDE_DIR="${ZIM_CLAUDE_DIR:-$HOME/zim-claude}"

# Всё, что принадлежит этому набору, живёт отдельно от обоих чекаутов.
RUNTIME="${ZIM_CLAUDE_RUNTIME_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zim-claude}"

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

[[ -d "$FILES" ]] || { fail "нет каталога files/ рядом со скриптом — запусти из deploy/"; exit 1; }

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
    # В WSL systemd поднимает Docker сам; без systemd — service docker start.
    sudo -n service docker start >/dev/null 2>&1 || sudo service docker start >/dev/null 2>&1 || true
    if ! docker ps >/dev/null 2>&1; then
      fail "закрой это окно терминала, открой заново и запусти скрипт снова"
      exit 0
    fi
    ok "Docker запущен"
  fi
else
  warn "Docker не установлен"
  # docker.io лежит в компоненте universe. На свежей Ubuntu он обычно включён,
  # но если выключен (или система ставилась минимальной), apt отвечает
  #   Package 'docker.io' has no installation candidate
  if ! sudo apt-get install -y docker.io; then
    warn "не вышло напрямую — включаю компонент universe и пробую снова"
    sudo apt-get install -y software-properties-common >/dev/null 2>&1
    sudo add-apt-repository -y universe >/dev/null 2>&1
    sudo apt-get update -qq || warn "apt update прошёл с ошибками, продолжаю"
    sudo apt-get install -y docker.io || { fail "не удалось поставить Docker"; exit 1; }
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1 || true
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
  SUDOERS_TMP="$(mktemp)"
  printf '%s ALL=(ALL) NOPASSWD: %s docker *\n' "$USER" "$SERVICE_BIN" >"$SUDOERS_TMP"
  if ! visudo -cf "$SUDOERS_TMP" >/dev/null 2>&1; then
    warn "правило не прошло проверку синтаксиса — sudoers не трогаю"
  elif sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS"; then
    ok "правило добавлено: $SUDOERS"
  else
    # install вернул ошибку (например, sudo спросил пароль и не получил его).
    # Без этой проверки успех печатался бы всегда: set -uo pipefail без -e
    # не останавливает скрипт, и следующая строка выполнилась бы как обычно.
    warn "не удалось записать $SUDOERS — start-all.sh будет спрашивать пароль"
  fi
  rm -f "$SUDOERS_TMP"
fi

# ── 3. Claude Code и zim-claude ──────────────────────────────────────────────

step "3/8  Claude Code и zim-claude"

if need claude; then
  ok "Claude Code уже установлен: $(claude --version 2>/dev/null | head -1)"
else
  warn "Claude Code не найден"
  TMP_INST="$(mktemp)"
  if curl -fsSL --connect-timeout 15 --max-time 120 https://claude.ai/install.sh -o "$TMP_INST" 2>/dev/null \
     && bash "$TMP_INST"; then
    ok "установлен"
  else
    fail "не удалось скачать Claude Code — проверь связь с downloads.claude.ai"
    todo "поставить Claude Code (curl -fsSL https://claude.ai/install.sh | bash)"
  fi
  rm -f "$TMP_INST"
fi

if [[ -x "$HOME/.local/bin/zim-claude" ]]; then
  ok "zim-claude уже установлен"
else
  # Клонируем апстрим сами, если чекаута нет: с этого момента он принадлежит
  # автообновлению zim-claude, а наш набор в нём ничего не держит.
  if [[ ! -d "$ZIM_CLAUDE_DIR/.git" ]]; then
    have "клонирую zim-claude в $ZIM_CLAUDE_DIR"
    git clone --quiet https://github.com/Mr-Destroyer/zim-claude "$ZIM_CLAUDE_DIR" \
      || { fail "не удалось склонировать zim-claude"; exit 1; }
  fi
  have "запускаю install.sh из $ZIM_CLAUDE_DIR"
  ( cd "$ZIM_CLAUDE_DIR" && ./install.sh ) 2>&1 | sed 's/^/      /'
  if [[ -x "$HOME/.local/bin/zim-claude" ]]; then
    ok "zim-claude установлен"
  else
    fail "zim-claude не установился — смотри вывод выше"
    exit 1
  fi
fi

# Диалог «Do you trust the files in this folder?» при каждом запуске. Claude
# Code хранит ответ в ~/.claude.json, в projects[<каталог>].hasTrustDialogAccepted,
# и спрашивает заново, пока ключа нет. Доверие наследуется вложенными
# каталогами, поэтому одной записи на $HOME хватает на всё внутри — и на
# терминал и на любые агентские сессии внутри $HOME.
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
    print("  ! ~/.claude.json не читается — пропускаю, доверие спросят один раз")
    raise SystemExit(0)

if not isinstance(data, dict):
    raise SystemExit(0)

projects = data.get("projects")
if not isinstance(projects, dict):
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

# ── 4. доработки ─────────────────────────────────────────────────────────────

step "4/8  Доработки (веб-поиск, zim-memory, настройки Claude Code)"

( cd "$SRC" && ./deploy.sh ) 2>&1 | sed 's/^/      /'
if (( PIPESTATUS[0] != 0 )); then
  fail "deploy.sh завершился с ошибкой — смотри вывод выше"
  exit 1
fi

# deploy.sh заменил ~/tokenjuice/litellm-config.yaml (добавил перехват
# веб-поиска), но уже запущенный прокси держит в памяти СТАРЫЙ конфиг.
# Перезапускаем, иначе веб-поиск не заработает.
have "перезапускаю прокси, чтобы подхватил новый конфиг"
"$HOME/.local/bin/start-litellm.sh" restart 2>&1 | tail -2 | sed 's/^/      /'
curl -sf http://127.0.0.1:4000/health/liveliness -o /dev/null --max-time 3 2>/dev/null \
  && ok "прокси :4000 отвечает" \
  || { warn "прокси :4000 не поднялся — смотри /tmp/litellm-proxy.log"; todo "поднять прокси :4000"; }

if [[ -x "$ZIM_CLAUDE_DIR/claude-desktop-integration/start-desktop-proxy.sh" ]]; then
  ( cd "$ZIM_CLAUDE_DIR/claude-desktop-integration" && ./start-desktop-proxy.sh restart ) \
    2>&1 | tail -2 | sed 's/^/      /'
  curl -sf http://127.0.0.1:4002/health/liveliness -o /dev/null --max-time 3 2>/dev/null \
    && ok "прокси :4002 отвечает" \
    || { warn "прокси :4002 не поднялся — смотри /tmp/litellm-desktop.log"; todo "поднять прокси :4002"; }
fi

# ── 5. SearxNG ───────────────────────────────────────────────────────────────

step "5/8  SearxNG (локальный веб-поиск)"

docker network inspect zim-net >/dev/null 2>&1 || docker network create zim-net >/dev/null 2>&1

# Образ весит ~380 МБ, и на свежей машине его нужно скачать. Скачивание
# показываем, а ошибку докера печатаем как есть.
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
    warn "контейнер запущен, но не отвечает на 127.0.0.1:8888 за 30 с"
    warn "смотри лог:  docker logs searxng"
    SEARXNG_OK=0
  fi
fi

if (( ! SEARXNG_OK )); then
  warn "веб-поиск работать не будет, пока SearxNG не поднимется"
  todo "запустить SearxNG (см. README, раздел «Если что-то не так»)"
fi
# ── 8. ярлыки Windows ────────────────────────────────────────────────────────

step "6/8  Ярлыки на рабочем столе Windows"

# Ярлыки делает PowerShell-скрипт: из WSL виден рабочий стол через /mnt/c,
# но .lnk — это COM-объект Windows, и собирать его бинарно руками незачем.
POWERSHELL=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
if [[ -x "$POWERSHELL" ]]; then
  PS1_WIN="$(wslpath -w "$FILES/windows/create-shortcuts.ps1" 2>/dev/null || true)"
  if [[ -z "$PS1_WIN" ]]; then
    warn "не удалось перевести путь для Windows"
    todo "запустить deploy/files/windows/create-shortcuts.ps1 вручную"
  else
    # Код возврата берём из PIPESTATUS: в конвейере с tr/sed он иначе всегда 0,
    # и упавший PowerShell выглядел бы как успех.
    "$POWERSHELL" -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" 2>&1 \
      | tr -d '\r' | sed 's/^/      /'
    if (( PIPESTATUS[0] == 0 )); then
      ok "ярлыки созданы"
    else
      warn "PowerShell завершился с ошибкой — смотри вывод выше"
      todo "создать ярлыки вручную (deploy/files/windows/create-shortcuts.ps1)"
    fi
  fi
else
  have "Windows рядом не видно — ярлыки не нужны"
fi

# ── 9. автообновление набора ─────────────────────────────────────────────────

step "7/8  Автообновление"

# Набор — надстройка над zim-claude. Когда апстрим обновляется, его install.sh
# переустанавливает своё и затирает то, что мы положили поверх (конфиг
# LiteLLM с перехватом поиска — первым делом). Поэтому мало обновлять только
# набор: после каждого обновления апстрима доработки надо наложить заново.
#
# Всё это делает zim-deploy-update.sh: сначала дёргает обновление zim-claude,
# потом подтягивает себя, потом прогоняет deploy.sh. Скрипт кладём в
# ~/.local/bin — оттуда его найдёт и ярлык, и человек.

put_update_script() {
  install -D -m 755 -- "$FILES/zim-deploy-update.sh" "$HOME/.local/bin/zim-deploy-update.sh" \
    || { fail "не удалось положить zim-deploy-update.sh"; return 1; }
  ok "zim-deploy-update.sh на месте"
}

if put_update_script; then
  # Автообновление работает только по git-чекауту: обновлятор делает fetch и
  # fast-forward, а с тарболом (как в инструкции «одна команда») этого не
  # сделать. Поэтому если набор распакован, а не склонирован — клонируем его
  # отдельно в ~/.zim-setup и дальше обновляем уже клон. Установка при этом
  # продолжает идти из распакованного каталога: файлы те же.
  UPDATE_CONF="$HOME/.local/share/zim-deploy/update.conf"
  REPO_URL="${ZIM_DEPLOY_REPO_URL:-https://github.com/Hayden-Wright/Setup}"
  REPO_SUBDIR="Claude-Code"
  CLONE_DIR="${ZIM_DEPLOY_CLONE_DIR:-$HOME/.zim-setup}"

  update_repo_dir="$SRC"
  update_branch="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ ! -d "$SRC/.git" || -z "$update_branch" || "$update_branch" == "HEAD" ]]; then
    have "набор распакован, а не склонирован — клонирую для автообновления"
    if [[ -d "$CLONE_DIR/.git" ]]; then
      update_branch="$(git -C "$CLONE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
      update_repo_dir="$CLONE_DIR"
      ok "использую существующий клон: $CLONE_DIR"
    elif git clone --quiet "$REPO_URL" "$CLONE_DIR" 2>/dev/null; then
      update_branch="$(git -C "$CLONE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
      update_repo_dir="$CLONE_DIR"
      ok "склонирован в $CLONE_DIR"
    else
      warn "склонировать не удалось — автообновление набора выключено"
      todo "склонировать $REPO_URL вручную, если нужно автообновление"
      update_repo_dir=""
    fi
  fi

  if [[ -n "$update_repo_dir" ]]; then
    mkdir -p "$(dirname "$UPDATE_CONF")"
    {
      printf '# Пишет install-stack.sh — читает zim-deploy-update.sh.\n'
      printf 'ZIM_DEPLOY_AUTO_UPDATE=1\n'
      printf 'ZIM_DEPLOY_REPO_DIR=%q\n' "$update_repo_dir"
      printf 'ZIM_DEPLOY_REPO_BRANCH=%q\n' "$update_branch"
      # deploy.sh лежит в корне клона репозитория Setup — во вложенной папке.
      printf 'ZIM_DEPLOY_SUBDIR=%q\n' "$REPO_SUBDIR"
    } >"$UPDATE_CONF"
    chmod 600 -- "$UPDATE_CONF"
    ok "автообновление включено ($update_branch в $update_repo_dir)"
  fi

  # Еженедельный запуск через cron — на случай, если человек неделю не
  # открывал терминал. В терминале то же самое делает хук zim-claude, так что
  # это подстраховка, а не основной путь. flock внутри скрипта не даст двум
  # копиям работать одновременно.
  if command -v crontab >/dev/null 2>&1; then
    CRON_LINE="@daily $HOME/.local/bin/zim-deploy-update.sh >/dev/null 2>&1"
    # Задание переписываем, а не «добавляем, если нет»: путь к скрипту может
    # смениться (другой $HOME, переезд), и старая строка тогда молча висит
    # нерабочей. Заодно убираем дубликаты, если они накопились.
    #
    # Уже настроено = наша строка встречается ровно один раз и совпадает
    # побайтно. Любое расхождение (старый путь, дубликат) — переписываем.
    existing="$(crontab -l 2>/dev/null || true)"
    ours="$(printf '%s\n' "$existing" | grep 'zim-deploy-update\.sh' || true)"
    if [[ "$ours" == "$CRON_LINE" ]]; then
      have "задание cron уже стоит"
    else
      cleaned="$(printf '%s\n' "$existing" | grep -v 'zim-deploy-update\.sh' || true)"
      { printf '%s\n' "$cleaned" | sed '/^$/d'
        printf '%s\n' "$CRON_LINE"
      } | crontab - 2>/dev/null \
        && ok "задание cron обновлено (@daily)" \
        || have "cron недоступен — обновление будет при запуске терминала"
    fi
  fi
fi

# ── 10. PATH и итог ──────────────────────────────────────────────────────────

step "8/8  PATH"

# ~/.local/bin в ~/.bashrc прописывает install.sh; здесь страхуемся на случай,
# если его запускали с --no-rc.
if [[ -f "$HOME/.bashrc" ]] && ! grep -q '.local/bin' "$HOME/.bashrc"; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.bashrc"
  have "добавил ~/.local/bin в ~/.bashrc"
else
  have "PATH уже настроен"
fi

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
  Desktop:    Claude Desktop → Gateway http://127.0.0.1:4002
  Поиск:      zim-memory search "запрос"
  Запуск всего сразу:  ~/start-all.sh

EOF

#!/usr/bin/env bash
# zim-deploy-update.sh — тихо подтянуть сам набор и переустановить доработки.
#
#   zim-deploy-update.sh          обычный запуск (соблюдает интервал)
#   zim-deploy-update.sh --now    проверить прямо сейчас, не ждать интервала
#
# Зачем нужен. Набор — это надстройка над zim-claude: он кладёт конфиги,
# патчи и настройки ПОВЕРХ того, что ставит install.sh из апстрима. Когда
# апстрим обновляется, его install.sh переустанавливает своё — и доработки
# надо наложить заново. Этот скрипт делает обе половины:
#
#   1. запускает обновление zim-claude (если оно настроено) — апстрим
#      обновляется по своим правилам, fast-forward, со своим логом;
#   2. подтягивает этот репозиторий тем же способом;
#   3. прогоняет deploy.sh — он идемпотентен и только раскладывает файлы.
#
# Чего он НЕ делает:
#   - не запускает install-stack.sh: тот просит sudo;
#   - не перезапускает прокси и контейнеры: работающая сессия не должна
#     терять соединение из-за фонового обновления;
#   - не делает merge, reset, stash или force: разошедшийся чекаут трогать
#     нельзя, это решает человек.
#
# Конфигурация пишется install-stack.sh в ~/.local/share/zim-deploy/update.conf:
#
#   ZIM_DEPLOY_AUTO_UPDATE=1|0
#   ZIM_DEPLOY_REPO_DIR="/path/to/checkout"
#   ZIM_DEPLOY_REPO_BRANCH="main"
#
# Переменные окружения:
#
#   ZIM_DEPLOY_UPDATE_INTERVAL=3600  секунд между проверками (0 = каждый раз)
#   ZIM_DEPLOY_UPDATE_LOG=...        путь к логу
#   ZIM_DEPLOY_UPDATE_CONF=...       путь к конфигу
#   ZIM_DEPLOY_STATE_DIR=...         каталог состояния
#   ZIM_DEPLOY_NO_UPSTREAM=1         не трогать zim-claude, только себя

set -uo pipefail

STATE_DIR="${ZIM_DEPLOY_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zim-deploy}"
CONF="${ZIM_DEPLOY_UPDATE_CONF:-$STATE_DIR/update.conf}"
LOG="${ZIM_DEPLOY_UPDATE_LOG:-$STATE_DIR/update.log}"
STAMP="$STATE_DIR/last-update-check"
LOCK="$STATE_DIR/update.lock"
INTERVAL="${ZIM_DEPLOY_UPDATE_INTERVAL:-3600}"

FORCE=0
case "${1:-}" in
  --now|-f|--force) FORCE=1 ;;
  -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

mkdir -p -- "$STATE_DIR" 2>/dev/null || exit 0
chmod 700 -- "$STATE_DIR" 2>/dev/null || true

# Лог растёт вечно, если его не подрезать: ротация при 256 КиБ.
if [[ -f "$LOG" ]] && (( $(stat -c%s "$LOG" 2>/dev/null || echo 0) > 262144 )); then
  mv -f -- "$LOG" "$LOG.1" 2>/dev/null || true
fi

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG" 2>/dev/null || true; }
stamp() { printf '%s\n' "$(date +%s)" >"$STAMP" 2>/dev/null || true; }

# Один прогон за раз. Без этого две сессии, открытые одновременно, обе
# делали бы fetch и обе запускали deploy.sh — файлы переписывались бы
# из-под читающего.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" 2>/dev/null || exit 0
  flock -n 9 || exit 0
fi

if (( ! FORCE )) && [[ -f "$STAMP" ]]; then
  last="$(cat "$STAMP" 2>/dev/null || true)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if (( $(date +%s) - last < INTERVAL )); then
    exit 0
  fi
fi

if [[ ! -r "$CONF" ]]; then
  log "update.conf нет — автообновление набора не настроено"
  exit 0
fi

# shellcheck disable=SC1090  # пишет install-stack.sh, форма фиксированная
. "$CONF"

if [[ "${ZIM_DEPLOY_AUTO_UPDATE:-0}" != "1" ]]; then
  exit 0
fi

repo="${ZIM_DEPLOY_REPO_DIR:-}"
branch="${ZIM_DEPLOY_REPO_BRANCH:-}"

if [[ -z "$repo" || -z "$branch" || "$branch" == "HEAD" ]]; then
  log "автообновление не настроено (нет пути или ветки)"
  exit 0
fi
if [[ ! -d "$repo/.git" ]]; then
  log "чекаут пропал: $repo — пропускаю"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  log "git не найден — пропускаю"
  exit 0
fi

# --- 1. апстрим --------------------------------------------------------------
#
# Сначала zim-claude: его install.sh переустанавливает своё, и накладывать
# доработки имеет смысл только поверх актуальной версии. Скрипт сам
# rate-limited и всегда возвращает 0, поэтому ждать его безопасно.
if [[ "${ZIM_DEPLOY_NO_UPSTREAM:-0}" != "1" ]]; then
  upstream="$HOME/.local/bin/zim-claude-update.sh"
  if [[ -x "$upstream" ]]; then
    before="$(git -C "${ZIM_CLAUDE_DIR:-$HOME/zim-claude}" rev-parse HEAD 2>/dev/null || true)"
    ZIM_CLAUDE_UPDATE_INTERVAL=0 "$upstream" >/dev/null 2>&1 || true
    after="$(git -C "${ZIM_CLAUDE_DIR:-$HOME/zim-claude}" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
      log "zim-claude обновлён ${before:0:12} -> ${after:0:12}"
    fi
  fi
fi

# --- 2. сам набор ------------------------------------------------------------

# Только отслеживаемые правки блокируют обновление. Untracked не мешает: если
# файл всё же будет перезаписан, fast-forward упадёт и это попадёт в лог.
dirty="$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null || true)"
if [[ -n "$dirty" ]]; then
  log "в чекауте есть локальные правки — не обновляю ($repo)"
  stamp
  exit 0
fi

run_git() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "${ZIM_DEPLOY_UPDATE_TIMEOUT:-20}" git "$@"
  else
    git "$@"
  fi
}

if ! run_git -C "$repo" fetch --quiet origin "$branch" >>"$LOG" 2>&1; then
  log "fetch не прошёл для origin/$branch — попробую позже"
  stamp
  exit 0
fi

local_rev="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
remote_rev="$(git -C "$repo" rev-parse "refs/remotes/origin/$branch" 2>/dev/null || true)"

if [[ -z "$local_rev" || -z "$remote_rev" ]]; then
  log "не удалось определить ревизии $branch — пропускаю"
  stamp
  exit 0
fi

if [[ "$local_rev" != "$remote_rev" ]]; then
  if ! git -C "$repo" merge-base --is-ancestor "$local_rev" "$remote_rev" 2>/dev/null; then
    log "локальная $branch разошлась с origin/$branch — не обновляю"
    stamp
    exit 0
  fi
  if ! git -C "$repo" merge --ff-only --quiet "$remote_rev" >>"$LOG" 2>&1; then
    log "fast-forward не прошёл — не обновляю"
    stamp
    exit 0
  fi
  log "набор обновлён ${local_rev:0:12} -> ${remote_rev:0:12}"
else
  log "набор уже актуален (${local_rev:0:12})"
fi

# --- 3. переустановка --------------------------------------------------------
#
# deploy.sh идемпотентен: он сравнивает файлы и трогает только изменившиеся.
# Запускаем его ВСЕГДА, даже когда git ничего не подтянул — install.sh
# апстрима мог перезаписать конфиг, и доработки надо вернуть на место.
# deploy.sh может лежать и в корне чекаута (если набор — отдельный
# репозиторий), и во вложенной папке (внутри Setup). Порядок: явный
# подкаталог из конфига, затем корень, затем известная папка.
sub="${ZIM_DEPLOY_SUBDIR:-}"
deploy=""
for cand in "${sub:+$repo/$sub/deploy.sh}" "$repo/deploy.sh" "$repo/Claude-Code/deploy.sh"; do
  [[ -n "$cand" && -f "$cand" ]] && { deploy="$cand"; break; }
done

# Конфиг прокси — единственный файл, чью смену работающий процесс не заметит
# сам: LiteLLM читает его один раз при старте. Если deploy.sh его переписал
# (например, install.sh апстрима вернул свой вариант без перехвата поиска),
# то без перезапуска веб-поиск молча деградирует до сниппетов — и заметить
# это можно только по качеству ответов. Поэтому сравниваем до и после.
proxy_conf="${ZIM_CLAUDE_TOKENJUICE_DIR:-$HOME/tokenjuice}/litellm-config.yaml"
conf_before="$(sha256sum "$proxy_conf" 2>/dev/null | cut -d' ' -f1)"

if [[ -f "$deploy" ]]; then
  bash "$deploy" </dev/null >>"$LOG" 2>&1
  log "deploy.sh завершился с кодом $?"
else
  log "deploy.sh не найден в $repo — файлы обновлены, но не установлены"
fi

conf_after="$(sha256sum "$proxy_conf" 2>/dev/null | cut -d' ' -f1)"
if [[ -n "$conf_after" && "$conf_before" != "$conf_after" ]]; then
  if [[ -x "$HOME/.local/bin/start-litellm.sh" ]]; then
    "$HOME/.local/bin/start-litellm.sh" restart >>"$LOG" 2>&1 \
      && log "конфиг прокси изменился — прокси перезапущен" \
      || log "конфиг прокси изменился, но перезапуск не удался"
  fi
fi

stamp
exit 0

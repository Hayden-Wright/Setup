#!/usr/bin/env bash
# deploy.sh — раскатать доработки поверх установленного zim-claude.
#
# Запускать ПОСЛЕ того, как отработал install.sh из репозитория zim-claude:
# он ставит сам CLI и оба прокси, а этот скрипт добавляет то, чего в
# репозитории нет — веб-поиск через SearxNG, zim-memory, конфиги Open WebUI
# и cptr.
#
#   ./deploy.sh              — установить / обновить
#   ./deploy.sh --dry-run    — показать, что будет сделано
#
# Всё, что перезаписывается, сохраняется рядом с меткой времени.
# Никакие ключи здесь не генерируются: env-профиль и конфиги копируются как
# есть, поэтому ключ Token Juice остаётся тем же.

set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES="$SRC/files"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

log()  { printf '\033[36m[deploy]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
skip() { printf '\033[2m  ·\033[0m %s\n' "$*"; }

# put <источник> <назначение> [права]
put() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    skip "уже на месте: ${dst/#$HOME/~}"
    return
  fi
  if [[ "$DRY" == "1" ]]; then
    log "записал бы: ${dst/#$HOME/~}"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  [[ -f "$dst" ]] && cp -p "$dst" "$dst.bak-$STAMP"
  cp "$src" "$dst"
  chmod "$mode" "$dst"
  ok "${dst/#$HOME/~}"
}

# ---------------------------------------------------------------- проверки

[[ -d "$FILES" ]] || { log "нет каталога files/ рядом со скриптом"; exit 1; }

command -v claude >/dev/null 2>&1 \
  || log "внимание: claude не найден на PATH — сначала install.sh из zim-claude"

if [[ ! -f "$HOME/claude-source/deepseek-claude" ]]; then
  log "внимание: нет ~/claude-source/deepseek-claude — его создаёт install.sh."
  log "          кладу свой, но проверь, что ключ Token Juice верный."
fi

# ---------------------------------------------------------------- zim-claude

log "1/4  zim-claude: конфиги прокси и перехват веб-поиска"
put "$FILES/claude-source/deepseek-claude"   "$HOME/claude-source/deepseek-claude" 600
put "$FILES/litellm-config.yaml"             "$HOME/litellm-config.yaml"
put "$FILES/drop_anthropic_only.py"          "$HOME/drop_anthropic_only.py"

# Модуль-колбэк LiteLLM подхватывает из ТЕКУЩЕГО каталога процесса, а не из
# конфига: `callbacks: ["drop_anthropic_only.proxy_handler_instance"]` — это
# обычный import по имени. Оба прокси стартуют из каталога интеграции, поэтому
# вторая копия обязана лежать именно там, иначе CLI-прокси упадёт на импорте.
put "$FILES/drop_anthropic_only.py"          "$HOME/zim-claude/claude-desktop-integration/drop_anthropic_only.py"
put "$FILES/litellm-config.desktop.yaml"     "$HOME/zim-claude/claude-desktop-integration/litellm-config.desktop.yaml"

# ---------------------------------------------------------------- zim-memory

log "2/4  zim-memory: поиск по заметкам и истории сессий"
put "$FILES/zim-memory/index.py"             "$HOME/.claude/zim-memory/index.py"
put "$FILES/zim-memory/hook-session-start.sh" "$HOME/.claude/zim-memory/hook-session-start.sh" 755
put "$FILES/zim-memory/zim-memory"           "$HOME/.local/bin/zim-memory" 755

# ---------------------------------------------------------------- прочее

log "3/4  SearxNG, Open WebUI, cptr"
put "$FILES/searxng-settings.yml"            "$HOME/.config/zim-claude/searxng/settings.yml"
put "$FILES/openwebui/openwebui.env"         "$HOME/zim-claude/openwebui/openwebui.env" 600
put "$FILES/openwebui/run-openwebui.sh"      "$HOME/zim-claude/openwebui/run-openwebui.sh" 755
put "$FILES/start-cptr.sh"                   "$HOME/start-cptr.sh" 755
put "$FILES/start-all.sh"                    "$HOME/start-all.sh" 755
put "$FILES/cptr-patches/gateway-images.patch"        "$HOME/zim-claude/patches/gateway-images.patch"
put "$FILES/cptr-patches/config-multiline-toml.patch" "$HOME/zim-claude/patches/config-multiline-toml.patch"

# ---------------------------------------------------------------- хук

log "4/4  хук SessionStart (доиндексация памяти при старте)"
SETTINGS="$HOME/.claude/settings.json"
if [[ "$DRY" == "1" ]]; then
  log "проверил бы хук в ${SETTINGS/#$HOME/~}"
else
  mkdir -p "$HOME/.claude"
  python3 -I - "$SETTINGS" "$FILES/claude-settings.json" <<'PY'
import json, pathlib, sys

target, source = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
want = json.loads(source.read_text())["hooks"]

if target.exists():
    try:
        data = json.loads(target.read_text())
    except ValueError:
        print("  settings.json не парсится — оставляю как есть, добавь хук вручную")
        raise SystemExit(0)
else:
    data = {}

# Не затираем чужие хуки: заменяем только SessionStart.
hooks = data.setdefault("hooks", {})
if hooks.get("SessionStart") == want["SessionStart"]:
    print("  · хук уже стоит")
else:
    if "SessionStart" in hooks:
        target.with_suffix(f".json.bak-hook").write_text(target.read_text())
    hooks["SessionStart"] = want["SessionStart"]
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print("  ✓ хук прописан в settings.json")
PY
fi

# ---------------------------------------------------------------- итог

if [[ "$DRY" == "0" ]]; then
  log "готово. Дальше:"
  cat <<'EOF'

  1. Перезапустить прокси:      ~/.local/bin/start-litellm.sh restart
  2. Перезапустить Desktop-шлюз (если нужен):
        cd ~/zim-claude/claude-desktop-integration && ./start-desktop-proxy.sh restart
  3. Открыть НОВЫЙ терминал (подхватить PATH и ~/.local/bin/zim-memory)
  4. Проверить:                 zim-memory stats

EOF
fi

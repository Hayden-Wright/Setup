#!/usr/bin/env bash
# deploy.sh — раскатать доработки поверх установленного zim-claude.
#
# Запускать ПОСЛЕ install.sh из корня репозитория: он ставит CLI и прокси, а
# этот скрипт добавляет то, чего в нём нет — перехват веб-поиска, zim-memory,
# настройки Claude Code и конфиги браузерной половины.
#
#   ./deploy.sh              — установить / обновить
#   ./deploy.sh --dry-run    — показать, что будет сделано
#
# Всё, что перезаписывается, сохраняется рядом с меткой времени.
# Никакие ключи здесь не генерируются: профиль ~/tokenjuice/source не
# трогается вовсе, поэтому ключ Token Juice остаётся тем же.

set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES="$SRC/files"

# Каталог zim-claude (чекаут Mr-Destroyer/zim-claude). Только ЧИТАЕМ и только
# ради его собственных файлов — claude-desktop-integration. Ничего сюда не
# пишем: чекаут обновляется автообновлением по fast-forward, и любой наш файл
# внутри него рано или поздно упрётся в «untracked file would be overwritten»,
# после чего обновления встанут навсегда.
ZIM_CLAUDE_DIR="${ZIM_CLAUDE_DIR:-$HOME/zim-claude}"

# Сюда складывается всё, что принадлежит этому набору: конфиг Open WebUI,
# патчи cptr. Отдельно от чекаутов — и апстрима, и нашего.
RUNTIME="${ZIM_CLAUDE_RUNTIME_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zim-claude}"

TOKENJUICE_DIR="${ZIM_CLAUDE_TOKENJUICE_DIR:-$HOME/tokenjuice}"
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

# put_env <источник> <назначение> — как put, но значения ключей, которые уже
# есть в файле-назначении, остаются: шаблон их оставляет пустыми, а заполняет
# их install-stack.sh под конкретную машину.
#
# Без этого повторный запуск затирал бы openwebui.env шаблоном: WEBUI_SECRET_KEY
# и OPENAI_API_KEY снова оказывались пустыми, скрипт генерировал НОВЫЙ секрет
# сессий (все, кто был в чате, разлогинивались) и создавал в cptr второй ключ
# при живом первом.
put_env() {
  local src="$1" dst="$2" mode="${3:-644}" k
  if [[ "$DRY" == "1" ]]; then
    log "обновил бы (ключи сохранил): ${dst/#$HOME/~}"
    return
  fi
  if [[ ! -f "$dst" ]]; then
    put "$src" "$dst" "$mode"
    return
  fi
  mkdir -p "$(dirname "$dst")"

  # Собираем результат во временный файл и сравниваем с текущим ДО записи.
  # Без этого каждый запуск создавал бы .bak с ключами, даже когда содержимое
  # не изменилось, — а deploy.sh теперь гоняется обновлятором каждый час.
  # Сутки такого «обновления» оставили бы 24 копии секретов на диске.
  local tmp
  tmp="$(mktemp "$dst.XXXXXX")" || return 1
  cp "$src" "$tmp"
  for k in WEBUI_SECRET_KEY OPENAI_API_KEY; do
    local have
    have="$(sed -n "s/^$k=//p" "$dst" | head -1)"
    [[ -n "$have" ]] || continue
    python3 -I - "$tmp" "$k" "$have" <<'PY' || true
import pathlib, re, sys
path, key, value = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
text = re.sub(rf'^{re.escape(key)}=.*$', f'{key}={value}', text, flags=re.M)
path.write_text(text)
PY
  done
  chmod "$mode" "$tmp"

  if cmp -s "$tmp" "$dst"; then
    rm -f -- "$tmp"
    skip "уже на месте: ${dst/#$HOME/~}"
    return
  fi
  cp -p "$dst" "$dst.bak-$STAMP"
  mv -f -- "$tmp" "$dst"
  chmod "$mode" "$dst"
  ok "${dst/#$HOME/~} (ключи сохранены)"
}

# ---------------------------------------------------------------- проверки

[[ -d "$FILES" ]] || { log "нет каталога files/ рядом со скриптом"; exit 1; }

command -v claude >/dev/null 2>&1 \
  || log "внимание: claude не найден на PATH — сначала install.sh"

if [[ ! -f "$TOKENJUICE_DIR/source" ]]; then
  log "внимание: нет $TOKENJUICE_DIR/source — его создаёт install.sh."
  log "          без него прокси не поднимется (ключ берётся оттуда)."
fi

# ---------------------------------------------------------------- прокси

log "1/4  прокси: веб-поиск и вырезание Anthropic-only полей"

# Конфиги читаются из ~/tokenjuice/ — там же, где профиль с ключом. Модель
# внутри уже new: deepseek-v4.1-flash-1017 под Token Juice.
put "$FILES/litellm-config.yaml"          "$TOKENJUICE_DIR/litellm-config.yaml"
put "$FILES/litellm-config.desktop.yaml"  "$TOKENJUICE_DIR/litellm-config.desktop.yaml"

# Колбэк LiteLLM грузит как модуль из каталога КОНФИГА (get_instance_fn:
# spec_from_file_location по os.path.dirname(config_file_path)), а при
# неудаче — обычным import из текущего каталога. Конфиг всегда лежит в
# ~/tokenjuice/, поэтому копия обязана быть там же.
#
# Вторую копию в чекаут zim-claude не кладём намеренно: файл был бы
# untracked внутри чужого репозитория, и появление такого пути в апстриме
# сломало бы fast-forward. Запасной путь start-desktop-proxy.sh (конфиг
# рядом со скриптом) работает только на свежем клоне до первого deploy.sh,
# и колбэк там всё равно не нужен.
put "$FILES/drop_anthropic_only.py" "$TOKENJUICE_DIR/drop_anthropic_only.py"

# ---------------------------------------------------------------- zim-memory

log "2/4  zim-memory: поиск по заметкам и истории сессий"
put "$FILES/zim-memory/index.py"              "$HOME/.claude/zim-memory/index.py"
put "$FILES/zim-memory/hook-session-start.sh" "$HOME/.claude/zim-memory/hook-session-start.sh" 755
put "$FILES/zim-memory/zim-memory"            "$HOME/.local/bin/zim-memory" 755

# Обновлятор набора. Его дёргает хук SessionStart выше, поэтому файл должен
# быть на месте до того, как хук начнёт работать.
put "$FILES/zim-deploy-update.sh"             "$HOME/.local/bin/zim-deploy-update.sh" 755

# ---------------------------------------------------------------- переезд

# Раньше эти файлы лежали ВНУТРИ чекаута zim-claude (~/zim-claude/openwebui/,
# ~/zim-claude/patches/). Теперь они в $RUNTIME, а из чекаута их надо убрать:
# untracked-файл там — это мина замедленного действия, при появлении такого
# пути в апстриме fast-forward упадёт с «would be overwritten».
#
# Не удаляем, а переносим: в старом openwebui.env лежат РАБОЧИЕ ключи этой
# машины (сессии Open WebUI и ключ cptr), и потерять их значит разлогинить
# человека и сломать связь с агентом.
migrate_legacy() {
  local legacy_openwebui="$ZIM_CLAUDE_DIR/openwebui"
  local legacy_patches="$ZIM_CLAUDE_DIR/patches"
  local legacy_cb="$ZIM_CLAUDE_DIR/claude-desktop-integration/drop_anthropic_only.py"
  local moved=0 f

  if [[ -f "$legacy_openwebui/openwebui.env" && ! -f "$RUNTIME/openwebui/openwebui.env" ]]; then
    if [[ "$DRY" == "1" ]]; then
      log "перенёс бы ключи из ${legacy_openwebui/#$HOME/~} в ${RUNTIME/#$HOME/~}"
    else
      mkdir -p "$RUNTIME/openwebui"
      mv -- "$legacy_openwebui/openwebui.env" "$RUNTIME/openwebui/openwebui.env"
      chmod 600 -- "$RUNTIME/openwebui/openwebui.env"
      ok "ключи перенесены из ${legacy_openwebui/#$HOME/~} в ${RUNTIME/#$HOME/~}"
    fi
    moved=1
  fi

  # Остатки прежних раскладок: бэкапы ключей и скрипт запуска.
  for f in "$legacy_openwebui"/*.bak-* "$legacy_openwebui/run-openwebui.sh"; do
    [[ -e "$f" ]] || continue
    if [[ "$DRY" == "1" ]]; then
      log "убрал бы из чекаута: ${f/#$HOME/~}"
    else
      rm -f -- "$f"
      moved=1
    fi
  done
  for f in "$legacy_patches"/*.patch; do
    [[ -e "$f" ]] || continue
    if [[ "$DRY" == "1" ]]; then
      log "убрал бы из чекаута: ${f/#$HOME/~}"
    else
      rm -f -- "$f"
      moved=1
    fi
  done
  if [[ -f "$legacy_cb" ]]; then
    if [[ "$DRY" == "1" ]]; then
      log "убрал бы из чекаута: ${legacy_cb/#$HOME/~}"
    else
      rm -f -- "$legacy_cb"
      moved=1
    fi
  fi

  # Пустые каталоги в чужом репозитории тоже не нужны.
  if [[ "$DRY" == "0" ]]; then
    rmdir -- "$legacy_openwebui" "$legacy_patches" 2>/dev/null || true
  fi

  (( moved )) || skip "чекаут zim-claude уже чист"
}

if [[ -d "$ZIM_CLAUDE_DIR/.git" ]]; then
  migrate_legacy
fi

# ---------------------------------------------------------------- прочее

log "3/4  SearxNG, Open WebUI, cptr"
put "$FILES/searxng-settings.yml"            "$RUNTIME/searxng/settings.yml"
put_env "$FILES/openwebui/openwebui.env"     "$RUNTIME/openwebui/openwebui.env" 600
put "$FILES/openwebui/run-openwebui.sh"      "$RUNTIME/openwebui/run-openwebui.sh" 755
put "$FILES/start-cptr.sh"                   "$HOME/start-cptr.sh" 755
put "$FILES/start-all.sh"                    "$HOME/start-all.sh" 755
put "$FILES/cptr-patches/gateway-images.patch"        "$RUNTIME/patches/gateway-images.patch"
put "$FILES/cptr-patches/config-multiline-toml.patch" "$RUNTIME/patches/config-multiline-toml.patch"

# ---------------------------------------------------------------- Claude Code

log "4/4  настройки Claude Code (права, хук памяти, статус-строка, MCP)"

# Статус-строка: процент занятого контекста. Кладём ДО слияния settings.json —
# statusLine ссылается на этот файл, и он должен существовать к первому
# запуску. python3 есть по шагу 1 install-stack.sh, импорты — только stdlib.
put "$FILES/statusline.py"                    "$HOME/.claude/statusline.py" 755

# settings.json: НЕ затираем целиком — у тебя там свои ключи (тема, флаги).
# Добавляем/обновляем только то, чем управляет этот скрипт: permissions и
# хук SessionStart.
if [[ "$DRY" == "1" ]]; then
  log "смержил бы permissions и хук SessionStart в ~/.claude/settings.json"
else
  python3 -I - "$HOME/.claude/settings.json" "$FILES/claude-settings.json" <<'PY'
import json, pathlib, sys

target, source = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
want = json.loads(source.read_text())

target.parent.mkdir(parents=True, exist_ok=True)
if target.exists():
    try:
        data = json.loads(target.read_text())
    except ValueError:
        print("  ! settings.json не парсится — оставляю как есть")
        raise SystemExit(0)
else:
    data = {}

changed = []

# permissions: allow-список объединяем с существующим, deny не трогаем.
if "permissions" in want:
    perms = data.setdefault("permissions", {})
    allow = perms.setdefault("allow", [])

    # Старые версии набора разрешали запуск скрипта по пути ВНУТРИ чекаута
    # zim-claude. Скрипт переехал в ~/.config/zim-claude, и разрешение на
    # старый путь больше ничего не открывает — убираем, иначе оно копится
    # у всех, кто ставил раньше.
    stale = "Bash(/home/*/zim-claude/openwebui/run-openwebui.sh:*)"
    if stale in allow:
        allow.remove(stale)
        changed.append("устаревшее разрешение")

    added = False
    for entry in want["permissions"].get("allow", []):
        if entry not in allow:
            allow.append(entry)
            added = True
    if added:
        changed.append("permissions")
    perms.setdefault("deny", want["permissions"].get("deny", []))

# Хук заменяем только SessionStart, чужие хуки не трогаем.
hooks = data.setdefault("hooks", {})
if hooks.get("SessionStart") != want["hooks"]["SessionStart"]:
    if "SessionStart" in hooks:
        target.with_suffix(".json.bak-hook").write_text(target.read_text())
    hooks["SessionStart"] = want["hooks"]["SessionStart"]
    changed.append("SessionStart hook")

# statusLine ставим, только если своего ещё нет. Свою строку человек мог
# настроить сам (как и permissions) — её не перетираем, а сообщаем об этом.
if "statusLine" in want:
    if "statusLine" not in data:
        data["statusLine"] = want["statusLine"]
        changed.append("statusLine")
    elif data["statusLine"] != want["statusLine"]:
        print("  · statusLine уже свой — не трогаю (нужен наш? удали ключ и запусти снова)")

if changed:
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"  ✓ обновлено: {', '.join(changed)}")
else:
    print("  · настройки уже на месте")
PY
fi

# MCP deploychan — публичный read-only сервер подборки знаний.
# User scope: виден из любого каталога, а не только из этого.
if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q '^deploychan'; then
    skip "MCP deploychan уже подключён"
  elif [[ "$DRY" == "1" ]]; then
    log "подключил бы MCP deploychan (user scope)"
  else
    claude mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp \
      >/dev/null 2>&1 && ok "MCP deploychan подключён" \
      || log "не удалось подключить deploychan — добавь вручную: claude mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp"
  fi
fi

# ---------------------------------------------------------------- итог

if [[ "$DRY" == "0" ]]; then
  log "готово. Дальше:"
  cat <<EOF

  1. Перезапустить прокси:      ~/.local/bin/start-litellm.sh restart
  2. Перезапустить Desktop-шлюз:
        cd ${ZIM_CLAUDE_DIR/#$HOME/~}/claude-desktop-integration && ./start-desktop-proxy.sh restart
  3. Открыть НОВЫЙ терминал (подхватить PATH и ~/.local/bin/zim-memory)
  4. Проверить:                 zim-memory stats

EOF
fi

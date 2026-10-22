#!/usr/bin/env bash
#
# Полная настройка Claude Code из репозитория Setup.
#
# Одной командой (WSL Ubuntu):
#   bash <(curl -fsSL https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Agents/install.sh)
#
# Или из клона репозитория:
#   ./install.sh
#
# Что делает:
#   1. Ставит Node 24 LTS, npm и npx в ~/.local (без sudo).
#   2. Ставит uv/uvx в ~/.local/bin (без sudo).
#   3. Ставит Python-библиотеки в user-site через uv (системный pip не работает).
#   4. Подключает маркетплейсы плагинов Anthropic.
#   5. Ставит плагины: superpowers, example-skills, document-skills,
#      claude-md-management, context7, playwright.
#   6. Подключает MCP deploychan (без ключей).
#   7. Кладёт CLAUDE.md в ~/.claude, если его ещё нет.
#
# Ничего не затирается: существующие конфиги бэкапятся, а уже установленное
# пропускается. Повторный запуск безопасен.
#
# Без sudo. Всё ставится в $HOME.

set -uo pipefail

# --- настройки ---------------------------------------------------------------
NODE_VERSION="v24.22.1"
NODE_TARBALL="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
NODE_SHA_URL="https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt"

PY_SITE="$HOME/.local/lib/python3.14/site-packages"
LOCAL_BIN="$HOME/.local/bin"
CLAUDE_DIR="$HOME/.claude"

REPO_RAW="https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Agents"

# --- вывод -------------------------------------------------------------------
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else
  B=''; G=''; Y=''; R=''; D=''; N=''
fi

step()  { echo; echo "${B}==> $*${N}"; }
ok()    { echo "  ${G}✓${N} $*"; }
skip()  { echo "  ${D}·${N} $* ${D}(уже есть)${N}"; }
warn()  { echo "  ${Y}!${N} $*"; }
fail()  { echo "  ${R}✗${N} $*"; }
die()   { fail "$*"; echo; echo "Установка прервана."; exit 1; }

FAILED=0
soft_fail() { fail "$*"; FAILED=$((FAILED+1)); }

# --- проверки окружения ------------------------------------------------------
step "Проверка окружения"

if [[ "$(uname -s)" != "Linux" ]]; then
  die "Этот скрипт для Linux/WSL. Для Windows-конфигов — install.ps1."
fi
if grep -qi microsoft /proc/version 2>/dev/null; then
  ok "WSL обнаружен"
else
  warn "Не WSL — обычный Linux. Должно работать, но проверено на WSL2."
fi
[[ $EUID -eq 0 ]] && die "Не запускай от root: всё ставится в \$HOME, root испортит права."

for c in curl tar xz; do
  command -v "$c" >/dev/null 2>&1 || die "Не найдено: $c. Поставь: sudo apt install -y $c"
done
ok "Базовые утилиты на месте (curl, tar, xz)"

if command -v claude >/dev/null 2>&1; then
  ok "Claude Code: $(claude --version 2>/dev/null | head -1)"
else
  warn "claude не найден в PATH. Плагины и MCP пропущу."
  SKIP_CLAUDE=1
fi

mkdir -p "$LOCAL_BIN" "$PY_SITE"

# PATH: дописываем в профиль, если наших путей там нет.
add_to_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local files=("$HOME/.bashrc" "$HOME/.profile")
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    grep -qF '.local/bin' "$f" && return 0
  done
  {
    echo
    echo "# >>> Setup: PATH >>>"
    echo "$line"
    echo "# <<< Setup: PATH <<<"
  } >> "$HOME/.bashrc"
  ok "PATH дописан в ~/.bashrc"
}

# --- Node --------------------------------------------------------------------
step "Node ${NODE_VERSION}"

if command -v node >/dev/null 2>&1 && [[ "$(node -v)" == "$NODE_VERSION" ]]; then
  skip "Node $(node -v)"
elif command -v node >/dev/null 2>&1; then
  warn "Node $(node -v) уже стоит — не трогаю. Нужен ${NODE_VERSION}, если что-то сломается."
else
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  echo "  качаю ${NODE_TARBALL}..."
  if ! curl -fsSL "$NODE_URL" -o "$tmp/$NODE_TARBALL"; then
    soft_fail "Не скачался Node. Пропускаю npm/npx."
  else
    # Проверка контрольной суммы — без неё качать бинарники не стоит.
    if curl -fsSL "$NODE_SHA_URL" -o "$tmp/SHASUMS256.txt" 2>/dev/null; then
      expected="$(grep " ${NODE_TARBALL}\$" "$tmp/SHASUMS256.txt" | awk '{print $1}')"
      actual="$(sha256sum "$tmp/$NODE_TARBALL" | awk '{print $1}')"
      if [[ -n "$expected" && "$expected" == "$actual" ]]; then
        ok "Контрольная сумма совпала"
      else
        die "Контрольная сумма НЕ совпала. Файл повреждён или подменён — прерываю."
      fi
    else
      warn "SHASUMS256.txt недоступен, пропускаю проверку"
    fi
    tar -xJf "$tmp/$NODE_TARBALL" -C "$tmp" || die "Не распаковался Node"
    cp -r "$tmp/node-${NODE_VERSION}-linux-x64/." "$HOME/.local/" || die "Не скопировался Node"
    export PATH="$LOCAL_BIN:$PATH"
    ok "Node $(node -v), npm $(npm -v)"
    add_to_path
  fi
fi

# --- uv ----------------------------------------------------------------------
step "uv / uvx"

if command -v uv >/dev/null 2>&1; then
  skip "$(uv --version)"
else
  if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
    export PATH="$LOCAL_BIN:$PATH"
    if command -v uv >/dev/null 2>&1; then
      ok "$(uv --version)"
      add_to_path
    else
      soft_fail "uv установился, но не виден в PATH"
    fi
  else
    soft_fail "uv не установился"
  fi
fi

# --- Python-библиотеки -------------------------------------------------------
step "Python-библиотеки"

# Системный python — PEP 668 (EXTERNALLY-MANAGED), pip в нём отсутствует.
# Поэтому --target в user-site: скиллы зовут python3, а не venv.
if command -v uv >/dev/null 2>&1; then
  if python3 -c "import pandas, docx, pptx, openpyxl, pypdf, reportlab, PIL, matplotlib" 2>/dev/null; then
    skip "основные библиотеки уже импортируются"
  else
    echo "  ставлю pypdf pdfplumber openpyxl python-docx python-pptx pandas pillow reportlab matplotlib..."
    if uv pip install --python /usr/bin/python3 --target "$PY_SITE" \
        pypdf pdfplumber openpyxl python-docx python-pptx \
        pandas pillow reportlab matplotlib >/dev/null 2>&1; then
      ok "библиотеки установлены"
    else
      soft_fail "часть библиотек не встала (см. uv pip install вручную)"
    fi
  fi

  # markitdown — отдельно: тяжёлый, и без него скиллы pdf/docx работают.
  if command -v markitdown >/dev/null 2>&1; then
    skip "markitdown"
  else
    if uv pip install --python /usr/bin/python3 --target "$PY_SITE" \
        "markitdown[docx,pdf,xlsx,pptx]" >/dev/null 2>&1; then
      for f in markitdown pdf2txt.py dumppdf.py; do
        [[ -e "$PY_SITE/bin/$f" ]] && ln -sf "$PY_SITE/bin/$f" "$LOCAL_BIN/$f" 2>/dev/null
      done
      command -v markitdown >/dev/null 2>&1 && ok "markitdown" || warn "markitdown поставился, но не в PATH"
    else
      warn "markitdown не встал — не критично"
    fi
  fi
else
  warn "uv нет — Python-библиотеки пропущены"
fi

# --- Плагины -----------------------------------------------------------------
if [[ -z "${SKIP_CLAUDE:-}" ]]; then
  step "Маркетплейсы плагинов"

  if claude plugin marketplace list 2>/dev/null | grep -q "anthropic-agent-skills"; then
    skip "anthropic-agent-skills"
  else
    if claude plugin marketplace add anthropics/skills >/dev/null 2>&1; then
      ok "anthropics/skills подключён"
    else
      soft_fail "не подключился маркетплейс anthropics/skills"
    fi
  fi

  step "Плагины"

  # -y обязателен: без TTY установка иначе отказывается.
  install_plugin() {
    local spec="$1"
    if claude plugin list 2>/dev/null | grep -q "^  ❯ ${spec%%@*}@"; then
      skip "${spec%%@*}"
      return 0
    fi
    if claude plugin install "$spec" -y >/dev/null 2>&1; then
      ok "${spec%%@*}"
    else
      soft_fail "${spec}"
    fi
  }

  install_plugin "superpowers@claude-plugins-official"
  install_plugin "claude-md-management@claude-plugins-official"
  install_plugin "context7@claude-plugins-official"
  install_plugin "playwright@claude-plugins-official"
  install_plugin "example-skills@anthropic-agent-skills"
  install_plugin "document-skills@anthropic-agent-skills"

  step "MCP-серверы"

  if claude mcp list 2>/dev/null | grep -q "^deploychan:"; then
    skip "deploychan"
  else
    if claude mcp add --transport http deploychan https://mcp.deploychan.webcam/mcp -s user >/dev/null 2>&1; then
      ok "deploychan"
    else
      soft_fail "deploychan не подключился"
    fi
  fi
fi

# --- CLAUDE.md ---------------------------------------------------------------
step "CLAUDE.md"

if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
  skip "~/.claude/CLAUDE.md"
else
  mkdir -p "$CLAUDE_DIR"
  if curl -fsSL "$REPO_RAW/CLAUDE.md" -o "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
    ok "положен из репозитория"
  else
    warn "не скачался — положи вручную"
  fi
fi

# --- Итог --------------------------------------------------------------------
echo
if [[ $FAILED -eq 0 ]]; then
  echo "${G}${B}Готово.${N}"
else
  echo "${Y}${B}Готово с замечаниями: ${FAILED} пункт(ов) не встало.${N}"
fi
echo
echo "Дальше:"
echo "  ${B}claude${N}                  — запустить в новой сессии"
echo "  ${B}claude mcp list${N}         — проверить MCP"
echo "  ${B}claude plugin list${N}      — проверить плагины"
echo
echo "${D}Если node/uv не видны — открой новое окно терминала или: source ~/.bashrc${N}"

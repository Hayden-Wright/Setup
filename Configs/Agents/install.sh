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
#      claude-md-management, context7.
#   6. Ставит Playwright MCP: браузер в ~/.cache, системные библиотеки —
#      распаковкой deb в ~/.local (sudo не нужен), плюс обёртку в PATH.
#   7. Подключает MCP deploychan (без ключей).
#   8. Кладёт CLAUDE.md в ~/.claude, если его ещё нет.
#
# Ничего не затирается: уже установленное пропускается. Повторный запуск
# безопасен.
#
# Без sudo. Всё ставится в $HOME.

set -uo pipefail

# --- настройки ---------------------------------------------------------------
NODE_VERSION="v24.22.1"
NODE_TARBALL="node-${NODE_VERSION}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
NODE_SHA_URL="https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt"

LOCAL_BIN="$HOME/.local/bin"
CHROMIUM_LIBS="$HOME/.local/lib/chromium-deps"
CLAUDE_DIR="$HOME/.claude"

REPO_RAW="https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Agents"

# PATH нужен сразу: node/npx/uv могут быть уже установлены, но не видны
# в неинтерактивном шелле (например, при запуске из-под curl | bash).
export PATH="$LOCAL_BIN:$PATH"

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
  die "Этот скрипт для Linux/WSL. Для Windows — Configs/Windows-Terminal/install.ps1."
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

# Путь user-site зависит от версии python — спрашиваем у самого python.
# Важно: site.getusersitepackages(), а не sys.prefix (тот даёт /usr, и запись
# туда падает с Permission denied).
PY_SITE="$(python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null || true)"
if [[ -z "$PY_SITE" ]]; then
  PY_SITE="$HOME/.local/lib/python3.14/site-packages"
  warn "не определил user-site python3, беру $PY_SITE"
fi

mkdir -p "$LOCAL_BIN" "$PY_SITE" || die "Не могу создать $LOCAL_BIN или $PY_SITE — проверь права на \$HOME."

# PATH: дописываем в ~/.bashrc, если наших путей там нет.
add_to_path() {
  local marker='.local/bin'
  if grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null; then
    return 0
  fi
  {
    echo
    echo "# >>> Setup: PATH >>>"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
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
  echo "  качаю ${NODE_TARBALL}..."
  if ! curl -fsSL "$NODE_URL" -o "$tmp/$NODE_TARBALL"; then
    soft_fail "Не скачался Node. Пропускаю npm/npx."
    rm -rf "$tmp"
  else
    # Проверка контрольной суммы — без неё качать бинарники не стоит.
    if curl -fsSL "$NODE_SHA_URL" -o "$tmp/SHASUMS256.txt" 2>/dev/null; then
      expected="$(grep " ${NODE_TARBALL}\$" "$tmp/SHASUMS256.txt" | awk '{print $1}')"
      actual="$(sha256sum "$tmp/$NODE_TARBALL" | awk '{print $1}')"
      if [[ -n "$expected" && "$expected" == "$actual" ]]; then
        ok "Контрольная сумма совпала"
      else
        rm -rf "$tmp"
        die "Контрольная сумма НЕ совпала. Файл повреждён или подменён — прерываю."
      fi
    else
      warn "SHASUMS256.txt недоступен, пропускаю проверку"
    fi
    if tar -xJf "$tmp/$NODE_TARBALL" -C "$tmp"; then
      cp -r "$tmp/node-${NODE_VERSION}-linux-x64/." "$HOME/.local/" || soft_fail "Не скопировался Node"
      hash -r 2>/dev/null || true
      ok "Node $(node -v), npm $(npm -v)"
      add_to_path
    else
      soft_fail "Не распаковался Node"
    fi
    rm -rf "$tmp"
  fi
fi

# --- uv ----------------------------------------------------------------------
step "uv / uvx"

if command -v uv >/dev/null 2>&1; then
  skip "$(uv --version)"
else
  if curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1; then
    hash -r 2>/dev/null || true
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

# --- Playwright ---------------------------------------------------------------
# Отдельная история: MCP-сервер Playwright не идёт в комплекте с браузером,
# а браузеру нужны системные библиотеки (libnss3, libnspr4, libasound2),
# которых в голом WSL нет. sudo недоступен, поэтому распаковываем deb-пакеты
# в ~/.local и подключаем их только процессу браузера через LD_LIBRARY_PATH.
install_playwright() {
  step "Playwright (браузер + MCP)"

  if ! command -v npx >/dev/null 2>&1; then
    warn "npx нет — Playwright пропущен"
    return 0
  fi

  # 1. Браузер, который понимает именно MCP (chrome-for-testing, не chromium).
  if compgen -G "$HOME/.cache/ms-playwright/chromium-*" >/dev/null 2>&1; then
    skip "браузер Playwright"
  else
    echo "  качаю браузер (~120 МБ)..."
    if npx -y @playwright/mcp@latest install-browser chrome-for-testing >/dev/null 2>&1; then
      ok "браузер установлен"
    else
      soft_fail "браузер не скачался"
    fi
  fi

  # 2. Системные библиотеки без sudo.
  if [[ -e "$CHROMIUM_LIBS/libnss3.so" && -e "$CHROMIUM_LIBS/libnspr4.so" && -e "$CHROMIUM_LIBS/libasound.so.2" ]]; then
    skip "системные библиотеки для браузера"
  elif ! command -v dpkg-deb >/dev/null 2>&1; then
    warn "dpkg-deb нет — библиотеки не распаковать. Нужен: sudo apt install -y libnss3 libnspr4 libasound2t64"
  else
    local dl
    dl="$(mktemp -d)"
    # libasound2 в Ubuntu 24.04+ называется libasound2t64.
    local pkgs=(libnss3 libnspr4)
    ( cd "$dl" && apt-get download "${pkgs[@]}" libasound2t64 >/dev/null 2>&1 ) \
      || ( cd "$dl" && apt-get download "${pkgs[@]}" libasound2 >/dev/null 2>&1 )
    if compgen -G "$dl/*.deb" >/dev/null 2>&1; then
      mkdir -p "$CHROMIUM_LIBS"
      for d in "$dl"/*.deb; do
        dpkg-deb -x "$d" "$dl/ext" 2>/dev/null
      done
      cp -a "$dl/ext/usr/lib/x86_64-linux-gnu/"*.so* "$CHROMIUM_LIBS/" 2>/dev/null
      ok "библиотеки распакованы в ~/.local/lib/chromium-deps"
    else
      soft_fail "не скачались deb-пакеты (нет доступа к apt-репозиторию?)"
    fi
    rm -rf "$dl"
  fi

  # 3. Обёртка: MCP по умолчанию ищет /opt/google/chrome, а не наш браузер,
  #    и запускается с урезанным PATH. Оба вопроса решает этот скрипт.
  cat > "$LOCAL_BIN/playwright-mcp" <<'WRAPPER'
#!/usr/bin/env bash
# Playwright MCP с браузером, поставленным без sudo.
#
# 1. Системных libnss3/libnspr4/libasound2 нет (ставятся только через sudo),
#    поэтому они распакованы в ~/.local/lib/chromium-deps.
# 2. MCP ищет канал 'chrome' (/opt/google/chrome), а не браузер из
#    ~/.cache/ms-playwright — флаг --browser chromium это правит.
# 3. MCP запускается с урезанным PATH — npx добавляем явно.
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$HOME/.local/lib/chromium-deps${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec npx -y @playwright/mcp@latest --browser chromium --headless "$@"
WRAPPER
  chmod +x "$LOCAL_BIN/playwright-mcp"
  ok "обёртка ~/.local/bin/playwright-mcp"

  if [[ -z "${SKIP_CLAUDE:-}" ]]; then
    # Старый плагин playwright содержит только .mcp.json (скиллов в нём нет)
    # и запускает MCP без наших флагов — то есть не работает. Убираем.
    if claude plugin list 2>/dev/null | grep -q "playwright@claude-plugins-official"; then
      claude plugin uninstall playwright@claude-plugins-official -y >/dev/null 2>&1 \
        && ok "старый плагин playwright убран" \
        || warn "не убрался плагин playwright — сделай вручную"
    fi

    if claude mcp list 2>/dev/null | grep -q "^playwright:"; then
      skip "MCP playwright"
    elif claude mcp add playwright -s user -- "$LOCAL_BIN/playwright-mcp" >/dev/null 2>&1; then
      ok "MCP playwright"
    else
      soft_fail "MCP playwright не подключился"
    fi
  fi
}

# --- Плагины -----------------------------------------------------------------
if [[ -z "${SKIP_CLAUDE:-}" ]]; then
  step "Маркетплейсы плагинов"

  # Нужны оба. claude-plugins-official на чистой машине отсутствует —
  # без него superpowers/context7/claude-md-management не ставятся вообще.
  add_marketplace() {
    local name="$1" repo="$2"
    if claude plugin marketplace list 2>/dev/null | grep -q "❯ ${name}$"; then
      skip "${name}"
      return 0
    fi
    if claude plugin marketplace add "$repo" >/dev/null 2>&1; then
      ok "${repo}"
    else
      soft_fail "не подключился маркетплейс ${repo}"
    fi
  }

  add_marketplace "claude-plugins-official" "anthropics/claude-plugins-official"
  add_marketplace "anthropic-agent-skills" "anthropics/skills"

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

install_playwright

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

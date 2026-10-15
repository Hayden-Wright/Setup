#!/bin/zsh
# Open WebUI Computer (cptr) — запуск и управление.
#
#   ./start-cptr.sh start|stop|restart|status|url|logs
#
# Слушает только 127.0.0.1: наружу не выставлен намеренно.
# Учётные данные: ~/.cptr-credentials.txt (chmod 600)

CPTR_BIN="$HOME/.local/share/cptr-venv/bin/cptr"
CPTR_HOST="${CPTR_HOST:-127.0.0.1}"
CPTR_PORT="${CPTR_PORT:-8100}"
CPTR_LOG="${CPTR_LOG:-/tmp/cptr.log}"
CPTR_PID="${CPTR_PID:-/tmp/cptr.pid}"

# Агент (Claude Code), которого запускает Computer, наследует окружение
# процесса cptr (см. cptr/utils/agents/claude_code.py: `env = os.environ.copy()`).
#
# По умолчанию в шелле стоит ANTHROPIC_BASE_URL=http://localhost:4000 — это
# CLI-прокси, где зарегистрирована ТОЛЬКО `deepseek-v4.1-flash`. Computer же
# подставляет модель из своего встроенного списка (claude-fable-5), и запрос
# падает с
#   400 anthropic_messages: Invalid model name passed in model=claude-fable-5
#
# Поэтому переводим агента на Desktop-шлюз :4002, где модель объявлена как
# claude-opus-5-5. Значения — те же, что в UI Claude Desktop.
export ANTHROPIC_BASE_URL="${CPTR_AGENT_BASE_URL:-http://127.0.0.1:4002}"
export ANTHROPIC_AUTH_TOKEN="${CPTR_AGENT_TOKEN:-sk-claude-desktop-local}"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL="${CPTR_AGENT_MODEL:-claude-opus-5-5}"

# Окно контекста агента. Имя `claude-opus-5-5` CLI не знает (за ним прячется
# DeepSeek), поэтому считает окно дефолтным 200K и рано включает авто-компакт.
#
# 262144 — реальный лимит Token Juice, апстрим называет его сам при
# переполнении: 400 {"details":{"type":"context_length","limit":262144,...}}.
# Значение то же, что в ~/claude-source/deepseek-claude для CLI-прокси.
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="${CPTR_AGENT_CONTEXT_TOKENS:-262144}"

# ── Доступ агента к диску ПК: ПОЛНЫЙ ────────────────────────────────────────
# Здесь раньше стоял `export CLAUDE_CONFIG_DIR=~/.config/cptr/agent-claude`
# с settings.json, запрещавшим Read/Bash/Grep/Glob/Edit/Write/Task. Это
# отключало агенту не только доступ к файлам, но и весь остальной
# инструментарий. Убрано по просьбе: агенту нужен полный доступ.
#
# Каталог ~/.config/cptr/agent-claude с тем settings.json оставлен на диске —
# вернуть запрет можно, раскомментировав строку ниже. Включать только вместе
# с CPTR_AGENT_CONFIG_DIR, иначе подхватится ~/.claude и запрет утечёт в
# терминальный Claude Code.
#
# export CLAUDE_CONFIG_DIR="${CPTR_AGENT_CONFIG_DIR:-$HOME/.config/cptr/agent-claude}"

# Шаблон для pgrep намеренно с [-]: иначе он совпадает с командной строкой
# самого этого скрипта и kill убивает вызывающий шелл.
CPTR_PATTERN="cptr[-]venv/bin/cptr"

running() {
  [[ -f "$CPTR_PID" ]] && kill -0 "$(cat "$CPTR_PID" 2>/dev/null)" 2>/dev/null
}

case "$1" in
  start)
    if running; then
      echo "уже запущен (pid $(cat "$CPTR_PID"))"
      exit 0
    fi
    [[ -x "$CPTR_BIN" ]] || { echo "не найден: $CPTR_BIN"; exit 1; }
    cd "$HOME" || exit 1
    setsid nohup "$CPTR_BIN" run --host "$CPTR_HOST" --port "$CPTR_PORT" --headless \
      > "$CPTR_LOG" 2>&1 < /dev/null &
    echo $! > "$CPTR_PID"
    for i in {1..20}; do
      sleep 1
      if ss -ltn 2>/dev/null | grep -q ":$CPTR_PORT "; then
        echo "запущен: http://$CPTR_HOST:$CPTR_PORT (pid $(cat "$CPTR_PID"))"
        exit 0
      fi
    done
    echo "не поднялся за 20 с — смотри $CPTR_LOG"; exit 1
    ;;
  stop)
    if running; then
      kill "$(cat "$CPTR_PID")" 2>/dev/null && echo "остановлен"
    else
      pgrep -f "$CPTR_PATTERN" | xargs -r kill 2>/dev/null && echo "остановлен"
    fi
    rm -f "$CPTR_PID"
    ;;
  restart)
    "$0" stop; sleep 3; "$0" start
    ;;
  status)
    if running; then
      echo "работает: pid $(cat "$CPTR_PID"), порт $CPTR_PORT"
      curl -s --max-time 5 "http://$CPTR_HOST:$CPTR_PORT/api/config" 2>/dev/null; echo
    else
      echo "остановлен"
    fi
    ;;
  url)
    TOKEN=$(grep -oE 'token=[a-f0-9]+' "$CPTR_LOG" 2>/dev/null | head -1 | cut -d= -f2)
    echo "http://$CPTR_HOST:$CPTR_PORT/?token=$TOKEN"
    ;;
  logs)
    tail -f "$CPTR_LOG"
    ;;
  *)
    echo "использование: $0 start|stop|restart|status|url|logs"
    exit 1
    ;;
esac

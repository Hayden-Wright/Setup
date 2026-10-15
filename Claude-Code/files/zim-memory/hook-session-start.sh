#!/usr/bin/env bash
# Хук SessionStart для Claude Code: доиндексировать память.
#
# Запускается в начале сессии, чтобы поиск (zim-memory search) видел
# вчерашние заметки и прошлые сессии. Инкрементальный — читает jsonl
# с прошлого смещения, поэтому на неизменённых данных это доли секунды.
#
# Никогда не валит сессию: любой сбой = тихий выход с кодом 0.
# Долгий/зависший индекс не должен задерживать старт, поэтому timeout.

set -uo pipefail

SCRIPT="$HOME/.claude/zim-memory/index.py"
[[ -f "$SCRIPT" ]] || exit 0

PY="${ZIM_MEMORY_PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || exit 0

timeout 60 "$PY" -I "$SCRIPT" index >/dev/null 2>&1 || true
exit 0

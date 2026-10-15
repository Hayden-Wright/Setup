#!/usr/bin/env bash
# setup-cptr.sh — прописать настройки cptr в его базу.
#
# Запускать ПОСЛЕ первого старта cptr (`~/start-cptr.sh start`): пока база
# не создана, писать некуда.
#
# Что делает:
#   gateway.model  — иначе Open WebUI получает
#                    503 No API model connections configured
#                    (cptr ищет модель для чата и не находит: агентский
#                    профиль в этой проверке не участвует)
#   agents.profiles — оставляет в пикере одну модель, claude-opus-5-5
#
# api_keys сюда НЕ вписывается намеренно: ключ привязан к id пользователя,
# а он у каждого свой. Ключ создаётся в веб-интерфейсе cptr и вручную
# вставляется в openwebui.env (см. руководство, шаг 9).

set -euo pipefail

DB="${CPTR_DB:-$HOME/.cptr/app.db}"
GATEWAY_MODEL="${CPTR_GATEWAY_MODEL:-agent:claude-code/claude-opus-5-5}"

[[ -f "$DB" ]] || { echo "нет $DB — сначала запусти ~/start-cptr.sh start"; exit 1; }

command -v cptr >/dev/null 2>&1 || true
CPTR_PY="$HOME/.local/share/cptr-venv/bin/python"
[[ -x "$CPTR_PY" ]] || CPTR_PY="python3"

"$CPTR_PY" -I - "$DB" "$GATEWAY_MODEL" <<'PY'
import json, sqlite3, sys

db, gateway_model = sys.argv[1], sys.argv[2]

# Значения в этой таблице — JSON, а не текст: строка хранится как
# "\"agent:claude-code/claude-opus-5-5\"" (с кавычками внутри). Если записать
# её сырым текстом, cptr не распарсит значение и модель не подхватится.
profiles = [{
    "id": "claude-code",
    "agent": "claude_code",
    "name": "Claude Code",
    "mode": "auto",
    "command": "claude",
    "home": None,
    "models": ["claude-opus-5-5"],
    "default_model": "claude-opus-5-5",
    "permission_mode": "default",
    "launch_args": "",
}]

con = sqlite3.connect(db)
now = int(__import__("time").time())

# chat.compact_token_threshold — тот же лимит 262144, что и у CLI: апстрим
# режет по нему, и без этой строки cptr считает окно больше, чем есть.
rows = [
    ("gateway.model", json.dumps(gateway_model)),
    ("agents.profiles", json.dumps(profiles)),
    ("chat.compact_token_threshold", json.dumps(262144)),
    ("chat.title_generation.enabled", json.dumps(True)),
    ("workspace.auto_gitignore_dot_cptr", json.dumps(True)),
]

for key, value in rows:
    con.execute(
        "INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
        (key, value, now),
    )
    print(f"  ✓ {key}")

con.commit()
print(f"\nзаписано в {db}")
print("перезапусти cptr, чтобы настройки применились:")
print("  ~/start-cptr.sh restart")
PY

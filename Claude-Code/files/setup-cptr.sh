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
#   workspace      — без строки в workspaces /v1/models пуст, и Open WebUI
#                    показывает «No models available»
#
# api_keys сюда НЕ вписывается намеренно: ключ привязан к id пользователя,
# а он у каждого свой. Ключ создаётся в веб-интерфейсе cptr и вручную
# вставляется в openwebui.env (см. руководство, шаг 9).

set -euo pipefail

DB="${CPTR_DB:-$HOME/.cptr/app.db}"
GATEWAY_MODEL="${CPTR_GATEWAY_MODEL:-agent:claude-code/claude-opus-5-5}"

[[ -f "$DB" ]] || { echo "нет $DB — сначала запусти ~/start-cptr.sh start"; exit 1; }

CPTR_PY="$HOME/.local/share/cptr-venv/bin/python"
[[ -x "$CPTR_PY" ]] || CPTR_PY="python3"

"$CPTR_PY" -I - "$DB" "$GATEWAY_MODEL" "$HOME" <<'PY'
import json, sqlite3, sys, time, uuid

db, gateway_model, home = sys.argv[1], sys.argv[2], sys.argv[3]

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

# Рабочая папка (workspace). Без неё Open WebUI показывает «No models
# available», и это не путать с gateway.model выше: тот выбирает, КАКОЙ агент
# отвечает, а здесь — ЧТО попадает в список моделей.
#
# GET /v1/models отдаёт не агентов, а workspace'ы: каждый каталог превращается
# в модель `cptr/<имя папки>`. Пока в таблице workspaces пусто, ответ — пустой
# список, и Open WebUI честно рисует пустой пикер. cptr заводит строку, только
# когда пользователь сам откроет папку в своём веб-интерфейсе, а установка
# ведёт человека сразу в Open WebUI — отсюда и пустота на чистой установке.
#
# Создаём одну папку — домашний каталог: с неё начинается работа, и в неё же
# cptr пишет свои заметки. Существующие не трогаем: если человек уже завёл
# свои, лишняя не нужна.
user_id = con.execute("select id from users limit 1").fetchone()
if user_id is None:
    print("  ! в базе нет пользователя — workspace не создан")
elif con.execute("select 1 from workspaces where user_id = ? limit 1", (user_id[0],)).fetchone():
    print("  ✓ workspace уже есть")
else:
    con.execute(
        "insert into workspaces (id, user_id, path, name, data, created_at, updated_at) "
        "values (?, ?, ?, ?, '{}', ?, ?)",
        (str(uuid.uuid4()), user_id[0], home, "Home", now, now),
    )
    print(f"  ✓ workspace: {home}")

con.commit()
print(f"\nзаписано в {db}")
print("перезапусти cptr, чтобы настройки применились:")
print("  ~/start-cptr.sh restart")
PY

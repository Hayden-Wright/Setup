#!/usr/bin/env python3
"""zim-memory — FTS5-индекс по заметкам и логам сессий Claude Code.

Зачем: заметки и история сессий лежат простыми файлами, и без индекса
единственный способ что-то найти — grep по 200+ МБ jsonl. Здесь SQLite+FTS5:
поиск по ключевым словам за секунды, с указанием сессии и времени.

Что индексируется:
  * заметки   — *.md из memory/
  * сессии    — реплики человека и текстовые ответы агента из *.jsonl
                (tool_use / tool_result НЕ берём: это вывод команд, он
                 раздувает индекс на порядки и искать в нём нечего)

Использование:
    zim-memory.py index            # доиндексировать изменившееся
    zim-memory.py index --rebuild  # пересобрать с нуля
    zim-memory.py search "запрос"  # поиск
    zim-memory.py stats            # что в индексе
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

CLAUDE = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
DB = Path(os.environ.get("ZIM_MEMORY_DB", CLAUDE / "zim-memory" / "memory.db"))
PROJECTS_DIR = CLAUDE / "projects"

# Папки памяти Claude Code лежат внутри projects/<слаг-каталога>/memory, и
# слаг зависит от того, откуда запущен Claude Code (`-home-<user>` против
# `-home-<user>-zim-claude` — это РАЗНЫЕ каталоги с разной памятью).
# Поэтому не зашиваем один слаг, а обходим все: иначе заметки, которые
# сессия реально грузит, в индекс не попадают.
MEMORY_DIRS = sorted(PROJECTS_DIR.glob("*/memory"))

# Поля FTS5. Столбец text — то, по чему ищем; остальные возвращаем как есть.
SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    path    TEXT PRIMARY KEY,
    size    INTEGER NOT NULL,
    mtime   REAL    NOT NULL,
    offset  INTEGER NOT NULL DEFAULT 0
);

CREATE VIRTUAL TABLE IF NOT EXISTS notes USING fts5(
    text, name, path,
    tokenize = "unicode61 remove_diacritics 2"
);

CREATE VIRTUAL TABLE IF NOT EXISTS sessions USING fts5(
    text, session, project, role, ts, uuid,
    tokenize = "unicode61 remove_diacritics 2"
);
"""


def connect() -> sqlite3.Connection:
    DB.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB)
    con.executescript(SCHEMA)
    return con


# ---------------------------------------------------------------- заметки

def index_notes(con: sqlite3.Connection) -> int:
    """Заметки небольшие — переиндексируем целиком, это дёшево."""
    con.execute("DELETE FROM notes")
    n = 0
    for mem_dir in MEMORY_DIRS:
        for p in sorted(mem_dir.glob("*.md")):
            try:
                text = p.read_text(errors="replace")
            except OSError:
                continue
            con.execute(
                "INSERT INTO notes (text, name, path) VALUES (?, ?, ?)",
                (text, p.stem, str(p)),
            )
            n += 1
    return n


# ---------------------------------------------------------------- сессии

def _texts_from(content) -> list[str]:
    """Достать текстовые блоки. Строку берём как есть; из списка — только
    блоки type=text, игнорируя tool_use / tool_result / thinking."""
    if isinstance(content, str):
        return [content]
    out = []
    if isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and isinstance(b.get("text"), str):
                out.append(b["text"])
    return out


def index_sessions(con: sqlite3.Connection, rebuild: bool = False) -> tuple[int, int]:
    """Инкрементально: jsonl только дописываются, поэтому читаем с прошлого
    смещения. Возвращает (файлов обработано, записей добавлено)."""
    if rebuild:
        con.execute("DELETE FROM sessions")
        con.execute("DELETE FROM files")

    known = {r[0]: (r[1], r[2], r[3]) for r in con.execute("SELECT path, size, mtime, offset FROM files")}

    files_done = rows_added = 0
    for path in sorted(PROJECTS_DIR.glob("*/*.jsonl")):
        try:
            st = path.stat()
        except OSError:
            continue
        key = str(path)
        prev = known.get(key)

        if prev and prev[0] == st.st_size and prev[1] == st.st_mtime:
            continue  # не менялся

        # Файл усечён или заменён — читаем с начала.
        offset = prev[2] if prev and st.st_size >= prev[2] else 0

        batch = []
        try:
            with open(path, errors="replace") as fh:
                fh.seek(offset)
                for line in fh:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue  # обрезанная/битая строка — пропускаем
                    t = d.get("type")
                    if t not in ("user", "assistant"):
                        continue
                    msg = d.get("message")
                    if not isinstance(msg, dict):
                        continue
                    for txt in _texts_from(msg.get("content")):
                        if txt and txt.strip():
                            batch.append((
                                txt,
                                d.get("sessionId") or path.stem,
                                path.parent.name,
                                t,
                                d.get("timestamp") or "",
                                d.get("uuid") or "",
                            ))
                new_offset = fh.tell()
        except OSError:
            continue

        if batch:
            con.executemany(
                "INSERT INTO sessions (text, session, project, role, ts, uuid) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                batch,
            )
        con.execute(
            "INSERT INTO files (path, size, mtime, offset) VALUES (?, ?, ?, ?) "
            "ON CONFLICT(path) DO UPDATE SET size=excluded.size, "
            "mtime=excluded.mtime, offset=excluded.offset",
            (key, st.st_size, st.st_mtime, new_offset),
        )
        files_done += 1
        rows_added += len(batch)

    return files_done, rows_added


# ---------------------------------------------------------------- поиск

def _fts_words(q: str) -> list[str]:
    """FTS5 понимает свой синтаксис, и случайная кавычка/звёздочка в запросе
    роняет его с ошибкой. Поэтому вытаскиваем только слова и подставляем
    их в кавычках."""
    return re.findall(r"\w+", q, flags=re.UNICODE)


def _fts_query(q: str, op: str = "AND") -> str:
    """Каждое слово — префиксный запрос (`"регион"*`).

    Это важно для русского: у FTS5 нет стемминга, и без звёздочки
    «регион» не находит «региона», а «расшифровка» — «расшифрованная».
    Окончания в русском меняются в конце слова, так что префикс ловит
    почти все формы.
    """
    return f" {op} ".join(f'"{w}"*' for w in _fts_words(q))


def cmd_search(con: sqlite3.Connection, query: str, limit: int, scope: str) -> int:
    if not _fts_words(query):
        print("пустой запрос", file=sys.stderr)
        return 2

    hits = 0
    for op, label in (("AND", ""), ("OR", " (не все слова)")):
        hits = _run_search(con, _fts_query(query, op), limit, scope, label)
        if hits:
            break
    if not hits:
        print("ничего не найдено")
        return 1
    return 0


def _run_search(con: sqlite3.Connection, fq: str, limit: int, scope: str, label: str) -> int:
    hits = 0
    if scope in ("all", "notes"):
        sql = ("SELECT name, path, snippet(notes, 0, '»', '«', '…', 14) "
               "FROM notes WHERE notes MATCH ? ORDER BY rank LIMIT ?")
        rows = list(con.execute(sql, (fq, limit)))
        if rows:
            print(f"\n\033[1m=== ЗАМЕТКИ ({len(rows)}){label} ===\033[0m")
            for name, path, snip in rows:
                print(f"\n\033[36m{name}\033[0m  \033[2m{path}\033[0m")
                print(f"  {snip}")
                hits += 1

    if scope in ("all", "sessions"):
        sql = ("SELECT session, role, ts, snippet(sessions, 0, '»', '«', '…', 14) "
               "FROM sessions WHERE sessions MATCH ? ORDER BY rank LIMIT ?")
        rows = list(con.execute(sql, (fq, limit)))
        if rows:
            print(f"\n\033[1m=== СЕССИИ ({len(rows)}){label} ===\033[0m")
            for sess, role, ts, snip in rows:
                mark = "вы" if role == "user" else "агент"
                print(f"\n\033[36m{mark}\033[0m \033[2m{ts[:19]} · {sess[:8]}\033[0m")
                print(f"  {snip}")
                hits += 1

    return hits


def cmd_stats(con: sqlite3.Connection) -> None:
    n_notes = con.execute("SELECT count(*) FROM notes").fetchone()[0]
    n_sess = con.execute("SELECT count(*) FROM sessions").fetchone()[0]
    n_files = con.execute("SELECT count(*) FROM files").fetchone()[0]
    print(f"база:    {DB}  ({DB.stat().st_size / 1e6:.1f} МБ)" if DB.exists() else f"база: {DB} (нет)")
    print(f"заметок: {n_notes}")
    print(f"записей сессий: {n_sess}")
    print(f"файлов сессий:  {n_files}")


def main() -> int:
    ap = argparse.ArgumentParser(prog="zim-memory", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_idx = sub.add_parser("index", help="доиндексировать изменившееся")
    p_idx.add_argument("--rebuild", action="store_true", help="пересобрать с нуля")

    p_s = sub.add_parser("search", help="поиск")
    p_s.add_argument("query")
    p_s.add_argument("-n", "--limit", type=int, default=8)
    p_s.add_argument("--scope", choices=["all", "notes", "sessions"], default="all")

    sub.add_parser("stats", help="что в индексе")

    a = ap.parse_args()
    con = connect()

    if a.cmd == "index":
        n = index_notes(con)
        files, rows = index_sessions(con, rebuild=a.rebuild)
        con.commit()
        print(f"заметок: {n}; файлов сессий: {files}; новых записей: {rows}")
        return 0
    if a.cmd == "search":
        return cmd_search(con, a.query, a.limit, a.scope)
    if a.cmd == "stats":
        cmd_stats(con)
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())

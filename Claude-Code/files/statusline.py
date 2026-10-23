#!/usr/bin/env python3
"""Claude Code status line: cwd, context usage in percent, model.

Reads the statusLine JSON payload from stdin. Field names are taken from the
schema embedded in the Claude Code 2.1.309 binary (context_window.*).
"""

import json
import os
import sys

RESET = "\033[0m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"


def human_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def color_for(pct: float) -> str:
    if pct >= 75:
        return RED
    if pct >= 50:
        return YELLOW
    return GREEN


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    parts = []

    cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or ""
    home = os.path.expanduser("~")
    if cwd == home:
        cwd = "~"
    elif cwd.startswith(home + os.sep):
        cwd = "~" + cwd[len(home):]
    if cwd:
        parts.append(f"{CYAN}{cwd}{RESET}")

    cw = data.get("context_window") or {}
    pct = cw.get("used_percentage")
    size = cw.get("context_window_size")
    used = cw.get("total_input_tokens")

    if pct is None:
        parts.append(f"{DIM}ctx —{RESET}")
    else:
        pct = float(pct)
        color = color_for(pct)
        label = f"{color}ctx {pct:.0f}%{RESET}"
        if used and size:
            label += f"{DIM} ({human_tokens(used)}/{human_tokens(size)}){RESET}"
        parts.append(label)

    sys.stdout.write(f" {DIM}│{RESET} ".join(parts))


if __name__ == "__main__":
    main()

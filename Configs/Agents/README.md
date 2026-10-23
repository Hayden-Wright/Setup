# Агенты

Настройка Claude Code в WSL: окружение, плагины, MCP-серверы и правила для
агента. Всё ставится в `$HOME`, sudo не нужен.

- [Установка одной командой](#установка-одной-командой)
- [Что ставится и зачем](#что-ставится-и-зачем)
- [По одному](#по-одному)
- [Playwright](#playwright)
- [Реверс-инжиниринг](#реверс-инжиниринг-опционально)
- [Удаление](#удаление)

## Установка одной командой

В WSL Ubuntu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Agents/install.sh)
```

Скрипт идемпотентный: уже установленное пропускает, повторный запуск ничего не
ломает. В конце пишет `Готово.`

**Что нужно до запуска:** `curl`, `tar`, `xz` (есть в Ubuntu по умолчанию) и
сам Claude Code. Если `claude` не найден, скрипт поставит окружение и
пропустит плагины — их можно добить позже.

**Что он не делает:** не ставит Ghidra (~880 МБ распакованной, отдельная
история — см. [ниже](#ghidra)) и не ставит `apt`-пакеты, потому что для них
нужен пароль sudo.

Браузер Playwright он ставит сам и без sudo — библиотеки для него
распаковываются из deb-пакетов в `~/.local` (подробности в разделе
[Playwright](#playwright)).

## Что ставится и зачем

| Компонент | Куда | Зачем |
|---|---|---|
| Node 24 LTS + npm/npx | `~/.local` | без него не работают `npx`-MCP-серверы (playwright) и установка скиллов |
| uv / uvx | `~/.local/bin` | запуск Python-MCP-серверов, установка пакетов |
| Python-библиотеки | user-site python3 (`~/.local/lib/python3.14/…`) | чтобы работали скиллы pdf/docx/xlsx/pptx |
| superpowers | плагин | методология: brainstorming, systematic-debugging, TDD, код-ревью |
| example-skills | плагин | 12 скиллов, включая `skill-creator` и `frontend-design` |
| document-skills | плагин | pdf, docx, xlsx, pptx |
| claude-md-management | плагин | аудит и правка CLAUDE.md |
| context7 | плагин + MCP | актуальная документация библиотек вместо памяти модели |
| playwright | MCP + браузер (~670 МБ в `~/.cache`) | браузерная автоматизация, тесты веб-приложений, скриншоты |
| deploychan | MCP | каталог знаний и готовых скиллов, без ключей |
| CLAUDE.md | `~/.claude/CLAUDE.md` | твои правила: язык, окружение, границы |

**Почему не `pip install`.** Системный Python 3.14 помечен
`EXTERNALLY-MANAGED` (PEP 668), и `pip` в нём вообще отсутствует. Пакеты
ставятся в user-site через `uv pip install --target` — тогда их видит
`python3`, который и вызывают скиллы. Отдельный venv не подходит: скиллы
зовут именно `python3`.

## По одному

Всё ниже — из WSL, без sudo.

### Node

Нужен для `npx`: на нём работают playwright MCP и установка сторонних скиллов
через `npx skills add`.

```bash
cd /tmp && curl -sLO https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz
curl -sL https://nodejs.org/dist/v24.22.1/SHASUMS256.txt | grep 'node-v24.22.1-linux-x64.tar.xz' | sha256sum -c -
tar -xJf node-v24.22.1-linux-x64.tar.xz
cp -r node-v24.22.1-linux-x64/* ~/.local/
node -v && npm -v && npx -v
```

Проверка контрольной суммы здесь не формальность: качается и запускается
бинарник.

### uv

Даёт `uvx`, через который запускается половина Python-MCP-серверов, и
`uv pip` для установки пакетов в обход PEP 668.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

### Python-библиотеки

Без них скиллы `pdf`, `docx`, `xlsx`, `pptx` падают на первом же импорте.

```bash
# путь зависит от версии python — спрашиваем у него самого
SITE=$(python3 -c 'import site; print(site.getusersitepackages())')

uv pip install --python /usr/bin/python3 --target "$SITE" \
  pypdf pdfplumber openpyxl python-docx python-pptx \
  pandas pillow reportlab matplotlib

# консольные скрипты кладутся в site-packages/bin — прокидываем в PATH
for f in markitdown pdf2txt.py dumppdf.py; do
  ln -sf "$SITE/bin/$f" ~/.local/bin/$f
done
```

Проверка:

```bash
python3 -c "import pandas, docx, pptx, openpyxl, pypdf, reportlab, PIL, matplotlib; print('OK')"
```

### Плагины

```bash
claude plugin marketplace add anthropics/skills

claude plugin install superpowers@claude-plugins-official -y
claude plugin install claude-md-management@claude-plugins-official -y
claude plugin install context7@claude-plugins-official -y
claude plugin install example-skills@anthropic-agent-skills -y
claude plugin install document-skills@anthropic-agent-skills -y
```

Флаг `-y` обязателен: без TTY установка иначе отказывается.

**Плагин `playwright` отдельно не ставится — он нерабочий.** В нём только
`.mcp.json`, без скиллов, и он запускает MCP без нужных флагов: сервер ищет
Chrome в `/opt/google/chrome`, которого в WSL нет, и падает на
`Chromium distribution 'chrome' is not found`. Рабочая установка — ниже, в
разделе [Playwright](#playwright).

**Не ставь `skill-creator` и `frontend-design` отдельными плагинами.** Они
побайтово лежат внутри `example-skills`; отдельная установка дублирует их в
листинге контекста. После установки они доступны как
`example-skills:skill-creator` и `example-skills:frontend-design`.

**Проверка:**

```bash
claude plugin list
```

### MCP-серверы

**deploychan** — каталог знаний и готовых скиллов, публичный, без ключей:

```bash
claude mcp add --transport http deploychan https://mcp.deploychan.webcam/mcp -s user
```

**context7** — ставится плагином, но требует входа: при первом вызове
инструмента откроется браузер. В WSL есть подвох — Windows не форвардит
`localhost`, поэтому OAuth-callback может не дойти. Обходной путь описан в
комментариях к issue; проще всего войти из терминала, где открывается
браузер, либо использовать API-ключ с [context7.com/dashboard](https://context7.com/dashboard):

```bash
claude mcp add --transport http context7 https://mcp.context7.com/mcp \
  -H "CONTEXT7_API_KEY: ctx7sk-твой-ключ" -s user
```

**GitHub** — отдельным MCP-сервером ставить не советую. Он вставляет ~5 000
токенов инструкций в **каждую** сессию, а `gh` делает то же самое через Bash
бесплатно:

```bash
gh auth login
gh pr list
```

Ставь MCP только если реально нужен ревью PR с комментариями по строкам.

### Playwright

Браузерная автоматизация: открыть страницу, кликнуть, снять скриншот,
посмотреть консоль. Ставится в три шага, и каждый нужен — пропустишь любой,
MCP будет числиться `Connected`, но упадёт на первом же вызове.

**Шаг 1. Браузер.** Не `chromium`, а именно `chrome-for-testing` — MCP ищет
его в своём каталоге:

```bash
npx -y @playwright/mcp@latest install-browser chrome-for-testing
```

**Шаг 2. Системные библиотеки.** Браузер не запустится без `libnss3`,
`libnspr4`, `libasound2`, а в голом WSL их нет. Ставить их надо через sudo,
но можно обойтись: скачать deb-пакеты и распаковать в `~/.local`.

```bash
mkdir -p ~/.local/lib/chromium-deps /tmp/pwdeps
cd /tmp/pwdeps
apt-get download libnss3 libnspr4 libasound2t64
for d in *.deb; do dpkg-deb -x "$d" ext/; done
cp -a ext/usr/lib/x86_64-linux-gnu/*.so* ~/.local/lib/chromium-deps/
```

`apt-get download` работает без root — он только скачивает файлы.
В Ubuntu 22.04 и старше пакет называется `libasound2`, а не `libasound2t64`.

Проверка, что все зависимости разрешились:

```bash
B=$(ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome | head -1)
LD_LIBRARY_PATH=~/.local/lib/chromium-deps ldd "$B" | grep "not found" || echo "все библиотеки на месте"
```

**Шаг 3. Обёртка.** MCP надо запускать с флагом `--browser chromium` (иначе
он ищет `/opt/google/chrome`) и с `LD_LIBRARY_PATH`. Проще всего — скриптом:

```bash
cat > ~/.local/bin/playwright-mcp <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin${PATH:+:$PATH}"
export LD_LIBRARY_PATH="$HOME/.local/lib/chromium-deps${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec npx -y @playwright/mcp@latest --browser chromium --headless "$@"
EOF
chmod +x ~/.local/bin/playwright-mcp

claude mcp add playwright -s user -- ~/.local/bin/playwright-mcp
```

Строка `export PATH` не лишняя: MCP запускается с урезанным окружением, и без
неё обёртка падает с `npx: not found`.

**Проверка:**

```bash
claude mcp list | grep playwright     # должно быть ✔ Connected
```

Одного `Connected` мало — он означает лишь, что процесс стартовал. Настоящая
проверка — попросить агента открыть страницу; если браузера нет, ответ будет
`Chromium distribution 'chrome' is not found`.

### CLAUDE.md

Файл `~/.claude/CLAUDE.md` читается в каждой сессии. Установщик кладёт туда
шаблон, если файла нет. Скопировать вручную:

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/Hayden-Wright/Setup/main/Configs/Agents/CLAUDE.md \
  -o ~/.claude/CLAUDE.md
```

Дальше правь под себя: язык ответов, пути проектов, что агенту можно и чего
нельзя.

## Реверс-инжиниринг (опционально)

Не ставится установщиком: инструменты из apt требуют sudo, Ghidra занимает
~880 МБ на диске. Всё ниже — по шагам, каждый проверен.

### Инструменты из apt

```bash
sudo apt install -y gdb radare2 strace ltrace
```

| инструмент | для чего |
|---|---|
| `gdb` | отладчик: точки останова, пошаговое выполнение, дамп памяти |
| `radare2` | дизассемблер и фреймворк анализа бинарников (`r2 -A файл`) |
| | `-A` = полный анализ, на бинарнике 10 МБ+ может идти минутами. Быстрее: `r2 -qc "s main; pdf" файл` без `-A` |
| `strace` | системные вызовы процесса — видно, какие файлы и сокеты трогает |
| `ltrace` | вызовы библиотечных функций — видно, с чем сравнивается пароль |

Плюс `objdump`, `readelf`, `nm`, `strings`, `xxd` — они уже есть в системе
вместе с binutils.

### Ghidra

Декомпилятор: превращает бинарник обратно в читаемый C. Единственный из
списка, который даёт **декомпиляцию**, а не только дизассемблер.

В WSL JDK нет, поэтому Ghidra работает на Windows-Java через interop:

```bash
# имя Windows-профиля не совпадает с $USER из WSL — смотри реальное:
WINUSER=$(find /mnt/c/Users -maxdepth 1 -mindepth 1 -type d \
  -not -iname 'All Users' -not -iname 'Default*' -not -iname 'Public' \
  -not -iname 'WDAGUtilityAccount' -printf '%f\n' | head -1)
echo "Windows-профиль: $WINUSER"
cd "/mnt/c/Users/$WINUSER"
curl -LO https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip
unzip ghidra_12.2_PUBLIC_20261016.zip
```

Запуск headless (из WSL, через `cmd.exe`):

```bat
C:\Users\<user>\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat C:\ghidra_proj proj -import C:\path\to\binary
```

Две ловушки, на которых легко застрять:

- **Пути только Windows-формата.** `C:\...`, не `/mnt/c/...`.
- **Lock-файлы.** Упавший прогон оставляет `<proj>.lock`, и следующий падает
  с `LockException`. Удаляй lock или бери новый каталог проекта.

Проверено на stripped ELF 11 МБ: 20 273 функции, `x86:LE:64`, декомпиляция в C
работает.

### Python-пакеты для реверса

```bash
SITE=$(python3 -c 'import site; print(site.getusersitepackages())')
uv pip install --python /usr/bin/python3 --target "$SITE" \
  capstone lief z3-solver angr unicorn
```

`unicorn` нужен явно: angr без него загружается, но печатает
`unicorn support disabled` и не умеет символьное исполнение — а ради него angr
и ставят. Пакет не приходит как зависимость.

`capstone` — дизассемблер как библиотека, `lief` — разбор и правка ELF/PE,
`z3-solver` — решатель ограничений (для брутфорса проверок), `angr` —
символьное исполнение.

## Удаление

```bash
# плагины (-y обязателен без TTY: без него uninstall ждёт подтверждения)
for p in superpowers claude-md-management context7; do
  claude plugin uninstall "$p@claude-plugins-official" -y
done
claude plugin uninstall example-skills@anthropic-agent-skills -y
claude plugin uninstall document-skills@anthropic-agent-skills -y

# MCP
claude mcp remove deploychan
claude mcp remove playwright
```

Node и uv лежат в `~/.local` — если больше не нужны, `rm -rf ~/.local/node*`
и `rm -rf ~/.local/bin/uv*`. Python-библиотеки — `rm -rf ~/.local/lib/python3.14`.

Браузер и его библиотеки — отдельно, они самые тяжёлые (~670 МБ):

```bash
rm -rf ~/.cache/ms-playwright ~/.local/lib/chromium-deps ~/.local/bin/playwright-mcp
```

## Ссылки

- [zim-claude](https://github.com/Mr-Destroyer/zim-claude) — Claude Code через локальный LiteLLM-прокси
- [anthropics/skills](https://github.com/anthropics/skills) — официальные скиллы
- [deploychan](https://mcp.deploychan.webcam) — каталог знаний

![](deploy-tan.png)

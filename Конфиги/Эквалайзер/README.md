Пресет ABI: пять фильтров и лимитер LoudMax в конце цепочки.

![](preset-abi-2.jpg)

## Что поставить

- **[Equalizer APO](https://sourceforge.net/projects/equalizerapo/)** — сам эквалайзер
- **[Peace](https://sourceforge.net/projects/peace-equalizer-apo-extension/)** — оболочка к нему
- **[LoudMax](https://loudmax.blogspot.com/2026/06/loudmax-plugin-v147-released.html)** — лимитер, качается у автора отдельно (архив **VST2 for Windows**)

При установке Equalizer APO отметить устройство вывода, через которое слушаешь,
и перезагрузиться. Peace ставится после APO. LoudMax в репозитории не лежит —
автор запрещает распространять его файлы, так что ссылка на оригинал.

## Настройка

1. Открыть Peace. Если ругается на устройство — выбрать его в списке справа
   (`Select a speaker`) и нажать `Done`.
2. Кнопка `Import` → выбрать `ABI 2.0.peace` из этого репозитория. Ползунки
   встанут на места.
3. `Save`, затем `Done`. Peace создаст `peace.txt` и сам добавит в `config.txt`
   строку `Include: peace.txt`.
4. Распаковать `LoudMax64.dll` из архива в любую папку — например `C:\VST`.
   Папку потом не перемещать: путь прописывается жёстко.
5. Открыть **Equalizer APO Configuration Editor** (`config.txt`) и нажать `+` →
   **VST plugin**. В диалоге указать путь к `LoudMax64.dll`.
6. В появившейся строке плагина нажать `Options` — откроется окно LoudMax.
   Поставить `Thresh` −6 dB, `Output` −6 dB и включить `Link`.

![](config-editor.png)

Эквалайзер должен стоять **до** лимитера, как на скрине: сначала правятся
частоты, потом LoudMax поджимает пики.

## Пресеты

Ползунки для ручного ввода в Peace.

**ABI 2.0** — текущий:

| Частота | Тип | Gain | Q |
|---|---|---|---|
| 70 Hz | low shelf | −12 dB | 0.93 |
| 250 Hz | peak | +4.5 dB | 1.76 |
| 1050 Hz | peak | +3 dB | 3.5 |
| 1800 Hz | peak | +2.5 dB | 3 |
| 4000 Hz | peak | +4.5 dB | 1.43 |

**ABI** — предыдущий:

| Частота | Тип | Gain | Q |
|---|---|---|---|
| 100 Hz | low shelf | −12 dB | 1.41 |
| 315 Hz | peak | +6 dB | 3 |
| 6300 Hz | peak | +6 dB | 3 |
| 10000 Hz | high shelf | +5 dB | 1.41 |

![](preset-abi.png)

Тип задаётся в строке `Filter` под каждым ползунком: `LS` — low shelf,
`PK` — peak, `HS` — high shelf. Gain и Q — в полях `Gain Values` и `Quality (Q)`
под графиком.

## Файлы

| Путь | Что это |
|---|---|
| `ABI 2.0.peace` | текущий пресет |
| `ABI.peace` | предыдущий пресет |
| `preset-abi-2.jpg` | как выглядит ABI 2.0 в Peace |
| `preset-abi.png` | как выглядит ABI |
| `config-editor.png` | цепочка в APO: эквалайзер, потом LoudMax |

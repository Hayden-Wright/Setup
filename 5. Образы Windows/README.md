# Образы Windows

- **[UUP dump](https://uupdump.net/)** — оригинальный образ Windows с серверов обновлений Microsoft

## UUP dump

Собирает ISO из файлов обновлений Microsoft. Файлы оригинальные — в отличие от сборок с торрентов.

Сайт только один — `uupdump.net`, зеркал нет.

### Как пользоваться

1. Выбрать сборку на [uupdump.net](https://uupdump.net/) → язык → редакцию → **Next**.
2. Метод — **Download and convert to ISO**.
3. Галочку **Include updates** не снимать: без неё соберётся базовая версия, а не выбранная.
4. **Create download package** → распаковать ZIP в пустую папку → запустить `uup_download_windows.cmd` от администратора.
5. Рядом появится `.ISO`.

Нужен Windows 10 2004+ или 11 (на Linux обновления не встроятся) и ~30 ГБ свободного места. Занимает от 20 минут.

### Если не вышло

- **«can't be converted to an ISO»** — выбрано обновление вместо сборки. Нужен Feature Update («Upgrade to…»), не Cumulative Update («Update for…»).
- **Не работают Windows Security или Настройки** — собиралось без обновлений или не на Windows. Пересобрать с **Include updates**.
- **Ошибка сборки** — мало места или кириллица в пути. Распаковать в `C:\uup`.

# Veilor на основе OneXray

Активная ветка: `veilor/onexray` в https://github.com/onety11one/veilor.

Цель — универсальный клиент для Windows, macOS, Linux, Android и iOS с утверждённым интерфейсом «Лента». Первый целевой билд — Windows. Основу OneXray сначала собираем и проверяем без изменений поведения; затем переносим UI небольшими шагами.

- [Передача работы и текущий статус](HANDOFF.md)
- [Подготовка и продолжение Windows-сборки](BUILD-WINDOWS.md)
- [Дизайн и границы поведения](DESIGN.md)
- [Сохранённый макет](mockups/veilor-windows.html)
- [Ревизии зависимостей](upstream-sources.lock.json)
- [Результаты исследования](research/BUILD-PROGRESS-2026-10-23.md)
- [Обезличенный пример VLESS](examples/IMPORT-ONEXRAY.md)

Основа ветки — полная Git-история OneXray до commit `73c1cb33fb755d8da324064225bff17734e590f6`. Karing не объединён с этим исходным деревом. Его итоговый архив сохранён в [veilor/core-readonly-adapter](https://github.com/onety11one/veilor/tree/veilor/core-readonly-adapter), commit `2ddb6b52`.

OneXray лицензирован GPL-3.0; исходные лицензии и авторство сохранены. Для распространения Veilor нужно выполнять условия GPL и лицензий включённых зависимостей. Имя, Store-идентификаторы, сертификаты, ссылки и брендинг OneXray пока не менялись: собственный релиз ещё не подготовлен.

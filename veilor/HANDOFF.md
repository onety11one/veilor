# Точка продолжения Veilor / OneXray

Обновлено 23.10.2026. Пользователь прекратил направление Karing и разрешил сохранить архив, создать эту ветку и продолжить разработку на основе OneXray. `main` не изменять без отдельной задачи. Не возобновлять реверс Karing как основной план.

## Что уже подтверждено

- Пользователь импортировал вручную восстановленный VLESS/REALITY-узел из Karing в установленный OneXray и подтвердил подключение. Для Windows понадобился явный выбор физического Wi-Fi/Ethernet в Advanced → VPN Tunnel → Xray outbound interface.
- Это проверка готового OneXray. Собственная сборка приложения ещё не работает и не тестировалась в сети.
- Исходники OneXray, libXray, Vole и закреплённого boring/BoringSSL доступны. `cargo fetch --locked --target x86_64-pc-windows-msvc` завершился успешно.
- Подготовлены отдельные Flutter 3.47.7 / Dart 3.13.5, Go 1.27.3, Rust 1.99.1, LLVM-MinGW 20261020, libclang 18.1.1.
- `flutter pub get` и `flutter gen-l10n` завершились успешно. Новые версии зависимостей сверх lockfile специально не выбирались.
- Штатная Windows-сборка libXray завершилась успешно: DLL, header, Core EXE и полный GeoData. Проверены x64/PE32+ и экспорты CGoInvoke/CGoFree, без загрузки DLL или запуска Core.
- Ранее прошли 35 тестов упаковочных Python-скриптов. Они не подтверждают сборку UI или работу VPN.

## Текущие блокеры

1. **Установленный Visual Studio C++ toolchain.** FFI generation упала в build hook cnativeapi из-за отсутствия MSVC/vswhere; Flutter Windows build тоже завершился с сообщением об отсутствии подходящего Visual Studio. Последнее сообщение пользователя: **Build Tools устанавливаются**. Сначала проверить завершение установки через flutter doctor, не запускать второй инсталлятор автоматически.
2. **Wintun DLL.** Официальная загрузка не завершилась; curl сообщил CRYPT_E_REVOCATION_OFFLINE. Проверки TLS не отключать, частичные ZIP не использовать.
3. **Vole DLL и два UWP host EXE.** Зависимости скачаны, компиляция после подготовки Rust ещё не выполнена. Текущий CMake требует их и для EXE/ZIP.
4. После подготовки native bundle нужны FFI generation и повторная полная Windows-сборка. Подписание и упаковка — отдельный последующий этап.

## Порядок следующих работ

1. Проверить установленные Build Tools. Завершить исходную Windows Debug-сборку по [BUILD-WINDOWS.md](BUILD-WINDOWS.md).
2. Проверить запуск с изолированными данными. Не мешать установленному рабочему OneXray и его соединению.
3. Проверить подключение одного рабочего узла вручную, затем остальные протоколы, DNS и маршрутизацию. Полный паритет Karing не доказан.
4. Переносить утверждённую «Ленту» через существующие сервисы OneXray; не заменять VPN-логику демонстрационными обработчиками.
5. Добавить собственные идентификаторы/брендинг и Windows-пакет; затем проверять Android, macOS, iOS и Linux в соответствующих окружениях. Apple требует Mac/Xcode и своих capabilities/signing.

## Важные границы

- В OneXray `pages → service → core`; UI-only изменение сохраняет текущие контракты. Документация оригинала — [docs/README.md](../docs/README.md), сборка — [build_scripts/README.md](../build_scripts/README.md).
- «Игровой / Рабочий» пока только переименованные Karing «Правила / Глобально». В OneXray нужно отдельно определить эквивалентное поведение; не приравнивать автоматически Smart/Custom к этим режимам.
- Экспорт Karing — sing-box JSON. Перенос одного сервера не переносит правила, DNS, группы/автовыбор или все inbounds. В исходном обезличенном примере были 42 VLESS, 4 Hysteria2, 3 urltest, 42 route rules, 73 binary SRS sets, сложный DNS. Все эти возможности ещё требуют сопоставления.
- В примере REALITY поле Xray `password` содержит публичный ключ. Приватные ключи, реальные UUID, подписочные URL, пароли и заполненные конфиги не коммитить.
- Не запускать собранный Core «для справки» и не подключать тестовый клиент автоматически: WindowsCoreProcess умеет завершать OneXrayCore.exe по имени. Другой каталог сам по себе не изолирует процессы.
- Никаких автоматических публикаций в магазины: upstream release-команды Apple/Android включают внешние действия. Пользователь разрешил Git commits/push этих наработок, не публикацию продукта в Store.
- Сохранять `LIBXRAY_REF=main` в upstream workflow. Для повторения выполненной проверки использовать commit manifest и записывать фактические версии.

## Локальная машина исходного исследования

Корень: `C:/Users/Onety/Documents/Codex/2026-10-20/rfr`.

- Этот checkout: `work/onexray-audit/source`, ветка `veilor/onexray`.
- Соседние зависимости: `work/onexray-audit/libXray`, `work/onexray-audit/Vole`.
- SDK: `work/onexray-audit/toolchains`; Python: `C:/Users/Onety/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.
- Cargo cache: `C:/Users/Onety/Documents/Codex/ox-build/cargo` — укорочен из-за Windows path too long.
- Старый Karing checkout: `outputs/veilor`, архивная ветка `veilor/core-readonly-adapter`.
- Родительский `Enter-BuildEnvironment.ps1` и оригиналы логов остаются локально. Переносимый вариант окружения — [scripts/enter-build-environment.ps1](scripts/enter-build-environment.ps1).

Кэши/SDK/бинарники и реальные данные не включены. Их отсутствие в Git намеренно; повторная подготовка описана в build guide, зависимости закреплены manifest и их upstream lockfiles.

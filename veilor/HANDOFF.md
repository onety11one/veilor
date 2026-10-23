# Точка продолжения Veilor / OneXray

Обновлено 23.10.2026. Пользователь прекратил направление Karing и разрешил сохранить архив, создать эту ветку и продолжить разработку на основе OneXray. `main` не изменять без отдельной задачи. Не возобновлять реверс Karing как основной план.

## Что уже подтверждено

- Пользователь импортировал вручную восстановленный VLESS/REALITY-узел из Karing в установленный OneXray и подтвердил подключение. Для Windows понадобился явный выбор физического Wi-Fi/Ethernet в Advanced → VPN Tunnel → Xray outbound interface.
- Это проверка готового OneXray. Теперь также успешно скомпилированы собственные Windows x64 Debug и Release, но их запуск и VPN-трафик ещё не проверялись.
- Исходники OneXray, libXray, Vole и закреплённого boring/BoringSSL доступны. `cargo fetch --locked --target x86_64-pc-windows-msvc` завершился успешно.
- Подготовлены отдельные Flutter 3.47.7 / Dart 3.13.5, Go 1.27.3, Rust 1.99.1, LLVM-MinGW 20261020, libclang 18.1.1.
- `flutter pub get` и `flutter gen-l10n` завершились успешно. Новые версии зависимостей сверх lockfile специально не выбирались.
- Штатная Windows-сборка libXray завершилась успешно: DLL, header, Core EXE и полный GeoData. Проверены x64/PE32+ и экспорты CGoInvoke/CGoFree, без загрузки DLL или запуска Core.
- Ранее прошли 35 тестов упаковочных Python-скриптов. Они не подтверждают сборку UI или работу VPN.
- Vole собран штатной командой: DLL и оба UWP host EXE; Wintun 0.14.1 получен с официального сайта. Все шесть native runtime-файлов проверены по хэшам после копирования в Debug и Release bundle.
- Пройдены 33 существующих mock-теста Windows EXE/native API. Они не запускали настоящий Core и не меняли рабочее подключение.
- Добавлены поддержка переносимого libclang в tool/ffigen.dart и подготовка отдельного MSVC/MinGW окружения в helper. Анализ изменённого Dart-генератора: без замечаний. Runtime/UI-код приложения не менялся.
- Сформирован Release ZIP: outputs/OneXray-Windows-x64-Release-2026-10-23.zip, 70 175 933 байта; 75 файлов, ZIP CRC проверен. Пакет содержит исходный UI OneXray; «Лента» ещё не перенесена. Подробности: [отчёт сборки](research/BUILD-WINDOWS-2026-10-23.md).

## Текущая точка

Прежние блокеры сборки устранены: установлен Visual Studio Build Tools 2026 18.11.1 с ATL, добавлен NASM 3.02, скомпилирован Vole, получен Wintun, FFI сгенерирован. Короткие Cargo target и Flutter build-dir обязательны для текущего глубокого workspace. TLS-проверки не отключались; зависимости не обновлялись.

Следующая задача — безопасная проверка запуска. В базовой сборке пока сохранены оригинальные product/company identifiers и имя OneXrayCore.exe. Нельзя предполагать изоляцию от установленного OneXray из-за другого каталога: возможны общие данные и управление Core по имени. До запуска подготовить отдельный тестовый профиль/идентификаторы и исключить взаимодействие с рабочим VPN. Не запускать автоматически ZIP из текущего отчёта рядом с действующим клиентом.

## Порядок следующих работ

1. Сборка завершена; команды повторения — [BUILD-WINDOWS.md](BUILD-WINDOWS.md). Исправления текущего этапа ещё не закоммичены и не отправлены автоматически.
2. Подготовить изоляцию и проверить запуск. Не мешать установленному рабочему OneXray и его соединению.
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
- Старый Karing checkout outputs/veilor удалён по одобрению пользователя вместе со старыми инструментами/лабораторией. Архивная ветка veilor/core-readonly-adapter остаётся в GitHub, commit 2ddb6b52. PHP API, функциональные справочники, дизайн и резервный portable-build сохранены.
- Cargo target: `C:/Users/Onety/Documents/Codex/ox-build/vt`; Flutter build-dir: `C:/Users/Onety/Documents/Codex/ox-build/wd`. Bundle каждого режима — windows/x64/runner/Debug или Release внутри wd.
- Родительский `Enter-BuildEnvironment.ps1` и оригиналы логов остаются локально. Переносимый вариант окружения — [scripts/enter-build-environment.ps1](scripts/enter-build-environment.ps1).

Кэши/SDK/бинарники и реальные данные не включены. Их отсутствие в Git намеренно; повторная подготовка описана в build guide, зависимости закреплены manifest и их upstream lockfiles.


## Изоляция Windows EXE — 23.10.2026

Windows EXE теперь Veilor.exe, CompanyName=SigmaGate, ProductName=Veilor.
path_provider и shared_preferences используют собственные Roaming/Local AppData
SigmaGate/Veilor. Существующие данные не копируются. Core запускается и
обнаруживается как VeilorCore.exe; CMake переименовывает штатный native артефакт
windows/app/OneXrayCore.exe при установке bundle. Отдельные Veilor.lnk,
notification AppUserModelID/GUID и VeilorTun. MSIX и другие платформы ещё не
полностью переименованы; этот этап только Windows EXE.

Новый Flutter build-dir: C:/Users/Onety/Documents/Codex/ox-build/wv.
Старый CMake cache wd содержит TARGET_FILE_DIR:OneXray; не смешивать bundle.
Имена и данные разделены, системные маршруты/DNS остаются общими: два VPN
одновременно не включать. Подключение проверяет пользователь вручную после
отключения VPN в установленном клиенте. Реальные профили автоматически не читаем.


Результат изоляции: Release exit 0; пакет
outputs/Veilor-Windows-x64-Preview-2026-10-23.zip, 66 127 044 байта, 75 файлов,
SHA256 fedd1910dc82eaf4cd86b9163ce1a2f07b70d32cc38bfc592a91de63dde79614.
ZIP CRC и все 6 native хэшей проверены. Готовый PE: SigmaGate / Veilor /
Veilor.exe. Анализ изменённого Dart без замечаний; группы тестов 44 и 57 прошли
(часть автозапуска повторена); реальные native process-тесты используют только
переименованные уникальные cmd.exe fixtures, без VPN/сети. UI и VPN этой сборки
не запускались. Пользователю передан ZIP для ручного подключения.
Следующий шаг: получить результат ручной проверки и перейти к «Ленте».
Изменения этого этапа локальные, commit/push не выполнены.


## Ручная проверка пользователем — 23.10.2026

После получения Veilor-Windows-x64-Preview-2026-10-23.zip пользователь сообщил:
«супер, всё работает!» и поручил закоммитить результат. Запуск и VPN отмечаем
как подтверждённые пользователем; отдельные результаты по DNS, всем протоколам,
маршрутизации и параллельной работе клиентов не запрашивались и не доказаны.
Сведения выше о непроверенном запуске относятся к состоянию до этого сообщения.
Следующая работа — перенос утверждённой «Ленты» через существующие сервисы.

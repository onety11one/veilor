# Успешная сборка OneXray для Windows x64

23.10.2026. Продолжение первоначального аудита и подготовки окружения. Этот отчёт фиксирует компиляцию и проверки файлов, не запуск приложения или VPN.

## Результат

| Проверка | Итог |
| --- | --- |
| Flutter doctor: Windows / Visual Studio | OK; Build Tools 2026 18.11.1, SDK 10.0.26100.0 |
| Vole Windows UWP, штатный builder | exit 0, DLL и два host EXE |
| Официальный Wintun 0.14.1 | HTTPS Range, ZIP CRC OK |
| FFI generation | exit 0 |
| Dart analyze tool/ffigen.dart | exit 0, no issues |
| Существующие Windows EXE/native API mock-тесты | 33 passed, exit 0 |
| Flutter Windows Debug | exit 0 |
| Flutter Windows Release | exit 0 |
| Шесть native-файлов в обоих bundle | SHA256 совпали с подготовленными исходными артефактами |
| Прямые PE DLL-зависимости Release | отсутствующих в bundle/System32 не найдено; Windows API sets учитывались отдельно |
| Release ZIP | 75 файлов, CRC OK |
| Запуск UI / реальный VPN / DNS и трафик | NOT RUN |

Release ZIP: `outputs/OneXray-Windows-x64-Release-2026-10-23.zip`, 70 175 933 байта.
SHA256: `57dbb22974951cbe95f10a56d1810a73d478a4acbef602b6823b71edb35c30af`.

Основной отчёт: [windows-build-success.json](windows-build-success.json). Пакет: [windows-release-package.json](windows-release-package.json). Журналы — evidence/. Исходная точка приложения cd0a463; текущие изменения инструментов/документов локальные и ещё не закоммичены.

## Исправления и окружение

- Установленный C++ комплект обнаружен Flutter. Для уведомлений дополнительно потребовался ATL (Microsoft.VisualStudio.Component.VC.ATL). Он добавлен штатным Visual Studio Installer с UAC; рабочий фоновый MSBuild нашей завершённой сборки предварительно остановлен. Код плагина не менялся.
- NASM 3.02 добавлен отдельно; без него aws-lc-sys останавливал сборку.
- Rust/CMake и Flutter/MSBuild потребовались короткие output paths: текущие vt и wd находятся в C:/Users/Onety/Documents/Codex/ox-build. Системная политика long paths не менялась. Flutter config относится к отдельному APPDATA окружения сборки.
- MinGW нужен Go/CGo, но его clang/header discovery мешал MSVC bindgen. Helper включает MinGW только с EnableMinGW и удаляет его из PATH при возврате к MSVC.
- tool/ffigen.dart поддерживает явный LIBCLANG_PATH; без переменной остаётся прежний поиск. Генерация выполняется исходным ffigen, сгенерированные bindings вручную не правились.
- Обычная полная загрузка Wintun зависала. Скрипт download-wintun.py получил официальный архив малыми HTTPS Range-запросами, проверяя ETag, Content-Range и ZIP CRC. TLS verification оставалась включённой. Хэши зафиксированы после загрузки, независимая upstream checksum не сверялась.
- Исходники Vole, его Cargo.lock и public headers не менялись. Локальные libXray/Core уже были собраны на прошлом этапе; их хэши сохранены и совпадают в новом bundle.

## Ограничения пакета

ZIP — базовый OneXray с исходным интерфейсом, без реализации «Ленты», API учётных записей и реальных конфигураций пользователя. Подпись собственного Veilor и установщик не подготовлены; это локальный Release bundle, не публикация в Store. Лицензии OneXray/libXray/Vole/Xray-core/Wintun добавлены в пакет, полный release license audit не выполнялся.

В базовой сборке сохраняются идентификаторы OneXray и глобальный поиск Core по имени. Статическая проверка imports/хэшей и mock-тесты не доказывают запуск Windows App, установку драйвера, доступность серверов или отсутствие утечек. Изоляция данных и процесса, затем контролируемый запуск — следующий шаг. Установленный клиент, его реальные профили и текущее соединение не читались/не менялись.

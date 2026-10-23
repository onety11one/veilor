# Сборка анализатора и карта методов

22 октября 2026. После разрешения пользователя приняты условия Microsoft и получены portable MSVC/Windows SDK. Анализатор собран под Dart 3.12.2. Два запуска диагностической сборки успешно загрузили сохранённый snapshot и дали одинаковую выбранную карту методов. Это ещё не сборка Veilor.

## Инструменты и проверки

- MSVC family 14.44.17.14, tools 14.44.35207, host/target x64; SDK 10.0.26100.0. Загрузчик сообщил 457 MB загрузки. Payloads проверены по SHA-256 из Microsoft manifest.
- CMake 3.31.6, Ninja 1.13.2, ICU 73.2, Capstone C++ 4.0.2.
- Windows fork 1903247335/blutter-windows commit 6b69d5cf3055480f198c88ae92f000e9dbd704c5.
- Dart source 3.12.2 commit d684a576a6aa954ae107a03b2b4e1d61c3bebe93. Настоящий format hash 15 исходников совпал со snapshot: ace654289f5abc240509fc941453ebc5. Подмены hash нет.
- Загрузчик portable-msvc.py revision 49b58850aa5e5c1e65f090d4651ee76607883e11. Защитная обёртка ограничивает cleanup дочерними путями msvc/downloads в рабочей папке. Принятие условий записано в license-acceptance.json. SDK извлечён через msiexec /a, без /i.
- Собственный C++20 пример с std::format и Windows.h собран и выполнен: compiler-smoke.json. INCLUDE/LIB/PATH задавались дочерним процессам.
- Собраны VM и pool-only анализатор Windows x64 без compressed pointers, с NO_CODE_ANALYSIS. /Zc:preprocessor нужен для __VA_OPT__, /EHsc добавлен для исключений C++ анализатора. Исходники формата Dart не менялись.

## Результат и ограничения

Справка инструмента работает. Первый запуск завершился 0xC0000005 без дампа; причина не установлена. После добавления stderr-маркеров в DartApp.cpp/DartLoader.cpp и пересборки два запуска завершились с кодом 0 и создали по 2174 файла. Общая стабильность инструмента не доказана. Изменения инструмента записаны в blutter-diagnostic.patch.

В четырёх выбранных файлах vpn_service извлечены 42 записи методов. Имена, адреса и размеры совпали в двух успешных запусках. VpnServiceConfig: class id 314, размер 0xd0, constructor 0xd8652c/0xe8, две записи toJson 0xd8662a/0x3c и 0xd86650/0x4e0. Роль дублирующей записи ещё не интерпретирована. Эти три диапазона независимо дизассемблированы Capstone; все байты декодировались. Отдельный fromJson в карте класса не обнаружен; inlining/tree shaking не исключены. **Имена полей, defaults и переходы состояний ещё не восстановлены.**

Артефакты: [vpn-aot-methods.json](vpn-aot-methods.json), [vpn-config-x64.txt](vpn-config-x64.txt), [pool-analysis-runs.json](pool-analysis-runs.json). Полные pools/objects остаются в work/karing-feasibility/aot-pool-*. Сгенерированный Frida script не запускался, подключения к процессам не было.

Загрузка snapshot в собственную Dart VM/isolate отличается от статического чтения ELF: VM может выполнять внутренние stubs. В просмотренном пути нет app main, Dart_Invoke/Dart_RunLoop. Запуски использовали отдельные рабочие APPDATA/LOCALAPPDATA/TEMP/USERPROFILE. Установленные karing.exe/karingService.exe не запускались, команды управления VPN не отправлялись. Ранее работавшие PID 26128/21252 сохранились.

Скрипты рядом — копии для review, привязанные к рабочим папкам work/toolchains/portable-build и work/karing-feasibility; из research их запускать нельзя. build-pool-only.py только собирает, run-pool-only.py анализирует snapshot с закреплённым SHA-256, extract-vpn-methods.py проверяет две карты и публикует выбранные метаданные.

Следующий шаг — сопоставить constructor/toJson с object pool и смещениями полей, затем параметры Windows _start/waitConnect/_stop. Активные lib/bind/windows/pubspec не изменены. Коммит/push не выполнялись.

## Продолжение: начальные значения VpnServiceConfig

В следующем offline-шаге сопоставлены все 25 ключей с полями и восстановлены constructor defaults: 23 прямых скалярных присваивания и 2 значения через factory/allocation. Подробности и ограничения: [VPN-CONFIG-RECOVERY.md](VPN-CONFIG-RECOVERY.md). Ранее указанный статус «defaults не восстановлены» относится к моменту первоначального составления этого отчёта. Значения после заполнения вызывающим кодом всё ещё требуют исследования.

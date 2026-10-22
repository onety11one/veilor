# Dart AOT: версия, параметры службы и граница восстановления

22 октября 2026. Прочитан сохранённый app.so из установленного Karing 1.2.25+2802; SHA-256 `38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882`. Установленные профили, secret и device ID не читались. Ни приложение, ни core, ни snapshot в Dart VM не запускались.

**Результат:** определён точный формат snapshot, найден подходящий по платформе путь анализа и уточнены два факта из публичных исходников. Тела AOT-методов и полный serializer пока не восстановлены.

## Snapshot

app.so — ELF64 little-endian, EM_X86_64. Экспортированы адреса VM/isolate SnapshotData и SnapshotInstructions. Их наличие не означает, что в ELF есть таблица Dart-методов: function boundaries и object pool ещё не декодированы.

Заголовки обоих data snapshot имеют FullAOT kind=3 и общий форматный hash:

```text
ace654289f5abc240509fc941453ebc5
```

Флаги сообщают product, x64, windows, no-compressed-pointers, no-code_comments и no-dwarf_stack_traces_mode. Flutter engine сообщает **Dart 3.12.2 stable**. Заголовок сверялся с [snapshot.h Dart 3.12.2](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/snapshot.h); определение версии независимо подтвердил reviewed extract_dart_info.py из Windows-порта Blutter. Это только разбор файлов, не десериализация snapshot в VM.

В snapshot найдены имена VpnServiceConfig, FlutterVpnService, prepareConfig, proxy_manager.dart и строки control_port, secret, service-config, service-http-port, connected-port. Инвентарь сохраняет только allowlist имён и смещения. **Соседство строк и совпадение имён не дают default-параметры или адрес метода.** Содержимое произвольных строк, URL и ключей не выгружалось.

## Что удалось подтвердить исходниками

| Факт | Версия доказательства | Ограничение |
| --- | --- | --- |
| SettingConfigItemProxy.controlPortDefault = 3057 | Публичный commit 0c320dc182d095ec0d483f852169421e749c2bac, tag установленной версии v1.2.25.2802 | Это default настройки Clash API, не служебного HTTP-порта |
| При отсутствии control_port fromJson берёт 0, затем заменяет 0 на controlPortDefault | Тот же setting_manager.dart | Не означает, что запущенный экземпляр использует default; настройки не читались |
| getSecret() получает Did.getDid() и берёт substring(8,24) | Исторический публичный commit e3c19f1eb1225dbd48a4862f0983b82d0af8de69 | Для установленного AOT этот алгоритм ещё не подтверждён |
| Service config.secret и core experimental.clash_api.secret получают один API secret | Та же старая VPNService/ClashApi/SingboxConfigBuilder-обвязка | Текущая AOT-реализация отсутствующего пакета ещё не разобрана |

Никаких реальных значений из этих выражений не вычисляли. Алгоритм старой версии не перенесён в новый код как автоматически верный default. Текущий serializer продолжает сохранять явно переданные параметры, не генерируя ID/secret и не смешивая три порта: Clash API, служебный HTTP, parent connected listener.

Matching setting_manager.dart сохранён в work/karing-feasibility/matching-source; исторические файлы — в research/karing-vpn-service-reference. В `dart-aot-verified.json` факты помечены точными commit и отдельно флагом currentAotVerified=false для старого secret-алгоритма.

## Инструмент и препятствие

Обычный [Blutter](https://github.com/worawit/blutter) ориентирован на Android arm64. Проверен [Windows x64 fork](https://github.com/1903247335/blutter-windows) на commit `6b69d5cf3055480f198c88ae92f000e9dbd704c5`. Его Python-исходники просмотрены; запускался только режим **detect-only**, который возвращается до сборки/загрузки snapshot. Он правильно определил 3.12.2/windows/x64/no-compressed-pointers. Полноценный анализ x64 у fork обозначен как MVP, не паритет arm64.

В проверенном [release v0.1.0](https://github.com/1903247335/blutter-windows/releases/tag/v0.1.0) опубликован prebuild для **Dart 3.3.4**, не 3.12.2. Этот бинарник не скачивался и не запускался; подмена hash/форсирование несовместимой VM не выполнялись. Для нашего snapshot потребуется собрать и проверить совместимость инструмента с нужной VM/flags; одного совпадения номера Dart недостаточно, нужен и формат snapshot.

В текущем окружении не обнаружены cl.exe/clang-cl.exe, cmake.exe, ninja.exe в PATH; стандартный vswhere также отсутствует. Это не полный аудит всех дисков, но настроенного C++-инструментария для такой сборки сейчас нет. Системные Build Tools не устанавливались. Совместимость исходников Windows fork с Dart 3.12.2 ещё предстоит проверить при сборке.

Небольшие Python-зависимости установлены только в workspace: pyelftools 0.32 и requests 2.32.5 с зависимостями в work/karing-feasibility/python-deps. Они нужны для независимой проверки detector, не для запуска Karing. Репозиторий инструмента находится отдельно в work/toolchains/blutter-windows; в исходники Veilor он не добавлялся. Build scripts не запускались, зеркала и большие SDK-архивы ими не скачивались.

## Артефакты и проверка

- dart-aot-inventory.json: ELF, snapshot headers, allowlist строк и смещения.
- dart-aot-verified.json: **29 проверок метаданных и исходников**, mode=detect-only, snapshotLoadedIntoVm=false, methodRecovery остаётся незавершённым.
- inspect-dart-aot.py, detect-dart-tool.py, verify-dart-aot.py: воспроизводятся из корня workspace локальным Python. Их копии сохранены рядом с отчётом.

Новые runtime-тесты Dart не запускались: код приложения/стенда этим этапом не менялся. Установленные karing и karingService продолжают работать; активные lib/bind/windows/pubspec приложения без изменений. Коммит/push не выполнялись.

Подготовка C++-инструментария продолжена в [TOOLCHAIN-PREP.md](TOOLCHAIN-PREP.md): CMake/Ninja, ICU/Capstone и точные исходники готовы, реальный format hash исходников совпал со snapshot без подмены. Получение выбранных MSVC/SDK-компонентов ожидает подтверждения лицензии Microsoft. После сборки и проверки pool-only анализатора можно искать VpnServiceConfig constructor/toJson/fromJson; пока это не сделано, оставшиеся defaults и карту состояний нельзя считать восстановленными.

## Обновление после разрешения пользователя

MSVC/SDK получены, анализатор собран под точный Dart 3.12.2. Два запуска диагностической сборки загрузили snapshot и дали одинаковые 42 записи методов в четырёх выбранных файлах vpn_service. Найдены constructor и две записи toJson VpnServiceConfig; их машинный код дизассемблирован. Defaults и соответствие полей пока не восстановлены. Первый запуск завершился ошибкой доступа к памяти; причина не установлена. Текущий результат и ограничения: [TOOLCHAIN-PREP.md](TOOLCHAIN-PREP.md). Описанные выше отсутствие компилятора и detect-only отражают предыдущий этап; dart-aot-verified.json остаётся отчётом того этапа.

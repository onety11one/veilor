# VpnServiceConfig: поля и начальные значения

22 октября 2026. Продолжение AOT-исследования. Восстановлены соответствие всех **25 JSON-ключей полям объекта** и значения сразу после конструктора для исследованного Karing **1.2.25+2802** / Dart **3.12.2**.

**Это не готовая конфигурация запуска.** Вызывающий код может изменить каждое поле до сериализации. Результат не доказывает совместимость с исходной базой 1.2.26+2908 или то, что все поля используются Windows-службой.

## Схема

Смещения ниже измерены от начала нетегированного объекта. Машинное смещение относительно tagged pointer на единицу меньше.

| JSON-ключ | Смещение | Значение после конструктора |
| --- | --- | --- |
| control_port | 0x08 | 0 |
| base_dir | 0x10 | пустая строка |
| work_dir | 0x18 | пустая строка |
| cache_dir | 0x20 | пустая строка |
| core_path | 0x28 | пустая строка |
| log_path | 0x30 | пустая строка |
| err_path | 0x38 | пустая строка |
| id | 0x40 | пустая строка |
| version | 0x48 | пустая строка |
| name | 0x50 | пустая строка |
| secret | 0x58 | пустая строка |
| install_refer | 0x60 | пустая строка |
| prepare | 0x68 | true |
| wake_lock | 0x70 | false |
| auto_connect_at_boot | 0x78 | false |
| allowed_sender_packages | 0x80 | новый пустой GrowableList<String> |
| include_all_networks | 0x88 | false |
| exclude_local_networks | 0x90 | false |
| exclude_cellular_services | 0x98 | false |
| exclude_apns | 0xa0 | false |
| exclude_device_communication | 0xa8 | false |
| enforce_routes | 0xb0 | false |
| auto_route_use_sub_ranges_by_default | 0xb8 | false |
| disconnect_after_sleep_seconds | 0xc0 | 0 |
| sentry_minversion | 0xc8 | null |

## Как проверено

- Входной app.so закреплён SHA-256 38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882.
- Код constructor 0xd8652c/0xe8 и serializer 0xd86650/0x4e0 заново дизассемблирован напрямую из ELF. Запуска VM/ядра в этом шаге нет.
- Каждая строка-ключ связывается с последующей загрузкой поля receiver, а не с соседством строк в бинарнике. Проверены последовательные позиции ключей в массиве для map literal; набор совпал со всеми 25 ранее наблюдёнными ключами.
- Использованные записи pool совпали в двух предыдущих успешных AOT dumps. PP=R15; обращение по displacement d соответствует печатному pp offset d+1. Публикуются только выбранные ключи, пустая строка и type arguments.
- Две записи toJson объясняются делегированием: 0xd8662a вызывает 0xd86650. Диапазон первой записи в прежнем dumper перекрывает начало второй; нельзя трактовать его как отдельную полную реализацию. Здесь wrapper проверен только до 0xd86650.
- Булевы значения проверены по AOT/product/x64/no-compressed-pointers блоку официального runtime_offsets_extracted.h точного Dart source: true 0x90, false 0x98, null 0x80 относительно Thread. Это не предположение по порядку полей.
- 23 скалярных defaults извлекаются из прямых присваиваний. Для списка проверены нулевая длина RSI, type arguments <String>, вызов GrowableList factory 0xa579f8, запись длины 0 и сохранение результата в поле 0x80.
- sentry_minversion не перезаписывается конструктором. Stub 0xd86b50 переходит к generic allocator 0x1533420, который заполняет поля каноническим null; fast path подтверждён машинным кодом и GenerateAllocateObjectHelper точного Dart source. Slow path опирается на семантику VM runtime, а не на выполненную здесь live allocation.

Официальный source: dart-lang/sdk commit d684a576a6aa954ae107a03b2b4e1d61c3bebe93, runtime/vm/compiler/runtime_offsets_extracted.h и stub_code_compiler_x64.cc. Provenance SDK/toolchain описан в [TOOLCHAIN-PREP.md](TOOLCHAIN-PREP.md).

## Артефакты и продолжение

- [vpn-config-recovered.json](vpn-config-recovered.json): значения и адреса доказательств каждого поля.
- [vpn-config-helper-x64.txt](vpn-config-helper-x64.txt): выбранные factory/allocation инструкции.
- recover-vpn-config.py: воспроизводимая offline-проверка; рабочий оригинал в work/karing-feasibility. Копия в research предназначена для review и требует восстановления структуры workspace, SDK, Capstone/pyelftools и двух pool dumps.

Реальные ID/secret, профили, порты и настройки пользователя не читались. Восстановленные defaults не перенесены в production serializer и не используются для запуска. В частности control_port=0 здесь не отменяет ранее найденный default пользовательской настройки 3057: это разные этапы формирования конфигурации.

Следующий шаг — исследовать присваивания вызывающего слоя перед сериализацией, затем Windows _start/waitConnect/_stop. Особенно нужны пути, control_port/secret и происхождение sentry_minversion. Политику телеметрии и проверки версии не подменять.

## Следующее уточнение: источники перед запуском

Сопоставлены присваивания всех 25 полей в вызывающем коде, проверены вложенные поля настроек и static slots Windows prepareConfig. Подтверждён текущий AOT getSecret без вычисления значения. Полная политика версии и запуск ещё открыты: [VPN-CONFIG-PREPARATION.md](VPN-CONFIG-PREPARATION.md).

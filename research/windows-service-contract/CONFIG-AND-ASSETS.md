# Windows service.json и файлы ядра

22 октября 2026. Исследован сохранённый Karing core 1.2.25+2802 с SHA-256 `023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea`, старые публичные Dart-исходники и имена публичных assets. Ядро не запускалось, конфигурации пользователя не читались. Это уточнение контракта, **не полное восстановление serializer отсутствующего Flutter-пакета**.

## Что теперь известно о полях

Доказана привязка `libbox.init.0` → function value `SentryInitPrivate` → global 0x143569e40 → чтение того же global в `SentryInit`. Ранее эта связь оставалась неизвестной. Инициализация SDK подключает обработчик чтения service.json; внутри Private видны fastjson, пять GetStringBytes, сравнение версии и инициализация Sentry. Это не основание изменять или обходить его политику; код ядра и значения настроек не менялись. URL телеметрии не переносился в новые документы/артефакты.

| Поле | Подтверждённый потребитель | Обязательность |
| --- | --- | --- |
| core_path | setUpDir и SentryInitPrivate | В setUpDir явно проверяется непустая строка |
| base_dir | setUpDir → Setup | Наличие и default целиком не установлены |
| work_dir | setUpDir → Setup | То же; старая Windows-обвязка передаёт каталог data |
| cache_dir | setUpDir → Setup | Default целиком не установлен |
| err_path | setUpDir → StderrRedirect | Передаётся в файловое перенаправление; отсутствие не объявляем допустимым |
| log_path | SentryInitPrivate | Читается как строка; обязательность не установлена |
| id | SentryInitPrivate | Читается как строка; обязательность не установлена |
| version | SentryInitPrivate | Читается как строка, используется в SDK; обязательность не установлена |
| sentry_minversion | SentryInitPrivate → compareVersion | Есть условная ветка сравнения; defaults/политика не подменялись |

Для остальных **16 наблюдаемых полей** соответствие Windows-потребителю не доказано:

`control_port`, `name`, `secret`, `install_refer`, `prepare`, `wake_lock`, `auto_connect_at_boot`, `allowed_sender_packages`, `include_all_networks`, `exclude_local_networks`, `exclude_cellular_services`, `exclude_apns`, `exclude_device_communication`, `enforce_routes`, `auto_route_use_sub_ranges_by_default`, `disconnect_after_sleep_seconds`.

Они не удалены и не признаны ненужными. Часть может обрабатываться отсутствующим Dart/Flutter-транспортом, другим бинарником или косвенным/reflection-путём. По одним названиям платформу не назначаем. Наблюдаемые типы всех 25 полей, подтверждённые readers и статус обязательности сохранены в `service-config-contract.json`. Кандидатные прямые RIP-xrefs — в service-field-xrefs.json; совпадения коротких id/name/secret в других библиотеках не выдаются за чтение service.json.

Трасса ядра после подготовки также уточнена: BoxService.Start → StartedService.StartOrReloadService → newInstance → daemon.parseConfig → UnmarshalExtendedContext, затем sing-box.New/Box.Start. Этот parser относится к core JSON; наличие parseConfig не доказывает декодирование всех полей service.json.

## Файлы: разные причины зависимости

| Группа | Основание | Вывод |
| --- | --- | --- |
| service.json, service_core.json | Подтверждённое чтение файлов и core_path | Создаются отдельно для запуска |
| logs/cache/base/work | Setup, stderr и старая обвязка | Нужны собственные пути и права записи; полный список возможных записей не закрыт |
| Local .srs | Старый builder задаёт относительные пути | Доставлять именно файлы, на которые ссылается core JSON, сохраняя иерархию |
| Remote rule sets | В builder есть отдельная remote-ветка | Не заменять локальными и не скачивать при подготовке стенда |
| KERNEL32.dll, msvcrt.dll | PE import table исследованного core | Это статические импорты, не весь список runtime-зависимостей |
| libcronet.dll | findLibrary → os.Executable/PATH/os.Stat; doLoadLibrary → syscall.LoadLibrary | Подтверждён динамический loader, не найденный простой PE-таблицей; охват профилей/момент вызова не установлен |
| Flutter UI, WebView, шрифты, изображения, TUN-драйверы | Другие подсистемы/пакет приложения | Не объявлены лишними или восстановленными на этом шаге |

В публичном repo assets/datas найдено **2417 файлов**, в установленном пакете — **2457**; 47 имён есть только в установленном пакете, 7 — только в repo. Сравнивались имена/размеры, не идентичность содержимого и не функциональная необходимость каждого файла. Версии приложения различаются; автоматически смешивать наборы нельзя. Инвентарь — `core-file-inventory.json`.

## Исправление подготовки локальных правил

Старый Windows PathUtils.appAssetsDir указывает на `<app>/data`, а builder пишет, например:

```text
flutter_assets/assets/datas/geoip/ru.srs
flutter_assets/assets/datas/geosite/youtube.srs
flutter_assets/assets/datas/acl/<name>.srs
```

Поэтому пустой work_dir стенда недостаточен для профиля с local rule_set. Добавлен `LocalRuleAssets` и интеграция в WindowsLaunchPlan.prepare через bundledAssetsRoot:

- Выделяет локальные binary rule sets трёх восстановленных семейств; не меняет core JSON и пути в нём.
- Переносит только выбранные файлы из публичного assetsRoot в work/flutter_assets/assets/datas/..., сохраняя байты.
- Сначала готовит временное дерево, публикует его после успешного копирования всего набора. При ошибке частичное дерево убирается; существующий flutter_assets не перезаписывается.
- Проверяет относительные пути, выход через symlink и первые три байта SRS. Это не полная проверка формата/версии или семантики правила.
- Все bundled .srs имена проверены на представимость, включая варианты `@!cn`. Пробелы в родительском Windows-пути не влияют на эти имена.
- Remote/inline остаются отдельными ветками; загрузок нет. Неизвестный тип, Android is_asset или нестандартный local path отклоняются явно — эта реализация пока ограниченная, не полная поддержка всех SDK rule sets.
- Если профиль требует local assets, а источник не указан, подготовка завершается ошибкой вместо плана с недостающими правилами.

Произвольные сертификаты, внешние local rule files, remote cache paths, UI-ресурсы и драйверы этот helper ещё не упаковывает. Его нельзя считать полным упаковщиком приложения.

## Проверка и следующий шаг

**19 статических проверок** подтверждают привязку hook, ключи, parser и dynamic loader; `verify-config-consumers.py` воспроизводит `service-config-contract.json`. **13 новых Dart-тестов** проверяют перенос настоящих .srs по SHA-256, весь набор имён, пропуски/плохой заголовок, запрет traversal и отсутствие частичной публикации. 15 тестов плана запуска проходят, analyzer — без замечаний. Core не запускался; установленный Karing и активное приложение не менялись. Коммит/push не выполнялись.

Скрипты config-consumers.py/service-field-xrefs.py/core-file-inventory.py/verify-config-consumers.py сохранены рядом. Запускаются из корня workspace локальным Python с подготовленным Capstone и snapshot. Dart-проверки находятся в packages/veilor_core_transport_lab/test/assets_test.dart.

Полную Windows-схему service.json пока нельзя честно объявить восстановленной. Продолжение AOT-исследования — [DART-AOT.md](DART-AOT.md): определены точная VM/flags и источник controlPortDefault=3057, но методы snapshot ещё не декодированы; для pool-only анализа требуется подходящий C++-инструментарий. Для реального испытания ядра по-прежнему нужна изолированная Windows-среда; совпадение имени с работающим Karing блокируется preflight.

# Контракт vpn_service и Windows: исследование 22 октября 2026

Продолжение: [частично восстановлен протокол самого karingService — run2, флаги, HTTP GET /reload и /stop, callback-порт](SERVICE-PROTOCOL.md). Это уточняет перечисленные ниже неизвестные части; runtime-совместимость ещё не подтверждена.

Цель этого шага — установить реальные границы восстановления запуска/остановки/событий. Это исследование текущего Karing и исторической обвязки, не реализация работающего пакета vpn_service.

## Главный вывод

Можно восстановить значительную часть верхнего Dart-контракта и отдельно системные операции Windows. **Нижний транспорт управления Karing core ещё не установлен**: отсутствуют реализация FlutterVpnService, аргументы запуска/протокол управления karingService, формат ответа и доставка событий. Стандартный sing-box и уже пройденные локальные стенды не являются заменой этого контракта.

Название karingService.exe само по себе не доказывает SCM-службу Windows. При чтении Win32_Service по именам/display names, содержащим karing/veilor, совпадений не найдено, хотя процессы karing и karingService работают. Служба под другим именем не исключена; текущий режим установки и переносимый режим могут различаться. Поэтому команды sc.exe install/start/stop нельзя назначать как восстановленный протокол по одному имени EXE.

## Версии и доказательства

- Текущие исходники: 1f52c28e062fe55d7c3ccc254f1a90d53fd8c103, приложение 1.2.26+2908; SettingConfig ожидает core 1.14.0.
- Историческая обвязка: e3c19f1eb1225dbd48a4862f0983b82d0af8de69; архив находится в соседнем research/karing-vpn-service-reference.
- Исследуемые установленные бинарники: Karing 1.2.25+2802; ранее GET /version возвращал sing-box 1.13.19.2802. Это другая версия относительно текущих исходников.
- pubspec.lock: vpn_service 0.12.15, локальный path ../vpn-service. Каталога нет; это не зависимость, которую восстанавливает обычный pub get.
- windows/flutter/generated_plugin_registrant.cc включает vpn_service_plugin.h и вызывает VpnServicePluginRegisterWithRegistrar. generated_plugins.cmake требует исходный plugin target. windows/CMakeLists.txt:142 дополнительно упаковывает bind/windows/core, который отсутствует.

source-and-native-inventory.json содержит вызовы FlutterVpnService из parser AST (комментарии исключены), публичные исторические методы, поля config и статические сведения DLL. Это инвентаризация без разрешения импортов/типов, не доказательство компилируемости.

local-schema-observation.json содержит только имена/типы полей service.json и безопасный снимок процессов/поиска SCM. Значения secret, ID, путей, настроек и командных строк не записывались.

## Три слоя, которые требуется восстановить

| Слой | Подтверждено | Пока неизвестно |
| --- | --- | --- |
| Верхняя Dart-обвязка VPNService | Последовательности prepare/start/restart/stop, правила таймаута, преобразование ошибок, ожидания UI | Новые методы initABI/prepareFiles и отличия текущей закрытой обвязки |
| Windows Flutter plugin | Имя канала vpn_service_plugin, регистрация, разобранный dispatcher с девятью командами proxy/firewall/autostart/admin | Полные схемы proxy options, codec/результаты helper-функций и все ветви системных отказов |
| FlutterVpnService ↔ karingService | EXE, service.json/service_core.json, start/restart wait result, currentState и callback на стороне вызывающего кода | Process.start argv, RPC/IPC paths/methods/auth, протокол остановки/reload, события и числовые enum |

Пути из исторического PathUtils: EXE рядом с приложением; service.json, service_core.json, service_error.log, service_core.log — в profileDir. Восстановление этих соглашений не даёт команду запуска автоматически.

## Подтверждённый верхний контракт Windows

Дополнительный результат native-разбора: цепочка регистрации 0x180005a50 → настройка обработчика 0x180005c80; адрес таблицы callback 0x180012c68, её slot 2 указывает на 0x1800062c0. Этот callback вызывает **dispatcher 0x180004c60**, который статически разобран Ghidra 12.1.4 через локальный REA.

В dispatcher найдены сравнения с девятью командами:

| Команда | Подтверждённые ключи/действия | Что осталось неизвестным |
| --- | --- | --- |
| isRunAsAdmin | Вызовы AllocateAndInitializeSid/CheckTokenMembership/FreeSid | Все fallback/error условия результата |
| cleanSystemProxy | Передача в helper 0x1800065d0 без аргументов | Точная политика владения/restoration proxy |
| setSystemProxy | Контейнер аргументов передаётся в helper 0x180008470 | Полная схема options, обработка неверных типов |
| getSystemProxyEnable | Контейнер передаётся в helper 0x180007bf0; результат упаковывается | Семантика сравнения текущего proxy и options |
| firewallAddApp | Ветки appPath/appName | Полные COM/HRESULT ошибки и гарантия применения правила |
| firewallAddPorts | Ветки ports/appName | Точный тип списка ports и результирующее представление ошибок |
| autoStartCreate | taskName/processPath/processArgs/runElevated | Полная схема результата и настройки Task Scheduler |
| autoStartDelete | taskName | Идемпотентность/ошибки удаления |
| autoStartIsActive | taskName | Различение отсутствия задачи и системной ошибки |

**start/stop/restart/currentState/installService/uninstallService в этом разобранном dispatcher отсутствуют.** Это локализует границу поиска: восстановить только девять команд DLL недостаточно для запуска VPN. Не исключаются другие каналы/реализации в отсутствующем Dart-коде; это не утверждение об отсутствии управления во всём приложении.

native-evidence.json содержит компактные ссылки/строки/адреса трёх новых разборов. native-dispatcher.pseudocode.txt — вывод декомпилятора, не оригинальный C++ и не готовая реализация; типы и имена временных переменных эвристические. Ни одна из системных команд плагина не вызывалась. SHA-256 снимка DLL: 901a53d40fafc0e39ae340a09bb9ca5f8479d69f03760102079843b4054325ea.

| Операция | Вход/выход, видимые в обвязке | Последовательность и граница знания |
| --- | --- | --- |
| init | async, подключает callback | isRunAsAdmin; добавление firewall-приложений; регистрация onStateChanged; prepareConfig; исторически на Windows затем stop. Эту инициализацию нельзя запускать как безопасную проверку — она меняет систему и останавливает core |
| prepareConfig | config и именованные tunnelServicePath/configFilePath/systemExtension/bundleIdentifier/uiServerAddress/uiLocalizedDescription/excludePorts | Собирается service.json. Фактический serializer VpnServiceConfig отсутствует; список явно присвоенных полей не равен полной схеме |
| start(Duration) | Future<ReturnResultError?>: null при успехе верхней обвязки | prepareConfig; firewall ports при сетевом host; FlutterVpnService.start(timeout) → VpnServiceWaitResult; при timeout/err/nonempty stderr выполняется stop; при успехе возможна настройка системного proxy |
| restart(Duration) | Future<ReturnResultError?> | Если getStarted=false, исторически сразу null без рестарта; иначе prepare, FlutterVpnService.restart(timeout), обработка wait type/err/stderr и cleanup. Этот no-op нельзя выдавать за подтверждённый новый запуск |
| reload(Duration) | Future<ReturnResultError?> | В исполняемом историческом коде **return restart(timeout)**. Прямой FlutterVpnService.reload находится только в комментарии и не попал в AST-инвентарь вызовов |
| stop() | Future<void> | Сначала очистка принадлежащего приложению системного proxy; затем FlutterVpnService.stop(); затем uninstall() на Windows. Ошибка uninstall возвращается, но здесь не обрабатывается — это ограничение старого кода, а не гарантия успеха |
| getState() | Future<FlutterVpnServiceState> | Читает FlutterVpnService.currentState. Источник состояния внутри отсутствующего пакета неизвестен |
| getStarted() | Future<bool> | true только при currentState==connected; доступность HTTP API не заменяет это условие |
| install()/uninstall() | Future<ReturnResultError?> | Делегируют installService/uninstallService и преобразуют err.message. Сам смысл installService на Windows ещё не установлен; имя не доказывает SCM registration |

Таймаут исторической обвязки: 20 секунд, +5 при Windows TUN, затем +2 за вычисленные группы серверов свыше 1000. В формуле используется (((count-1000) ~/ 1000)+1)*2: её границы нужно сохранять или изменять явно, а не заменять округлением на глаз.

getTunMode в старом Windows-коде требует setting.tun.enable и сохранённый результат isRunAsAdmin. Это не проверка наличия драйвера, корректности маршрутов или успешного старта TUN.

## Состояния, события и ошибки

Подтверждены имена invalid/disconnected/connecting/connected/reasserting/disconnecting. **Числовые значения и native event codec неизвестны.** Callback вызывающего Dart-кода принимает (FlutterVpnServiceState, Map<String,String> params). В старой обвязке при disconnected очищается системный proxy, затем событие передаётся слушателям.

Текущий HomeScreen отдельно реагирует на connected/disconnected/reasserting/disconnecting, запускает/останавливает наблюдение и публикует Biz callbacks. params Windows лишь логируются; неизвестные ключи нельзя объявлять exitCode/reason без доказательства. Диагностика stderr и ошибки результата отдельны от state: ошибка API или таймаут не означают подтверждённый disconnected.

VpnServiceWaitResult содержит как минимум type и err, а err — message. Подтверждены сравнения с VpnServiceWaitType.done и timeout. Остальные enum values, сериализация и поведение при потере процесса неизвестны. Историческое restart обращается к result.err! при не-done — это предположение вызывающего кода, не доказанная гарантия отсутствующего пакета.

Локальная модель packages/veilor_vpn_state уже учитывает эту неопределённость, но пока не получает реальные native события.

## Схема service.json: что нельзя копировать вслепую

Старая _prepareConfig явно присваивает 16 полей. В наблюдаемом установленном service.json — 25 полей. Общие названия: control_port, base_dir, work_dir, cache_dir, core_path, log_path, err_path, id, version, name, secret, install_refer, sentry_minversion.

В старых присваиваниях есть expired_time/time_connect/time_disconnect; в данном установленном JSON они не встречены. В наблюдаемом JSON есть prepare, wake_lock, auto_connect_at_boot, allowed_sender_packages, include_all_networks, exclude_local_networks, exclude_cellular_services, exclude_apns, exclude_device_communication, enforce_routes, auto_route_use_sub_ranges_by_default, disconnect_after_sleep_seconds.

Это сравнение списка присваиваний с одним сериализованным экземпляром, а не доказательство удаления/добавления обязательных полей. Часть полей явно относится к другим платформам. Их defaults, единицы и Windows-эффект требуют оригинального serializer/consumer. Secret нельзя переносить в argv/логи или заменять тестовым постоянным значением.

## Что реализовывать дальше

1. Native dispatcher найден; при реализации системных helper сначала уточнить схемы аргументов/ошибок, перечисленные выше. Не менять proxy/firewall/автозапуск при исследовании.
2. CLI и HTTP-маршруты частично подтверждены в [SERVICE-PROTOCOL.md](SERVICE-PROTOCOL.md). Проверка singleton и полей конфигурации — в [ISOLATION-AND-CONFIG.md](ISOLATION-AND-CONFIG.md): одинаковое имя exe конфликтует даже при разных каталогах. [Стенд транспорта с имитатором](../../packages/veilor_core_transport_lab/README.md) проходит 22 интеграционных теста, включая проверку PID порта и отказ команды внутри HTTP 200. Схема ответов — в [COMMAND-REPLIES.md](COMMAND-REPLIES.md). Следующий приоритет — связь событий транспорта с политикой состояний.
3. После восстановления wire-контракта — отдельный минимальный пакет vpn_service для Windows: конфиг, подписка/начальное состояние, таймауты, штатный stop и ошибки. Реальное испытание требует отдельной среды или доказанной изоляции; одной копии в другом каталоге недостаточно.
4. Затем адаптировать текущие пропуски обвязки и генератор, подключать UI и проходить функциональный список. Бинарный helper и стандартный Process.kill не объявлять полной заменой службы.

Не созданы фиктивные implementations start/stop/currentState, чтобы снять ошибки компиляции ценой потери функций. Исследовательский шаг завершён контрактом; сборка всего приложения ещё заблокирована отсутствующими частями.

## Проверка и воспроизведение

inventory-service-contract.cjs запускается из корня workspace: он читает ранее сохранённый AST-инвентарь, исторический исходник и снимок DLL, затем пересоздаёт source-and-native-inventory.json. Скрипт не читает service.json или другие пользовательские данные. Снимок схемы/SCM сделан отдельно через read-only PowerShell с выводом только имён/типов.

Синтаксис скрипта проверен node --check, JSON-артефакты успешно разобраны. Декомпиляции имеют evidence IDs в native-evidence.json; исходная DLL не переписывалась. Бинарник karingService.exe не запускался даже с --help: в его строках есть makeProcessSingleton/terminateCurrentProcess, и неизвестный startup не подходит для read-only проверки рядом с работающим VPN.

Исходники lib/bind/windows и корневые pubspec не изменены относительно исходной базы. Ни тесты VPN-трафика, ни команды управления установленным Karing на этом шаге не выполнялись: результат — статическое исследование и безопасное чтение структуры окружения.

# Заполнение VpnServiceConfig перед запуском Windows

22 октября 2026. Offline-разбор сохранённого app.so Karing 1.2.25+2802. Продолжает [восстановление constructor defaults](VPN-CONFIG-RECOVERY.md). Установленное приложение/ядро не запускались и пользовательские настройки не читались.

## Что подтверждено

В VPNService._prepareConfig (0xd874fc, 0x820 байт) после создания VpnServiceConfig перезаписываются **все 25 полей**. Для каждого присваивания зафиксирован адрес. Для вложенных настроек дополнительно сопоставлены JSON-ключи и смещения в serializer соответствующего класса — имена не угаданы по порядку полей.

| Поля | Источник перед сериализацией |
| --- | --- |
| control_port | settings.proxy.control_port |
| base_dir | await PathUtils.profileDir() |
| work_dir | PathUtils.appAssetsDir() |
| cache_dir | await PathUtils.cacheDir() |
| core_path | await PathUtils.serviceCoreConfigFilePath() |
| log_path | await PathUtils.serviceLogFilePath() |
| err_path | await PathUtils.serviceStdErrorFilePath() |
| id | await Did.getDid(); значение не читалось/не вычислялось |
| version | compiled public string 1.2.25.2802 |
| name | compiled public string Karing |
| secret | await ClashApi.getSecret(); значение не читалось/не вычислялось |
| install_refer | ранее ожидаемый результат InstallReferrerUtils.getString() |
| prepare | ранее ожидаемый результат VPNService.getTunMode() |
| wake_lock | settings.ui.wake_lock |
| auto_connect_at_boot | settings.auto_connect_at_boot |
| allowed_sender_packages | settings.allowed_sender_packages; присваивается ссылка |
| include_all_networks, exclude_local_networks, exclude_cellular_services, exclude_apns, exclude_device_communication, enforce_routes, auto_route_use_sub_ranges_by_default | одноимённые значения settings.tun |
| disconnect_after_sleep_seconds | Duration из settings; преобразование в секунды, null становится 0 |
| sentry_minversion | remote_config.sentry_min_version, затем условная политика версии/возраста сборки |

Это таблица происхождения, а не готовый JSON. Методы PathUtils ещё нужно разобрать для точного выбора каталогов/portable mode. Политика sentry_minversion ещё не восстановлена полностью: видны сравнение времени с buildDateTime, вызовы getNextBuildinVersion/compareVersion и повторная запись поля 0xd87be6. Нельзя переносить только первое присваивание, оставлять constructor null или обходить эту ветку.

## Уточнения, важные для реализации

**prepare не постоянный true.** В Windows-коде getTunMode читает settings.tun.enable. При выключенном TUN возвращает false, иначе — сохранённый результат проверки isRunAsAdmin. Цепочка проверки прав подтверждена в VPNService.init: вызов FlutterVpnService.isRunAsAdmin и запись результата в static slot 0x3480, который читает getTunMode. Не выводим из этого, что один prepare сам настраивает TUN или что повышение прав всегда необходимо для остальных режимов.

**control_port не служебный HTTP-порт.** Здесь он приходит из proxy.control_port, заменяя constructor 0. Это согласуется с ранее найденным default настройки 3057. Нельзя использовать этот порт вместо service-http-port или connected-port.

**Текущий AOT подтверждает алгоритм getSecret.** Метод ожидает Did.getDid и вызывает substring(8,24). В машинном коде start=8, optional end передан Smi 0x30, то есть 24. Ранее алгоритм был известен только из исторических исходников; теперь подтверждён для исследованного 1.2.25+2802. Сам Did/getSecret не выполнялся; реальный ID/secret не извлекался. Совпадение с core JSON secret нужно отдельно подтвердить в текущем builder, а не выводить из исторического кода.

**prepareConfig сохраняет ссылки, а запись JSON происходит затем в приложении.** По аргументам вызова и Windows-коду FlutterVpnService.prepareConfig (0xd87d1c) установлены static slots:

| Slot | Назначение |
| --- | --- |
| 0x4248 | объект VpnServiceConfig |
| 0x4258 | путь service exe |
| 0x4250 | путь service config JSON |
| 0x4270 | список исключаемых портов |

После prepareConfig вызываются JsonEncoder.convert и File.writeAsString для service config. Восстановление полного порядка запуска, резервирования портов и готовности этим шагом не закрыто.

## Проверки и артефакты

Проверяющий скрипт заново дизассемблирует выбранные диапазоны из snapshot с закреплённым SHA-256. Зафиксированы 25 присваиваний, 16 соответствий полей настроек/remote config и 46 проверок точных инструкций. Выбранные JSON-ключи также сверены со вторым ранее полученным pool dump. Это статические проверки доказательств, не runtime-тест VPN.

- [vpn-config-preparation.json](vpn-config-preparation.json): машинно читаемые источники и адреса.
- [vpn-config-preparation-x64.txt](vpn-config-preparation-x64.txt): выбранные инструкции с маскированием строк вне allowlist.
- inspect-config-callers.py и verify-config-callers.py: рабочие оригиналы в work/karing-feasibility; копии рядом предназначены для review. Для воспроизведения нужна структура workspace, pinned app.so, два pool dump, ida labels, Capstone/pyelftools и публичные исходники. Полные dumps в Git не добавляются.

Ограничения остаются: другая версия активной базы; полная политика версии; разрешение путей; совпадение core JSON и service JSON; управление портами; подтверждение connected; остановка/очистка. Production serializer и активный Flutter-код не изменены.

Следующий шаг — точное разрешение PathUtils и порядок Windows _start/waitConnect, затем _stop. Реальный core проверять в отдельной Windows VM из-за singleton по basename.

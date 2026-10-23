# Windows: пути и запуск службы из AOT

22 октября 2026. Исследован сохранённый app.so Karing 1.2.25+2802. Код не запускался: заново дизассемблированы выбранные диапазоны, сверены литералы и адреса инструкций. Это продолжение [заполнения конфигурации](VPN-CONFIG-PREPARATION.md), а не испытание VPN.

## Пути

exeDir вычисляется как dirname(Platform.resolvedExecutable), а не текущий рабочий каталог.

profileDir сначала использует кешированный результат. При его отсутствии проверяет существование exeDir/profiles и возможность создать/удалить __test_dir__ внутри него. Успешная проба выбирает portable-каталог. Если каталога нет либо проба не проходит, используется ветка profileDirNonPortable: через FlutterVpnService → MethodChannel → PC вызывается getApplicationSupportDirectory. В этой ветке каталог при необходимости создаётся. Никакая из этих файловых операций на исследуемой установке не выполнялась.

| Назначение | Формула в исследованной версии |
| --- | --- |
| base_dir | выбранный profileDir |
| work_dir / assets | exeDir/data |
| cache_dir | profileDir/cache; вызывается FileUtils.createDir |
| служебный JSON | profileDir/service.json |
| core_path | profileDir/service_core.json |
| log_path | profileDir/service_core.log |
| err_path | profileDir/service_error.log |
| service exe | exeDir/karingService.exe |
| workingDirectory для Process.start | dirname(service exe) |

Конечный абсолютный путь getApplicationSupportDirectory на машине пользователя не читался. Для Veilor нельзя автоматически использовать профиль Karing: требуется отдельное пространство данных. Имя программы и portable/support policy при интеграции должны быть согласованы отдельно.

## Последовательность _start

1. Создаётся список портов и временных ServerSocket; временные сокеты bind на loopbackIPv4 с port=0. Порты сравниваются с _excludePorts. Ищутся два подходящих номера; недостаточный результат приводит к ветке ошибки.
2. Временные сокеты закрываются. Первый выбранный номер затем заново bind на loopback как listener уведомления; он сохраняется в slot 0x4278. Второй номер сохраняется как service HTTP port в slot 0x4280.
3. На listener ставится closure 0xd86b5c; связь проверена по точной записи pool 0x309d0, а не только по близости функций.
4. Формируется список отдельных строк argv: run2, --service-config=<path>, --service-http-port=<port>, --connected-port=<port>. Три опции в этом AOT используют знак равенства. Запускается Process.start; workingDirectory равен каталогу service exe. Объект процесса сохраняется в slot 0x4260.
5. Подключается чтение stdout/stderr. Их runtime-содержимое здесь не исследовалось и не логировалось.
6. Future.any ожидает три исхода: FlutterVpnWait.waitProcessExit, PC.waitConnect и FlutterVpnWait.waitTimeout.
7. После результата listener закрывается и slot 0x4278 очищается. Обрабатываются результат/ошибки; успешная ветка устанавливает started flag 0x4268=true и подписывается на последующее завершение процесса. Полная очистка всех веток и stop этим шагом не проверены.

Release/rebind портов означает окно гонки. Это свойство оригинала, а не гарантия безопасного резервирования. Реализация стенда с lease до момента запуска намеренно отличается; PID ownership check также не является аутентификацией и не устраняет все гонки.

## Что означает сигнал готовности

Closure 0xd86b5c не читает socket payload и не проверяет отправителя: он устанавливает flag 0x4288=true. В обработчике нет вызовов чтения или проверки токена. PC.waitConnect опрашивает flag; пока он false и listener существует, делает Future.delayed с Duration 300000 микросекунд, то есть 300 мс. Если listener отсутствует, возвращает другой исход. При true возвращает VpnServiceWaitType с индексом 3; этот же объект используется успешными ветками. Имена enum из индексов не угадывались.

Сигнал не доказывает сам по себе, что VPN переносит полезный трафик. Нельзя объявлять любой открытый порт подключением. Для приложения ещё нужно сопоставить штатные события состояния, таймер/метрики и завершение процесса с этой последовательностью. В текущем лабораторном reducer ready по-прежнему не превращается автоматически в connected.

## Проверка и сохранённые материалы

verify-paths-startup.py проверяет закреплённый SHA-256 app.so, **58 точных инструкций**, 13 выбранных строк в двух предыдущих pool dumps, связку callback и Duration. Карта содержит 12 записей путей. Повторный запуск должен давать идентичный JSON. Проверки только статические; runtime-тесты приложения этим не заменяются.

- [windows-paths-startup.json](windows-paths-startup.json): контракт и адреса доказательств.
- [windows-paths-startup-x64.txt](windows-paths-startup-x64.txt): выбранные диапазоны с маскированием строк вне allowlist.
- inspect-config-callers.py, verify-paths-startup.py: копии для review. Рабочие оригиналы в work/karing-feasibility; нужны pinned app.so, сохранённые dumps и Python-зависимости. Их нельзя запускать из research без восстановления структуры workspace.

## Следующий шаг

Разобрать PC.stop/_stop/_stopWithoutUpdateState, обработчик выхода процесса и точную цепочку state callbacks. Проверить очистку proxy/сетевых настроек, ошибки и таймауты; затем исправлять лабораторную реализацию по доказанным отличиям. Политика sentry_minversion и полный core JSON остаются открытыми. Версия активной базы 1.2.26+2908 отличается; совместимость пока не установлена.

Установленный karingService.exe не запускался, управляющие команды ему не отправлялись. Первый настоящий запуск — в отдельной Windows VM из-за singleton по basename. Production-код приложения не изменён.

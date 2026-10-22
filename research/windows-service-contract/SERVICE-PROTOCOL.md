# Протокол karingService: статическое восстановление

22 октября 2026. Исследован сохранённый karingService.exe из Karing 1.2.25+2802, SHA-256:

`023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea`

**Установлены служебная CLI-команда, три управляющих флага и три HTTP-маршрута. Бинарник не запускался, управляющие запросы установленному Karing не отправлялись.** Это частично восстановленный контракт, не готовый vpn_service и не подтверждение текущего core 1.14.0.

## Как получены адреса

В pclntab обнаружены 66 932 Go-функции. pcHeader.textStart в файле равен нулю; реальный runtime.text восстановлен через runtime moduledata и проверен по minpc/etext и границам PE: **0x1400013e0**. Начало PE .text (0x140001000) отличается из-за startup-кода. Первичная привязка к началу секции была исправлена; итоговые артефакты содержат адреса только с проверенной базой.

Формат сверялся с [debug/gosym/pclntab.go](https://go.dev/src/debug/gosym/pclntab.go): для новых Go нужен фактический start PC, заголовок может быть нерелокированным. Инструкции разобраны Capstone 5.0.6 из локального work-каталога. Прямые CALL сопоставлены с таблицей функций и проверены на границах инструкций; ссылки на Cobra command objects и function values исследованы отдельно.

Большой Ghidra/REA-разбор, начатый до уточнения базы адресов, остановлен как нерелевантный. Его пустой/неполный вывод не используется как доказательство. Результат этого этапа опирается на pclntab, moduledata, инструкции x64 и статические структуры, а не на успешную декомпиляцию service в Ghidra.

## Запуск: подтверждённая команда run2

Статический Cobra command object имеет Use=`run2` и callback `main.init.func27`. Callback вызывает `main.runService`, который последовательно вызывает:

1. `main.createService` — читает конфигурацию и вызывает `libbox.NewService`, затем `BoxService.Start`.
2. `main.createHttpServer` — создаёт локальный HTTP-интерфейс.
3. Ожидание остановки и `main.destroyAll` — освобождение ресурсов.

Корневая команда имеет Use=`karing` и callback подготовки `main.preRun`. Он вызывает `libbox.SentryInit`, настройку директорий и `main.makeProcessSingleton`. Наличие telemetry/preparation/singleton — причина не считать даже запуск копии с неизвестными параметрами безвредным экспериментом.

Подтверждены регистрации persistent flags:

| Флаг | Тип регистрации | Подтверждённое назначение |
| --- | --- | --- |
| service-config | pflag.StringVarP | Служебная конфигурация, отдельная от обычного config |
| service-http-port | pflag.IntVarP | Значение читается локальным HTTP-server; нулевое отключает его ветку |
| connected-port | pflag.IntVarP | При ненулевом значении выполняется TCP Dial к 127.0.0.1:port, затем соединение закрывается |

Есть также config/config-directory/directory/disable-color, но их наличие не делает обычный `run` эквивалентом `run2`: `run` использует другой путь через Box.New/Start; `run2` — через libbox.NewService.

**Шаблон CLI, НЕ выполнялся. Последующая проверка показала, что копия в другом каталоге с тем же именем может завершить работающий Karing; условия испытания уточнены в [ISOLATION-AND-CONFIG.md](ISOLATION-AND-CONFIG.md).**

```text
karingService.exe run2 --service-config <isolated-service.json>
  --service-http-port <isolated-control-port>
  --connected-port <isolated-parent-listener-port>
```

Это подтверждённая CLI-поверхность бинарника, **не перехваченный argv исходного Dart-пакета**. Попытка read-only чтения CommandLine процесса 21252 через CIM вернула недоступное значение; прав не повышали, значения аргументов не собирали. См. running-command-shape.json.

## Локальный HTTP-интерфейс

main.createHttpServer находится по **0x141604320**, формат listener `127.0.0.1:%d`; port берётся из service-http-port. Используется chi Mux. Регистратор создаёт следующие route groups и внутри каждой регистрирует GET `/`:

| Группа | Handler | Подтверждённое действие |
| --- | --- | --- |
| /reload | main.createHttpServer.func1.1, 0x141608220 | Вызывает main.restartService; формирует JSON с ключами err/extra |
| /stop | main.createHttpServer.func2.1, 0x1416084e0 | Меняет флаг и отправляет событие в канал остановки; формирует JSON с ключом err |
| /clashiApiConnections | main.createHttpServer.func3.1, 0x141608620 | Читает query includeConnections, вызывает BoxService.GetConnections, пишет JSON |

Метод GET подтверждён по interface table chi.Router: слот 0x30 указывает на `(*Mux).Get`; route wrappers вызывают именно этот слот. Названия групп извлечены с точной длиной Go-строк, а не по всему соседнему printable blob.

Для connections значение includeConnections сравнивается с четырёхбайтовой строкой `true`. Поле Content-Type задаётся как application/json. Это отдельный endpoint управления/наблюдения службы, не автоматически тот же контроллер, что Clash API `/connections` с Bearer secret.

Точная нормализация URL со слешем/без слеша, response status, полная JSON-схема err/extra, содержимое ошибки и поведение при параллельных запросах **динамически не проверены**. Позднее статически подтверждены null-поля успешных ответов и строковый err отказа — см. [COMMAND-REPLIES.md](COMMAND-REPLIES.md); extra ошибки остаётся неописанным. В разобранных регистраторах/handlers не обнаружена проверка Authorization, но это не объявление всего стека неаутентифицированным без аудита остальных слоёв.

GET здесь **изменяет состояние**: /stop и /reload не подходят для read-only проверки на работающем VPN. Запросы к ним не делались. Отсутствие /start в этой таблице согласуется со стартом процессом, однако не доказывает отсутствия других интерфейсов во всём ядре.

## Значение для восстановления vpn_service

Теперь есть основание разделить будущий Windows backend на:

- **Запуск своего процесса** через run2 с отдельными путями/портами.
- **Начальное уведомление** через локальный parent listener connected-port. Сам факт Dial не доказывает полную карту FlutterVpnServiceState; это надо связать с Dart callback/наблюдением процесса.
- **Штатный запрос остановки/перезапуска** через service-http-port. Наличие такого механизма найдено, но его успешное применение пока не проверено.
- **Сбор агрегированных показателей** через служебный endpoint либо ранее проверенный Clash API — с отдельными настройками транспорта и доступности.

Это существенно сужает неизвестную часть, но **не позволяет прямо сейчас подставить старую обвязку и собрать приложение**.

Остаются: полная VpnServiceConfig serialization и обязательные поля libbox.NewService, defaults/аргументы Dart prepareConfig, распределение/проверка портов, порядок parent-listener/start, обработка stdout/stderr/exit, singleton-ключ и охват завершаемых процессов, точные состояния/enum и гарантии graceful cleanup proxy/TUN. Установленный SDK/core отличается от текущей исходной базы.

## Артефакты и проверки

- go-service-functions.json — имена/адреса main-функций, hash и происхождение базы runtime.text.
- service-disassembly.json — инструкции, resolved direct calls, RIP references; literalPreview не задаёт длину строки. adjacentLengthLiteral — кандидат, который сверяется с ABI отдельно.
- service-static-bindings.json — Cobra run2 callback и chi.Router GET slot.
- service-call-xrefs.json — межфункциональные CALL, подтверждённые декодированием.
- service-protocol-verified.json — итоговый ограниченный wire-контракт и **29 пройденных статических проверок**. Это не 29 runtime-тестов.
- running-command-shape.json — отсутствие доступа к CommandLine без вывода секретов/значений argv.

Скрипты map-go-service.cjs/disasm-service.py/service-xrefs.py/service-bindings.py/verify-service-protocol.py сохранены рядом. Запускать из корня workspace; они используют snapshot в work/karing-feasibility/targets, промежуточную полную таблицу work/karing-feasibility/go-all-functions.json и локальный Capstone в work/karing-feasibility/python-deps. Полная таблица стандартной библиотеки не добавлялась в repo.

Исходный snapshot не изменён. Бинарник Karing не выполнялся; созданные ранее обычные sing-box стенды на этом шаге не запускались. Активные lib/bind/windows/pubspec остаются без изменений.

**Последующие результаты:** singleton и пути проверены в [ISOLATION-AND-CONFIG.md](ISOLATION-AND-CONFIG.md), частичная схема ответов и владение портом — в [COMMAND-REPLIES.md](COMMAND-REPLIES.md). Стенд транспорта проходит 22 интеграционных теста на имитаторе. Следующий ограниченный шаг — связать события/ошибки транспорта с политикой состояний, сохранив неизвестные состояния явными. Для реального запуска Karing core всё ещё нужна изолированная среда; установленный VPN останавливать не требуется.

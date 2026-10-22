# Передача работы Veilor

Начать с [состояния проекта](STATUS-2026-10-22.md), затем [последнего исследования](../../research/windows-service-contract/TOOLCHAIN-PREP.md).

## Где находится результат

- packages/veilor_core_readonly, veilor_vpn_state, veilor_config, veilor_core_transport_lab: исходники, тесты, команды и ограничения в README.
- research/karing-vpn-service-reference: исторический source с provenance/license.
- research/windows-service-contract: протокол, изоляция, конфигурация/assets, доказательства, скрипты анализа и небольшие receipts.
- docs/veilor/mockups/veilor-windows.html: сохранённая копия Windows-preview, не runtime приложения.
- scripts/veilor/check-environment.ps1: проверка окружения; ранние документы описывают последовательность этапов и могут содержать уже устаревший статус. При конфликте приоритет у STATUS-2026-10-22.md.

## Локальный workspace и исключённые файлы

На исходной машине корень работы C:/Users/Onety/Documents/Codex/2026-10-20/rfr; checkout в outputs/veilor, инструменты/бинарники/полные AOT dumps в work. Эти тяжёлые или потенциально чувствительные файлы не включаются в Git.

Python: C:/Users/Onety/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe. Dart: work/toolchains/flutter/bin/cache/dart-sdk/bin/dart.exe. Их нужно установить отдельно на другой машине. Абсолютные пути в исторических receipts — сведения об исходной машине, не переносимая конфигурация.

Blutter Windows fork: https://github.com/1903247335/blutter-windows commit 6b69d5cf3055480f198c88ae92f000e9dbd704c5. Нужен Dart source tag 3.12.2 commit d684a576a6aa954ae107a03b2b4e1d61c3bebe93. Полный source snapshot hash ace654289f5abc240509fc941453ebc5; verify-dart-source.py пересчитывает его по 15 файлам. Не форсировать hash и не брать prebuild для Dart 3.3.4.

Исследованные файлы (получать законно из соответствующей версии; не брать произвольные аналоги):

- app.so: SHA-256 38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882.
- karingService.exe: SHA-256 023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea.

Рабочие build scripts расположены в work/toolchains/portable-build; сохранённые рядом с исследованием копии привязаны к этой структуре и не должны запускаться из research. Подготовка библиотек: prepare-blutter-libs.py, open-source-libs.json. Microsoft downloader mmozeiko gist 7f3162ec2988e81e56d5c4e22cde9977 revision 49b58850aa5e5c1e65f090d4651ee76607883e11; его digest и payloads в msvc-plan.json, wrapper install-msvc-guarded.py. Условия на другой машине соблюдаются её пользователем; receipt не переносит права лицензии.

Вызовы рабочим локальным Python: verify-dart-source.py → build-pool-only.py → справка собранного анализатора → run-pool-only.py с новым именем output → extract-vpn-methods.py. Требуются закреплённые зависимости и структура work; подробнее в TOOLCHAIN-PREP.md. Анализатор работает только с сохранённым app.so. Полные dumps не публиковать автоматически: они могут содержать строки compiled-приложения. Сгенерированный Frida script не запускался.

## Ближайший технический шаг

vpn-aot-methods.json содержит карту 42 методов, vpn-config-x64.txt — три диапазона config. Сопоставить обращения к PP (R15) и смещения полей с pp.txt в локальном aot-pool-diagnostic/dump. Затем проверить Windows _start/waitConnect/_stop. Не выдавать найденные строки или соседство записей за доказанные defaults. Две записи toJson ещё не интерпретированы; отсутствие fromJson не доказывает отсутствия поведения.

## Ограничения запуска

Не запускать установленный или скопированный karingService.exe, даже --help, рядом с действующим VPN: singleton завершает процессы по basename. Не отправлять установленному сервису reload/stop. Другой каталог не обеспечивает изоляцию. Реальный запуск — в отдельной Windows VM со снимком; лабораторные тесты запускают только свой mock.

Не читать/публиковать реальные профили, ID/secret, argv и credentials. PID ownership check является снимком, не аутентификацией; остаются TOCTOU-гонки. TCP-ready не превращать в connected. Не менять proxy/firewall/маршруты на рабочей машине для проверки гипотез.

# OneXray Windows — подготовка окружения и первая компиляция

Это продолжение AUDIT-2026-10-23.md. Прежние выводы об отсутствующих инструментах частично устранены. Готового приложения с интерфейсом пока нет.

## Подготовлено

- Изолированный Flutter stable 3.47.7 / Dart 3.13.5, framework abaf9c523780a608bd46686fd5e53740a07077f8. Старый Flutter не обновлялся.
- Go 1.27.3 windows/amd64: официальный ZIP, SHA256 проверен по метаданным go.dev (toolchains/go-release.json).
- Rust stable 1.99.1 MSVC: установлен rustup с --no-modify-path, минимальный профиль. RUSTUP_HOME внутри toolchains/rustup.
- LLVM-MinGW 20261020 ucrt-x86_64: официальный релиз mstorsjo/llvm-mingw, SHA256 проверен по digest GitHub release API (toolchains/llvm-mingw-release.json).
- libclang 18.1.1 из PyPI, отдельная директория toolchains/python-deps.
- Flutter Windows engine artifacts Debug/Profile/Release скачаны.
- Flutter pub get завершился с кодом 0; pubspec.lock не обновлялся. Новые версии пакетов специально не устанавливались.
- Flutter gen-l10n завершился с кодом 0.

Сеансовые пути задаёт Enter-BuildEnvironment.ps1: dot-source в PowerShell. Системный PATH не изменялся. APPDATA для дочерних команд направляется в references/flutter-appdata: настройки Flutter отделены от основного профиля. При первом bootstrap ранее использовался стандартный профиль Flutter; SDK Karing не изменялся.

Cargo cache перенесён в **C:/Users/Onety/Documents/Codex/ox-build/cargo**: глубокий исходный путь вызывал ошибку libgit2 `path too long` при checkout BoringSSL. Оба пути перед Move-Item проверены на принадлежность workspace; содержимое кэша сохранено. Enter-BuildEnvironment.ps1 использует новый путь.

## Что скомпилировано

1. Контрольная компиляция desktop_bin через Go с CGO_ENABLED=0: references/core-build/OneXrayCore.exe (45 350 400 байт). Это отдельная предварительная проверка.
2. Затем **штатный** `python build/main.py windows` в libXray, с подготовленными Go/LLVM-MinGW: код завершения 0. Получены:
   - libXray/windows_dll/libXray.dll — 31 833 600 байт;
   - libXray/windows_dll/libXray.h;
   - libXray/bin/xray.exe — 31 508 992 байт;
   - GeoData: geoip.dat/json, geosite.dat/json, timestamp.txt.
3. Runtime-файлы и GeoData скопированы в source/windows/app/ и source/assets/dat/ по инструкции сборки. Native Core сохранён под именем OneXrayCore.exe.
4. dumpbin подтвердил x64 / PE32+ библиотеки и экспорты CGoInvoke/CGoFree. Это проверка структуры, не вызов DLL.

SHA256 штатных артефактов:

| Файл | SHA256 |
| --- | --- |
| source/windows/app/libXray.dll | 7aecb2910736076512c0adeb6f880fcbdf2240817138b07056f47f6e826f3745 |
| source/windows/app/OneXrayCore.exe | 82fc9a0d88b2af3c4c3d1c41c39dcef9a4f224f4b0cdf27fdf914401648afc67 |

Машиночитаемые хэши сохраняются отдельно в build-evidence.json.

Лог штатной компиляции: libxray-build-prepared.log. go.mod/go.sum восстановлены скриптом, git status libXray чистый.

## Проверенные блокеры

**Visual Studio C++ отсутствует.**

- `dart run tool/ffigen.dart` завершился с кодом 255. Build hook cnativeapi не находит vswhere/MSVC, FFI не сгенерированы. Лог ffigen.log.
- `flutter build windows --debug --no-pub` завершился с кодом 1: `Unable to find suitable Visual Studio toolchain`. Лог flutter-build-windows.log.
- Автоматическая попытка запустить установку Visual Studio Build Tools отклонена инструментом выполнения: `rejected: blocked by policy`. Более подробная причина не предоставлена; повторная попытка обхода не выполнялась. Установка не подтверждена.
- Имеющийся portable MSVC не является установленной Visual Studio, которую обнаруживают Flutter, native hooks и штатный Vole builder.

Для продолжения установить с https://visualstudio.microsoft.com/visual-cpp-build-tools/ комплект Desktop development with C++ с MSVC x64/x86, Windows SDK и CMake. После установки проверить `flutter doctor -v` в подготовленном окружении.

Wintun пока не подготовлен: официальный https://www.wintun.net/builds/wintun-0.14.1.zip загружался неуспешно; curl завершился с CRYPT_E_REVOCATION_OFFLINE (35), другие попытки прерваны после отсутствия прогресса. Проверка TLS не отключалась. Частичные ZIP не использовать. Нужно повторить официальную загрузку и извлечь amd64 DLL.

## Vole и BoringSSL

Первый Cargo fetch через libgit2 был прерван после отсутствия прогресса. Повтор через git CLI потребовал долгой загрузки истории BoringSSL. Нужный BoringSSL commit e2a57cfb4d915b4ba820585aef9fdee7bca13fe5 получен отдельным shallow fetch в cache; lockfile и источники не изменялись. После сокращения CARGO_HOME повторная загрузка смогла перейти к crates.io. Итоговый статус загрузки записывается в build-evidence.json и cargo-fetch-short-path.log.

Locked fetch Vole в итоге завершился с кодом 0: зависимости crates.io и закреплённый BoringSSL доступны. Vole DLL/host EXE пока не компилировались с подготовленным Rust. Штатный путь всё ещё требует установленного Visual Studio. Наличие всех артефактов Windows не подтверждено.

## Как продолжить

Из source/ в PowerShell:

```powershell
. ../Enter-BuildEnvironment.ps1
flutter --no-version-check --suppress-analytics doctor -v
```

После подтверждения C++ окружения:

1. Завершить locked fetch и штатную сборку Vole UWP; скопировать DLL, оба host EXE и публичные заголовки по windows.py.
2. Получить официальный Wintun amd64 DLL.
3. Повторить `dart run tool/ffigen.dart` и проверить генерацию; локализации уже подготовлены.
4. Повторить `flutter --no-version-check --suppress-analytics build windows --debug --no-pub`.
5. Проверить запуск с отдельными данными. Перед проверкой подключения учесть, что WindowsCoreProcess умеет останавливать OneXrayCore.exe по имени: рабочий установленный VPN нельзя трогать автоматическим запуском тестового клиента.

В этом этапе собранные Core/DLL не запускались и не загружались в процесс. Реальные профили, текущий VPN и интерфейс приложения не изменялись. Flutter автоматически обновил generated plugin registrants; содержательные изменения нужно отдельно смотреть через git diff перед commit. Commit/push не выполнялись. UI «Лента» ещё не переносился.

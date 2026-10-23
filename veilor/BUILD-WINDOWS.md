# Продолжение сборки Windows

Первый целевой вариант — обычный Debug EXE. Подпись MSIX/Store и публикация продукта пока не входят в этот этап. Актуальный исходный guide: [build_scripts/README.md](../build_scripts/README.md), локальная подготовка: [FIRST_RUN](../readme/FIRST_RUN.md).

## Исходники и инструменты

На новой машине клонировать ветку в короткий путь, например `C:/dev/veilor/OneXray`. Рядом нужны libXray и Vole. Этот checkout — корень Flutter-приложения, папку source внутри него создавать не нужно.

```powershell
git clone --branch veilor/onexray https://github.com/onety11one/veilor.git C:/dev/veilor/OneXray
cd C:/dev/veilor/OneXray
./veilor/scripts/restore-dependencies.ps1
```

Скрипт получает закреплённые ревизии из [manifest](upstream-sources.lock.json), не сбрасывает существующие checkout и не обновляет их молча. Для проверки существующего workspace: `./veilor/scripts/restore-dependencies.ps1 -CheckOnly`.

Нужны Git, Python 3.12+, uv, Flutter/Dart, Go, Rust MSVC, установленный Visual Studio C++/Windows SDK/CMake, совместимый gcc/g++ для CGo, libclang и Perl. Проверенные версии перечислены в manifest. Обновлять зависимости вслепую не нужно.

Cargo cache должен иметь короткий путь, например `C:/dev/ox-cargo`: длинный путь ломал checkout BoringSSL. Сохранять `--locked` и исходный Cargo.lock; не обходить REALITY/TLS зависимости и не отключать проверки сертификатов ради сборки.

## Текущая машина

В исходном workspace SDK уже подготовлены. Из корня этого checkout:

```powershell
. ./veilor/scripts/enter-build-environment.ps1 -CargoHome C:/Users/Onety/Documents/Codex/ox-build/cargo
./veilor/scripts/restore-dependencies.ps1 -CheckOnly
flutter --no-version-check --suppress-analytics doctor -v
```

Helper меняет окружение только текущего процесса, включая отдельный APPDATA для настроек Flutter. Он не устанавливает инструменты. Для обычных SDK, уже настроенных в PATH, helper не обязателен. Go/Rust/Flutter команды выполнять последовательно с другими командами, изменяющими тот же Flutter build state.

Пользователь сообщил, что установка Build Tools идёт. Проверить её окончание и наличие C++ toolchain, не запускать установку повторно. До этого ffigen и Windows build закономерно завершались ошибкой.

## Native bundle

libXray уже собран на текущей машине, результат находится в windows/app и assets/dat. На новой машине повторить штатную команду:

```powershell
python ../libXray/build/main.py windows
New-Item -ItemType Directory -Force windows/app,assets/dat | Out-Null
Copy-Item ../libXray/windows_dll/libXray.dll windows/app/libXray.dll
Copy-Item ../libXray/bin/xray.exe windows/app/OneXrayCore.exe
Copy-Item ../libXray/dat/* assets/dat/ -Force
```

После установки Visual Studio собрать Vole:

```powershell
uv run --project ../Vole/scripts --locked vole-scripts build windows --backend uwp
Copy-Item ../Vole/dist/windows/x64/uwp/vole.dll windows/app/
Copy-Item ../Vole/dist/windows/x64/uwp/vole-windows-vpn-host.exe windows/app/
Copy-Item ../Vole/dist/windows/x64/uwp/vole-windows-session-host.exe windows/app/
Copy-Item ../Vole/dist/windows/x64/uwp/include/vole.h c/include/
Copy-Item ../Vole/dist/windows/x64/uwp/include/vole_windows_uwp.h c/include/
```

Для ARM64 нужен нативный ARM64 host и соответствующие пути/инструменты; приведённые команды — только для x64.

Wintun 0.14.1 получить из официального https://www.wintun.net/builds/wintun-0.14.1.zip. Извлечь `wintun/bin/amd64/wintun.dll` в `windows/app/wintun.dll`. Последняя попытка загрузки не завершилась, поэтому пока отсутствует. Полный runtime по windows/app.cmake: libXray.dll, OneXrayCore.exe, wintun.dll, vole.dll и два Vole host EXE. Наличие одних Core/DLL не означает готовую сборку.

## Генерация и сборка

```powershell
flutter --no-version-check --suppress-analytics pub get
flutter --no-version-check --suppress-analytics gen-l10n
dart run tool/ffigen.dart
flutter --no-version-check --suppress-analytics build windows --debug --no-pub
```

FFI generation запускает native hooks cnativeapi, поэтому сама тоже требует MSVC. Сгенерированные файлы не править вручную. Сохранять код завершения каждой команды, а не последней команды чтения журнала.

После успешной сборки ожидаемый bundle: `build/windows/x64/runner/Debug/`. Пока он не подтверждён. Подготовить изолированные данные до запуска; не запускать рядом с рабочим OneXray VPN автоматически. Сначала подтвердить запуск, затем отдельно подключение и DNS/маршруты. Для EXE/ZIP упаковки позже понадобятся Fastforge/Inno Setup; их установка не подтверждена и для текущей Debug-компиляции не нужна.

## Что считать результатом

Сохранены [машинные результаты](research/build-evidence.json) и [журналы](research/evidence/). Успешны пока сборка libXray/Core, подготовка зависимостей и локализации. Полная компиляция, UI, VPN-трафик и другие платформы ещё не приняты. До подтверждения базовой сборки не переносить макет в runtime.

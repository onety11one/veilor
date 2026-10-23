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

Нужны Git, Python 3.12+, uv, Flutter/Dart, Go, Rust MSVC, установленный Visual Studio C++/Windows SDK/CMake, **C++ ATL** (`Microsoft.VisualStudio.Component.VC.ATL`), NASM, совместимый gcc/g++ для CGo, libclang и Perl. ATL нужен плагину flutter_local_notifications_windows: без него компиляция завершается ошибкой atlbase.h. Проверенные версии перечислены в manifest. Для Windows использованы Visual Studio Build Tools 2026 18.11.1, Windows SDK 10.0.26100.0 и NASM 3.02. Обновлять зависимости вслепую не нужно.

Cargo cache и CARGO_TARGET_DIR должны иметь короткие пути: длинные пути ломали checkout BoringSSL и CMake TryCompile/MSBuild. Helper использует каталог vt рядом с CargoHome и ограничивает параллелизм четырьмя jobs. Сохранять `--locked` и исходный Cargo.lock; не обходить REALITY/TLS зависимости и не отключать проверки сертификатов ради сборки.

## Текущая машина

В исходном workspace SDK уже подготовлены. Из корня этого checkout:

```powershell
. ./veilor/scripts/enter-build-environment.ps1 -CargoHome C:/Users/Onety/Documents/Codex/ox-build/cargo
./veilor/scripts/restore-dependencies.ps1 -CheckOnly
flutter --no-version-check --suppress-analytics doctor -v
```

Helper меняет окружение только текущего процесса, включая отдельный APPDATA для настроек Flutter. Он не устанавливает инструменты. Для обычных SDK, уже настроенных в PATH, helper не обязателен. Go/Rust/Flutter команды выполнять последовательно с другими командами, изменяющими тот же Flutter build state.

Установка Build Tools завершена: flutter doctor подтвердил Windows C++ toolchain. Android SDK пока отсутствует и для Windows не требуется. NASM установлен отдельно в toolchains/nasm; helper добавляет его и поставляемые с Visual Studio CMake/Ninja в PATH.

## Native bundle

libXray уже собран на текущей машине, результат находится в windows/app и assets/dat. На новой машине повторить штатную команду:

```powershell
python ../libXray/build/main.py windows
New-Item -ItemType Directory -Force windows/app,assets/dat | Out-Null
Copy-Item ../libXray/windows_dll/libXray.dll windows/app/libXray.dll
Copy-Item ../libXray/bin/xray.exe windows/app/OneXrayCore.exe
Copy-Item ../libXray/dat/* assets/dat/ -Force
```

Если используется наш переносимый SDK layout, перед повторной сборкой Go/CGo включить MinGW через `. ./veilor/scripts/enter-build-environment.ps1 -CargoHome <короткий путь Cargo> -EnableMinGW`. Для Vole и Flutter снова вызвать helper **без** EnableMinGW: он убирает MinGW из PATH. Смешение MinGW clang/headers и MSVC ломало Rust bindgen. Для уже собранного libXray эта повторная компиляция не нужна.

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

Wintun 0.14.1 получен из официального https://www.wintun.net/builds/wintun-0.14.1.zip. Полная загрузка зависала; скрипт `python veilor/scripts/download-wintun.py` успешно получил тот же архив HTTPS Range-запросами с проверкой ETag, диапазонов и ZIP CRC, без отключения TLS. Он сохраняет amd64 DLL и лицензию в windows/app. SHA256 архива: `07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51`; DLL: `e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce`. Это зафиксированные хэши полученного архива, не независимая сверка с опубликованной upstream checksum.

Полный runtime по windows/app.cmake: libXray.dll, OneXrayCore.exe, wintun.dll, vole.dll и два Vole host EXE. Все эти файлы сейчас подготовлены на исходной машине.

## Генерация и сборка

Для глубокого пути checkout использовать короткий Flutter build-dir. На исходной машине это `C:/Users/Onety/Documents/Codex/ox-build/wd`: стандартный build/ вызвал MSB3501 на длинном пути tlog плагина уведомлений. Настройка сохраняется только в отдельном APPDATA helper-а, не в системном профиле Flutter:

```powershell
$shortBuild = Join-Path (Split-Path $env:CARGO_HOME -Parent) 'wd'
$relativeBuild = [IO.Path]::GetRelativePath((Get-Location).Path, $shortBuild)
flutter --no-version-check --suppress-analytics config --build-dir $relativeBuild
```

```powershell
flutter --no-version-check --suppress-analytics pub get
flutter --no-version-check --suppress-analytics gen-l10n
dart run tool/ffigen.dart
flutter --no-version-check --suppress-analytics build windows --debug --no-pub
```

FFI generation запускает native hooks cnativeapi, поэтому сама тоже требует MSVC. tool/ffigen.dart учитывает LIBCLANG_PATH (директория или полный путь к библиотеке); без переменной остаётся исходный поиск ffigen. Helper задаёт путь к установленному libclang. Сгенерированные файлы не править вручную. Сохранять код завершения каждой команды, а не последней команды чтения журнала.

Bundle находится в `<build-dir>/windows/x64/runner/Debug/`, по умолчанию это build/windows/x64/runner/Debug. На исходной машине используется короткий каталог из примера выше. Подготовить изолированные данные до запуска; не запускать рядом с рабочим OneXray VPN автоматически. Сначала подтвердить запуск, затем отдельно подключение и DNS/маршруты. Для EXE/ZIP упаковки позже понадобятся Fastforge/Inno Setup; их установка не подтверждена и для текущей Debug-компиляции не нужна.

## Что считать результатом

Сохранены [актуальные результаты](research/windows-build-success.json), [отчёт](research/BUILD-WINDOWS-2026-10-23.md) и [журналы](research/evidence/). Полные Windows Debug и Release собраны, 33 Windows mock-теста прошли. Запуск UI, VPN-трафик и другие платформы ещё не проверены. Перед переносом макета выполнить изолированный запуск базовой сборки. Первоначальная неуспешная попытка сохранена отдельно в research/build-evidence.json как историческое свидетельство.


## Отдельная сборка Veilor EXE

Windows runner называется Veilor; CMake устанавливает native Core как
VeilorCore.exe из windows/app/OneXrayCore.exe. Исходный native артефакт вручную
переименовывать не требуется. Данные: %APPDATA%/SigmaGate/Veilor; кэш:
%LOCALAPPDATA%/SigmaGate/Veilor. Установленный OneXray не мигрируется.
После смены имени использовать новый короткий Flutter build-dir
C:/Users/Onety/Documents/Codex/ox-build/wv вместо wd (старый CMake cache хранит имя
OneXray). Release: wv/windows/x64/runner/Release/Veilor.exe.
Это ещё исходный интерфейс OneXray, перенос «Ленты» следующий этап.

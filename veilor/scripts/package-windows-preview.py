"""Package the isolated Windows EXE bundle without user profiles."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--licenses-from', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
bundle = args.bundle.resolve()
for name in ['Veilor.exe', 'VeilorCore.exe', 'libXray.dll', 'wintun.dll', 'vole.dll',
             'vole-windows-vpn-host.exe', 'vole-windows-session-host.exe', 'data/app.so']:
    if not (bundle / name).is_file():
        raise SystemExit(f'Missing runtime: {name}')
for name in ['OneXray.exe', 'OneXrayCore.exe']:
    if (bundle / name).exists():
        raise SystemExit(f'Stale upstream executable in bundle: {name}')
root = 'Veilor-Windows-x64-Preview'
readme = """Veilor Windows x64 — тестовая сборка

1. Распакуйте архив целиком и запустите Veilor.exe.
2. Пройдите начальную настройку, выберите физический Wi-Fi/Ethernet.
3. Импортируйте ваш рабочий сервер вручную. Старые профили не копируются.
4. Отключите VPN в установленном OneXray перед подключением Veilor.
5. Проверьте подключение, внешний IP, сайты, отключение и повторное подключение.

Это исходный интерфейс OneXray; дизайн «Лента» пока не перенесён.
Сборка без цифровой подписи. VPN-подключение автоматически не проверялось.
Данные: %APPDATA%/SigmaGate/Veilor; кэш: %LOCALAPPDATA%/SigmaGate/Veilor.
Свой процесс VeilorCore.exe, адаптер VeilorTun, автозапуск Veilor.lnk.
Одновременно включённые VPN меняют общие системные маршруты и DNS.

Исходная основа: https://github.com/YuanDevTeam/OneXray
Доработки: https://github.com/onety11one/veilor/tree/veilor/onexray
Локальные изменения этого этапа ещё не опубликованы в Git.
Лицензии находятся в licenses/; уведомления об авторах сохранены.
"""
args.output.parent.mkdir(parents=True, exist_ok=True)
if args.output.exists():
    raise SystemExit(f'Output already exists: {args.output}')
with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as z:
    for file in sorted(bundle.rglob('*')):
        if file.is_file():
            z.write(file, root + '/' + file.relative_to(bundle).as_posix())
    with zipfile.ZipFile(args.licenses_from) as previous:
        for name in previous.namelist():
            if '/licenses/' in name and not name.endswith('/'):
                z.writestr(root + '/licenses/' + name.split('/licenses/', 1)[1], previous.read(name))
    z.writestr(root + '/README-RU.txt', readme.encode('utf-8-sig'))
with zipfile.ZipFile(args.output) as z:
    assert z.testzip() is None
    entries = len(z.namelist())
receipt = {'archive': str(args.output.resolve()), 'bytes': args.output.stat().st_size,
           'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
           'entries': entries, 'runtimeLaunched': False, 'vpnTested': False}
print(json.dumps(receipt, ensure_ascii=False, indent=2))

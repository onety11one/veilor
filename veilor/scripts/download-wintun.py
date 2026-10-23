"""Fetch the official archive with bounded HTTPS ranges, retaining TLS checks."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import io
import json
import urllib.request
import zipfile

parser = argparse.ArgumentParser(description='Download official Wintun using verified HTTPS byte ranges.')
parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
app_root = args.app_root.resolve()
archive_root = app_root.parent / 'references/windows-build'
archive_root.mkdir(parents=True, exist_ok=True)
(app_root / 'windows/app').mkdir(parents=True, exist_ok=True)
url = 'https://www.wintun.net/builds/wintun-0.14.1.zip'
with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=15) as response:
    size = int(response.headers['Content-Length'])
    etag = response.headers['ETag']
if not 100_000 < size < 5_000_000:
    raise RuntimeError('Unexpected archive length')

def fetch_range(start):
    end = min(start + 8191, size - 1)
    request = urllib.request.Request(url, headers={
        'Range': f'bytes={start}-{end}', 'If-Range': etag, 'Connection': 'close',
    })
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status != 206 or response.headers.get('ETag') != etag:
            raise RuntimeError('Range response or archive identity changed')
        if response.headers.get('Content-Range') != f'bytes {start}-{end}/{size}':
            raise RuntimeError('Unexpected byte range')
        data = response.read(end - start + 1)
    if len(data) != end - start + 1:
        raise RuntimeError('Truncated range')
    return data

with ThreadPoolExecutor(max_workers=4) as pool:
    archive_data = b''.join(pool.map(fetch_range, range(0, size, 8192)))
with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
    if archive.testzip():
        raise RuntimeError('ZIP integrity check failed')
    dll = archive.read('wintun/bin/amd64/wintun.dll')
    license_text = archive.read('wintun/LICENSE.txt')
(archive_root / 'wintun-0.14.1.zip').write_bytes(archive_data)
(app_root / 'windows/app/wintun.dll').write_bytes(dll)
(app_root / 'windows/app/wintun-LICENSE.txt').write_bytes(license_text)
receipt = {
    'url': url, 'etag': etag, 'archiveBytes': len(archive_data),
    'archiveSha256': hashlib.sha256(archive_data).hexdigest(),
    'dllBytes': len(dll), 'dllSha256': hashlib.sha256(dll).hexdigest(),
    'zipIntegrity': 'passed', 'tlsVerification': 'enabled',
    'note': 'Recorded hashes from official HTTPS archive; no independent upstream hash comparison.',
}
(archive_root / 'wintun-download.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
print(json.dumps(receipt), flush=True)

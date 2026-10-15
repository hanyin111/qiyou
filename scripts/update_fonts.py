"""Download and bundle original HarmonyOS Sans SC fonts without modifying them."""
from pathlib import Path
import hashlib
import io
import json
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip'
OUT = ROOT / 'assets/fonts'
EXPECTED = {
    'HarmonyOS_Sans_SC_Regular.ttf': '297b088424be212207df2ce8b98e335468b782aa6b96832af0b8b773d711e2b1',
    'HarmonyOS_Sans_SC_Medium.ttf': '6ed1553edccddc48eb27ff25d134a4a715cf54211238d4840b3038576cba1944',
    'HarmonyOS_Sans_SC_Bold.ttf': '43a424b85e47fb53a17b3b32026a71801f86f8e022ca6798d186b47d39fa5f01',
    'LICENSE.txt': 'b2ffec0e6269ee41c3b5fc0345ab37600b46d66ebea6c9c58ff37f517bdfa164',
}

if len(sys.argv) > 1:
    archive = zipfile.ZipFile(sys.argv[1])
else:
    with urllib.request.urlopen(SOURCE, timeout=120) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))

files = {name: archive.read('HarmonyOS Sans/HarmonyOS_Sans_SC/' + name)
         for name in EXPECTED}
for name, data in files.items():
    if hashlib.sha256(data).hexdigest() != EXPECTED[name]:
        raise SystemExit(f'Official package changed; review the new font and license before updating: {name}')
OUT.mkdir(parents=True, exist_ok=True)
for name, data in files.items():
    (OUT / name).write_bytes(data)
(OUT / 'sources.json').write_text(json.dumps({
    'family': 'HarmonyOS Sans SC', 'source': SOURCE,
    'modified': False, 'sha256': EXPECTED,
}, indent=2) + '\n', encoding='utf-8')
print('Original HarmonyOS Sans SC fonts and license verified and bundled.')

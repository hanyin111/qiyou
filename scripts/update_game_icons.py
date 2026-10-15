"""Fetch official game icons from the public Miyoushe game catalog."""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CATALOG = 'https://bbs-api.miyoushe.com/apihub/api/getGameList'
GAMES = {2: 'genshin', 6: 'starRail', 8: 'zenless'}
output = ROOT / 'assets' / 'games'
output.mkdir(parents=True, exist_ok=True)
with urlopen(CATALOG, timeout=30) as response:
    catalog = json.load(response)
if catalog.get('retcode') != 0:
    raise RuntimeError('Official catalog is unavailable')
sources = []
for game in catalog['data']['list']:
    if game['id'] not in GAMES:
        continue
    url = game['app_icon']
    host = urlparse(url).hostname or ''
    if urlparse(url).scheme != 'https' or not host.endswith(('.mihoyo.com', '.miyoushe.com')):
        raise RuntimeError('Unexpected official icon host')
    with urlopen(url, timeout=30) as response:
        content = response.read(2_000_001)
    if len(content) > 2_000_000 or not content.startswith(b'\x89PNG\r\n\x1a\n'):
        raise RuntimeError('Unexpected icon content')
    path = output / f'{GAMES[game["id"]]}.png'
    path.write_bytes(content)
    sources.append({'game': game['name'], 'file': str(path.relative_to(ROOT)).replace('\\', '/'),
        'catalog': CATALOG, 'url': url, 'sha256': hashlib.sha256(content).hexdigest(),
        'rights': 'miHoYo and the respective rights holders; excluded from the source-code MIT license'})
    print(f'{game["name"]}: {len(content):,} bytes')
(output / 'sources.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

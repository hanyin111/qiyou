"""Render Qiyou's original geometric launcher mark (requires Pillow)."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
base = Image.new('RGB', (1024, 1024), '#242528')
draw = ImageDraw.Draw(base)
draw.polygon([(512, 228), (794, 390), (512, 552), (230, 390)], fill='#f4f4f5')
draw.line([(230, 502), (512, 664), (794, 502)], fill='#f4f4f5', width=56, joint='curve')
draw.line([(230, 614), (512, 776), (794, 614)], fill='#f4f4f5', width=56, joint='curve')

def save(target, size):
    target.parent.mkdir(parents=True, exist_ok=True)
    base.resize((size, size), Image.Resampling.LANCZOS).save(target)

save(root / 'assets/brand/icon.png', 1024)
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
ios = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((ios / 'Contents.json').read_text())['images']:
    if 'filename' in item:
        save(ios / item['filename'], round(float(item['size'].split('x')[0]) * float(item['scale'][:-1])))
for size in [192, 512]:
    for prefix in ['Icon', 'Icon-maskable']:
        save(root / f'web/icons/{prefix}-{size}.png', size)
save(root / 'web/favicon.png', 32)
manifest = root / 'web/manifest.json'
data = json.loads(manifest.read_text())
data.update(name='栖游', short_name='栖游', description='多游戏体力与日常管理', background_color='#f7f7f8', theme_color='#242528')
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Launcher icons generated for Android, iOS, OHOS and web.')

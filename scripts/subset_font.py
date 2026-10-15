"""Build the bundled OFL font subsets: python scripts/subset_font.py SOURCE.ttf."""
from pathlib import Path
import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
text = ''.join(path.read_text(encoding='utf-8') for path in (root / 'lib').rglob('*.dart'))
text += ''.join(chr(code) for code in range(32, 127)) + '栖游冒险日常体力账号签到年月时分秒星期一二三四五六日，。！？：；、（）【】「」—…·••'
for weight, style in [(400, 'Regular'), (600, 'SemiBold')]:
    font = instantiateVariableFont(TTFont(sys.argv[1]), {'wght': weight}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    names = {1: 'Qiyou Sans', 2: style, 3: f'QiyouSans-{style}-0.1',
             4: f'Qiyou Sans {style}', 6: f'QiyouSans-{style}', 16: 'Qiyou Sans', 17: style}
    for entry in font['name'].names:
        if entry.nameID in names:
            entry.string = names[entry.nameID].encode(entry.getEncoding())
    target = root / 'assets' / 'fonts' / f'QiyouSans-{style}.ttf'
    font.save(target)
    print(f'{target.name}: {target.stat().st_size:,} bytes')

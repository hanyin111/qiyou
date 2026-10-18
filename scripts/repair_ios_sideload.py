"""Repair Qiyou's unsigned IPA names without rebuilding or changing binaries.

Only use on our unsigned build. SideStore reads the raw CFBundleDisplayName
as the Apple portal registration name; Chinese belongs in InfoPlist.strings.
"""
import argparse
import copy
from pathlib import Path
import plistlib
import zipfile


def repair(source: Path, target: Path) -> None:
    if source.resolve() == target.resolve():
        raise ValueError('Write to a new IPA; keep the original for comparison.')
    root = Path(__file__).resolve().parents[1]
    bundles = {
        'Payload/Runner.app/': ('Runner', 'app.qiyou.qiyou'),
        'Payload/Runner.app/PlugIns/QiyouWidget.appex/': (
            'QiyouWidget', 'app.qiyou.qiyou.QiyouWidget'),
    }
    replacements = {}
    with zipfile.ZipFile(source) as original:
        names = original.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive paths.')
        for prefix, (directory, identifier) in bundles.items():
            if any(name.startswith(prefix + '_CodeSignature/') or
                   name == prefix + 'embedded.mobileprovision' for name in names):
                raise ValueError('Expected an unsigned main app and widget.')
            info_path = prefix + 'Info.plist'
            data = original.read(info_path)
            info = plistlib.loads(data)
            if info['CFBundleIdentifier'] != identifier:
                raise ValueError('Expected the original Qiyou bundle identifiers.')
            defaults = plistlib.loads((root / 'ios' / directory / 'Info.plist').read_bytes())
            for key in ('CFBundleDisplayName', 'CFBundleName', 'CFBundleDevelopmentRegion'):
                value = defaults.get(key)
                if value and '$(' not in value:
                    info[key] = value
            for key in ('CFBundleDisplayName', 'CFBundleName'):
                if not info[key].isascii():
                    raise ValueError(f'{identifier}: {key} must be ASCII for sideloading.')
            fmt = plistlib.FMT_BINARY if data.startswith(b'bplist') else plistlib.FMT_XML
            replacements[info_path] = plistlib.dumps(info, fmt=fmt, sort_keys=False)
            for language in ('en', 'zh-Hans'):
                relative = f'{language}.lproj/InfoPlist.strings'
                replacements[prefix + relative] = (root / 'ios' / directory / relative).read_bytes()

        target.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(target, 'x') as output:
            for entry in original.infolist():
                output.writestr(copy.copy(entry), replacements.get(entry.filename, original.read(entry)))
            for name in sorted(set(replacements) - set(names)):
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(entry, replacements[name])

        with zipfile.ZipFile(target) as output:
            if output.testzip() is not None:
                raise ValueError('Archive integrity check failed.')
            for entry in original.infolist():
                if entry.filename not in replacements:
                    if original.read(entry) != output.read(entry.filename):
                        raise ValueError(f'Unexpected change: {entry.filename}')
                if output.getinfo(entry.filename).external_attr != entry.external_attr:
                    raise ValueError(f'Changed Unix attributes: {entry.filename}')
            for name, expected in replacements.items():
                if output.read(name) != expected:
                    raise ValueError(f'Incorrect metadata: {name}')
    print(f'Created {target}: names/localizations repaired; binaries unchanged; still unsigned.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    arguments = parser.parse_args()
    repair(arguments.source, arguments.target)

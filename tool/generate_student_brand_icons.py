#!/usr/bin/env python3
"""Derive platform icon sizes from the Tasko master, using macOS sips.
The script preserves the source artwork and exports platform-specific sizes.
"""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / 'artifacts/brand-source/tasko-logo-master.png'
if not source.is_file():
    source = root / 'assets/student/tasko-logo.png'

def resize(destination, size):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['sips', '-z', str(size), str(size), str(source),
                    '--out', str(destination)], check=True, stdout=subprocess.DEVNULL)

for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    directory = root / f'android/app/src/main/res/mipmap-{density}'
    resize(directory / 'ic_launcher.png', round(48 * scale))
    resize(directory / 'ic_launcher_foreground.png', round(108 * scale))

adaptive = root / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'
adaptive.parent.mkdir(parents=True, exist_ok=True)
adaptive.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/tasko_icon_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
(root / 'android/app/src/main/res/values/tasko_brand.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="tasko_icon_background">#561C24</color></resources>
''')

icons = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for image in json.loads((icons / 'Contents.json').read_text())['images']:
    if image.get('filename'):
        size = round(float(image['size'].split('x')[0]) * float(image['scale'].rstrip('x')))
        resize(icons / image['filename'], size)
for size in [192, 512]:
    resize(root / f'web/icons/Icon-{size}.png', size)
    resize(root / f'web/icons/Icon-maskable-{size}.png', size)
resize(root / 'web/favicon.png', 64)
print('Generated Android, iOS and web icon sizes.')

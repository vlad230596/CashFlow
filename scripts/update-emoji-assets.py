"""Regenerate the bundled emoji catalogue from pinned upstream releases."""

import io
import json
import zipfile
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
EMOJIBASE = '17.0.0'
TWEMOJI = '17.0.3'


def download(url):
    with urlopen(url, timeout=120) as response:
        return response.read()


def main():
    base = f'https://cdn.jsdelivr.net/npm/emojibase-data@{EMOJIBASE}'
    russian = json.loads(download(f'{base}/ru/data.json'))
    english = json.loads(download(f'{base}/en/data.json'))
    archive = zipfile.ZipFile(io.BytesIO(download(
        f'https://codeload.github.com/jdecked/twemoji/zip/refs/tags/v{TWEMOJI}'
    )))
    prefix = f'twemoji-{TWEMOJI}/'
    files = set(archive.namelist())
    destination = ROOT / 'app/assets/emoji'
    destination.mkdir(parents=True, exist_ok=True)
    svg_dir = destination / 'svg'
    svg_dir.mkdir(exist_ok=True)

    def flatten(items):
        return [variant for item in items for variant in [item, *item.get('skins', [])]
                if 'group' in variant and 'order' in variant]

    en_by_hex = {item['hexcode']: item for item in flatten(english)}
    catalogue = []
    for item in sorted(flatten(russian), key=lambda item: item['order']):
        emoji = item['emoji']
        code = '-'.join(f'{ord(char):x}' for char in emoji)
        # Twemoji omits presentation selectors except inside ZWJ sequences.
        if '\u200d' not in emoji:
            code = '-'.join(part for part in code.split('-') if part != 'fe0f')
        source = f'{prefix}assets/svg/{code}.svg'
        if source not in files:
            code = '-'.join(part for part in code.split('-') if part != 'fe0f')
            source = f'{prefix}assets/svg/{code}.svg'
        if source not in files:
            raise ValueError(f'Missing Twemoji asset: {item["hexcode"]}')
        (svg_dir / f'{code}.svg').write_bytes(archive.read(source))
        en = en_by_hex[item['hexcode']]
        catalogue.append({
            'emoji': emoji,
            'label': item['label'],
            'group': item['group'],
            'asset': code,
            'keywords': list(dict.fromkeys([
                *item.get('tags', []), en['label'], *en.get('tags', []),
            ])),
        })
    if len({entry['emoji'] for entry in catalogue}) != len(catalogue):
        raise ValueError('Duplicate emoji')
    if any(len('emoji:' + entry['emoji']) > 24 for entry in catalogue):
        raise ValueError('An emoji exceeds the existing database column')
    (destination / 'catalog.json').write_text(
        json.dumps(catalogue, ensure_ascii=False, separators=(',', ':')) + '\n',
        encoding='utf-8',
    )
    (ROOT / 'backend/data/user_emoji_keys.json').write_text(
        json.dumps(['emoji:' + entry['emoji'] for entry in catalogue], ensure_ascii=False)
        + '\n', encoding='utf-8',
    )
    (destination / 'TWEMOJI-LICENSE.txt').write_bytes(archive.read(prefix + 'LICENSE-GRAPHICS'))
    (destination / 'EMOJIBASE-LICENSE.txt').write_bytes(download(f'{base}/LICENSE'))
    print(f'Bundled {len(catalogue)} emoji from Twemoji {TWEMOJI} / Emojibase {EMOJIBASE}.')


if __name__ == '__main__':
    main()

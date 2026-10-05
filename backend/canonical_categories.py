"""Unified (canonical) cashback categories and MCC-based linking of bank categories.

Bank categories keep their original names. A canonical category is the shared vocabulary used
for search and comparison; each one has a core set of MCC codes. A bank category is linked to
every canonical category whose core it substantially covers, so a broad bank category such as
"Cafes and restaurants" with fast food inside is found under both canonical entries.
"""

import json
from pathlib import Path

import sqlalchemy as sa

BUNDLED_CANONICAL_CATEGORIES = Path(__file__).with_name('data') / 'canonical_categories.json'
LINK_RELATIONS = ('exact', 'broader', 'narrower')
LINK_SOURCES = ('auto', 'manual')

# A bank category is linked to a canonical category when it covers at least half of the core
# or when at least half of its own codes belong to that core. Additional (non-primary) links
# must also be a real part of the bank category: a fifth of its codes, or most of a multi-code
# core. This keeps a supermarket list that happens to contain 5921 from being sold as "alcohol".
MIN_COVERAGE = 0.5
MIN_SHARE = 0.5
MIN_SECONDARY_SHARE = 0.2


def load_bundled_canonical_categories(path=BUNDLED_CANONICAL_CATEGORIES):
    document = json.loads(Path(path).read_text(encoding='utf-8'))
    if document.get('schemaVersion') != 1 or document.get('kind') != 'canonical_categories':
        raise ValueError('Unsupported canonical categories document')
    groups = {group['key']: group['title'] for group in document['groups']}
    group_order = {key: index for index, key in enumerate(groups)}
    rows = []
    seen = set()
    for index, item in enumerate(document['categories']):
        key = item['key']
        if key in seen:
            raise ValueError(f'Duplicate canonical category: {key}')
        if item['group'] not in groups:
            raise ValueError(f'Unknown group for canonical category {key}')
        seen.add(key)
        rows.append({
            'key': key,
            'group_key': item['group'],
            'group_title': groups[item['group']],
            'title': item['title'],
            'aliases': list(item.get('aliases') or []),
            'core_mcc': sorted(set(item.get('coreMcc') or [])),
            'default_priority': int(item['defaultPriority']),
            'sort_order': group_order[item['group']] * 100 + index,
        })
    return rows


def compute_canonical_links(codes, categories):
    """Return [{key, relation, coverage}] for a bank category's included MCC codes.

    ``categories`` is an iterable of mappings with ``key`` and ``core_mcc``.
    """
    codes = set(codes)
    if not codes:
        return []
    cores = {item['key']: set(item['core_mcc']) for item in categories if item['core_mcc']}
    candidates = []
    for key, core in cores.items():
        overlap = len(codes & core)
        if not overlap:
            continue
        coverage = overlap / len(core)
        share = overlap / len(codes)
        if coverage >= MIN_COVERAGE or share >= MIN_SHARE:
            candidates.append((key, coverage, share))
    if not candidates:
        return []
    candidates.sort(key=lambda item: (-item[2], -item[1], item[0]))

    def is_substantial(key, coverage, share):
        return share >= MIN_SECONDARY_SHARE or (coverage > MIN_COVERAGE and len(cores[key]) >= 2)

    selected = [
        (key, coverage)
        for index, (key, coverage, share) in enumerate(candidates)
        if index == 0 or is_substantial(key, coverage, share)
    ]
    links = []
    for key, coverage in selected:
        if len(selected) > 1:
            relation = 'broader'
        elif coverage == 1:
            relation = 'exact'
        else:
            relation = 'narrower'
        links.append({'key': key, 'relation': relation, 'coverage': round(coverage, 4)})
    return sorted(links, key=lambda item: item['key'])


def upsert_canonical_categories(connection, category_table, core_table, rows):
    """Insert or refresh canonical categories and replace their core MCC sets."""
    existing = {
        row.key
        for row in connection.execute(sa.select(category_table.c.key))
    }
    for row in rows:
        values = {key: row[key] for key in (
            'group_key', 'group_title', 'title', 'aliases', 'default_priority', 'sort_order',
        )}
        if row['key'] in existing:
            connection.execute(
                category_table.update()
                .where(category_table.c.key == row['key'])
                .values(**values)
            )
        else:
            connection.execute(category_table.insert().values(key=row['key'], **values))
        connection.execute(core_table.delete().where(core_table.c.canonical_key == row['key']))
        if row['core_mcc']:
            connection.execute(core_table.insert(), [
                {'canonical_key': row['key'], 'mcc_code': code} for code in row['core_mcc']
            ])

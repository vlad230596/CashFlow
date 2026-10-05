"""Unified (canonical) cashback categories and MCC-based linking of bank categories.

Bank categories keep their original names. A canonical category is the shared vocabulary used
for search and comparison; each one has a core set of MCC codes. A bank category is linked to
every canonical category whose core it substantially covers, so a broad bank category such as
"Cafes and restaurants" with fast food inside is found under both canonical entries.
"""

import json
import re
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


TRAVEL = ('airline', 'hotels', 'rail', 'travel_agency')

# Fallback for personal offers whose bank has no published rules with the same category name.
# Every matching rule contributes its keys, so "Фастфуд, кафе и рестораны" gets both entries.
# Brand offers ("Пятёрочка") and "all purchases" intentionally match nothing.
NO_CANONICAL = re.compile(r'осаго|каско|страхов|все покупки|^на вс[её]|за вс[её] покупки')
# A generic travel word adds the whole travel set only when no specific travel kind matched,
# so "Авиа в Тревел" stays an airline offer.
GENERIC_TRAVEL = re.compile(r'путешеств|travel|тревел')
NAME_RULES = [
    (r'супермаркет|продукт|гипермаркет|groceries', ('groceries',)),
    (r'кафе|ресторан|\bбар(ы)?\b', ('restaurants',)),
    (r'фастфуд|фаст фуд|быстр\w* питан', ('fastfood',)),
    (r'алкогол', ('alcohol',)),
    (r'аптек|лекарств', ('pharmacy',)),
    (r'медицин|(?<!вет )(?<!вет)клиник|стоматолог|анализ', ('medical',)),
    (r'^здоровье$', ('pharmacy', 'medical')),
    (r'космет|парфюм', ('cosmetics',)),
    (r'салон|\bспа\b|\bspa\b|парикмахер', ('beauty_salons',)),
    (r'^красота$|^красота и уход$|бьюти', ('beauty_salons', 'cosmetics')),
    (r'одежд|обув|fashion', ('clothing',)),
    (r'электрон|техник|гаджет', ('electronics',)),
    (r'маркетплейс', ('marketplaces',)),
    (r'ювелир|украшен|бижутер', ('jewelry',)),
    (r'^цвет|\bцветы\b|флорист', ('flowers',)),
    (r'хобби|подар|сувенир|творчеств|музык', ('hobby',)),
    (r'duty free|дьюти', ('duty_free',)),
    (r'дом и ремонт|товары для дома|ремонт|мебел|стройматериал', ('home',)),
    (r'детск|для детей|^дети$|игруш|малыш', ('kids',)),
    (r'животн|питом|зоо|ветеринар|ветклиник', ('pets',)),
    (r'химчист|прачечн|бытов\w* услуг', ('household_services',)),
    (r'жкх|жку|коммунал', ('utilities',)),
    (r'связ|интернет|мобильн|телевиден', ('telecom',)),
    (r'азс|топлив|заправ', ('fuel',)),
    (r'автоуслуг|автосервис|автомойк|шиномонтаж', ('auto_services',)),
    (r'автозапчаст|запчаст', ('auto_parts',)),
    (r'^авто$', ('auto_services', 'auto_parts', 'toll_roads')),
    (r'платн\w* дорог|парковк', ('toll_roads',)),
    (r'транспорт|метро|автобус', ('transport',)),
    (r'такси|яндекс go|yandex go|uber', ('taxi',)),
    (r'каршер|аренд\w* авто|прокат авто', ('car_rental',)),
    (r'самокат|кикшер', ('scooters',)),
    (r'авиа', ('airline',)),
    (r'отел|гостиниц', ('hotels',)),
    (r'\bж ?д\b|железнодорож|поезд', ('rail',)),
    (r'\bтур(ы|агент|ист)', ('travel_agency',)),
    (r'^(?!.*онлайн).*(кино|театр)', ('cinema_theater',)),
    (r'онлайн кинотеатр', ('online_cinema',)),
    (r'цифров', ('digital',)),
    (r'развлеч|впечатлен', ('entertainment',)),
    (r'активн\w* отдых', ('fitness', 'entertainment')),
    (r'искусств|музе|выстав', ('culture',)),
    (r'книг|канцтовар|канцеляр', ('books',)),
    (r'спорттовар|спортивн\w* товар', ('sports_goods',)),
    (r'фитнес|тренировк|спортклуб|спортзал', ('fitness',)),
    (r'^спорт$|спорт и фитнес', ('sports_goods', 'fitness')),
    (r'образован|обучен|курс|школ|университет|репетитор', ('education',)),
    (r'налог|штраф', ('fines_taxes',)),
]
_COMPILED_NAME_RULES = [(re.compile(pattern), keys) for pattern, keys in NAME_RULES]


def normalize_category_name(value):
    text = str(value or '').lower().replace('ё', 'е')
    return re.sub(r'[^a-zа-я0-9]+', ' ', text).strip()


def resolve_canonical_by_name(name):
    """Return canonical keys suggested by an offer name, or an empty list."""
    normalized = normalize_category_name(name)
    if NO_CANONICAL.search(normalized):
        return []
    keys = []
    for pattern, rule_keys in _COMPILED_NAME_RULES:
        if pattern.search(normalized):
            keys.extend(key for key in rule_keys if key not in keys)
    if GENERIC_TRAVEL.search(normalized) and not set(keys) & set(TRAVEL):
        keys.extend(TRAVEL)
    return keys


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

"""Build importable bank MCC rule snapshots from the manual transcription of bank documents.

Input:  data/bank_mcc_2026-10.json   (transcribed categories, exclusions and notes per bank)
Output: data/bank_mcc_rules/2026-10/<bank>.json  (one bank_mcc_rules_snapshot v1 per bank)

Run from backend/:  uv run python scripts/build_bank_mcc_snapshots.py
Then import:        uv run flask --app main import-bank-mcc-rules
"""

import csv
import json
import re
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
SOURCE = BACKEND / 'data' / 'bank_mcc_2026-10.json'
TARGET = BACKEND / 'data' / 'bank_mcc_rules' / '2026-10'
CATALOG = BACKEND / 'data' / 'mcc_codes.csv'
COLLECTED_AT = '2026-10-05T00:00:00+03:00'

PROGRAMS = {
    'ozon': {'programKey': 'ozon-cashback', 'source': 'pdf',
             'validity': {'from': '2026-10-01', 'confidence': 'unknown'}},
    'alfa': {'programKey': 'alfa-vygodno', 'source': 'pdf',
             'validity': {'from': '2026-10-01', 'to': '2026-11-01', 'confidence': 'exact'}},
    'vtb': {'programKey': 'vtb-multibonus', 'source': 'pdf',
            'validity': {'from': '2026-09-01', 'confidence': 'inferred'}},
    'tbank': {'programKey': 'tbank-black', 'source': 'pdf',
              'validity': {'from': '2026-04-02', 'confidence': 'inferred'}},
    'yandex': {'programKey': 'yandex-pay-points', 'source': 'public_page',
               'url': 'https://yandex.ru/legal/card_and_pay_points/ru/',
               'validity': {'from': '2026-09-29', 'confidence': 'exact'}},
    'sber': {'programKey': 'sberspasibo', 'source': 'pdf',
             'validity': {'from': '2026-10-01', 'confidence': 'unknown'}},
}

ALL_PURCHASES = {'Все остальные покупки', 'Все покупки', 'На всё', 'На все покупки'}
PAYMENT_METHODS = {
    'Яндекс Сплит', 'Оплата по СБП со Счёта в Яндексе',
    'Оплата через SberPay QR со Счёта в Яндексе', 'Оплата токеном Яндекс Пэй по NFC (Android)',
    'На всё за оплату улыбкой', 'На всё по SberPay NFC', 'На всё за оплату Вжух',
}
OTHER = {'Подписка: Авиабилеты и Отели (15%)', 'Бонусы за остаток (Приложение 3)'}
TRAVEL = ['airline', 'hotels', 'rail', 'travel_agency']
# Categories without MCC lists (or defined by a bank's own service) are linked by hand.
BANK_SERVICES = {
    ('alfa', 'Интернет'): ['telecom'],
    ('alfa', 'Коммунальные услуги'): ['utilities'],
    ('alfa', 'Налоги'): ['fines_taxes'],
    ('alfa', 'Штрафы ГАИ'): ['fines_taxes'],
    ('alfa', 'Транспортные карты'): ['transport'],
    ('alfa', 'Альфа-Афиша'): ['cinema_theater', 'entertainment'],
    ('alfa', 'Альфа-Заправки'): ['fuel'],
    ('alfa', 'Альфа-Тревел'): TRAVEL,
    ('vtb', 'ВТБ Шопинг'): ['marketplaces'],
    ('vtb', 'ВТБ Путешествия'): ['airline'],
    ('vtb', 'ВТБ Афиша'): ['cinema_theater', 'entertainment'],
    ('vtb', 'Оплата ЖКУ в ВТБ-Онлайн'): ['utilities'],
    ('yandex', 'Яндекс Маркет'): ['marketplaces'],
    ('sber', 'ЖКХ в Сбербанк Онлайн'): ['utilities'],
    ('sber', 'Транспортные карты'): ['transport'],
    ('sber', 'Маркетплейс ОСАГО'): [],
    ('sber', 'СпасибоТревел'): TRAVEL,
    ('sber', 'Авиа на СпасибоТревел'): ['airline'],
    ('sber', 'ЖД на СпасибоТревел'): ['rail'],
    ('sber', 'Отели на СпасибоТревел'): ['hotels'],
    ('sber', 'Туры на СпасибоТревел'): ['travel_agency'],
}
MANUAL_MCC_CATEGORIES = {
    ('tbank', 'Самокаты'): ['scooters'],
    ('tbank', 'Маркетплейсы'): ['marketplaces'],
    ('yandex', 'Онлайн-кинотеатры'): ['online_cinema'],
}
PARTNERS = {
    'Дикси Доставка': ['groceries'], 'Азбука вкуса': ['groceries'],
    'Перекрёсток Доставка': ['groceries'], 'Пятёрочка': ['groceries'],
    'АШАН онлайн': ['groceries'], 'Tasty Coffee': ['groceries'], 'Реми/РемиСити': ['groceries'],
    'Детский мир': ['kids'], 'Здравсити, Ригла': ['pharmacy'], 'Еаптека': ['pharmacy'],
    'Подружка': ['cosmetics'], 'РИВ ГОШ': ['cosmetics'], 'KARI': ['clothing'],
    'Твой Дом': ['home'], 'Аскона': ['home'], 'Рестораны в городе': ['restaurants'],
    'Авиа в Тревел': ['airline'], 'Отели в Тревел': ['hotels'], 'Ж/Д в Тревел': ['rail'],
}
EXCLUSION_KINDS = {
    'always': 'always',
    'conditional': 'conditional',
    'unless_category': 'unless_category',
    'insurance_conflict': 'conditional',
}
TRANSLIT = dict(zip(
    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
    ['a', 'b', 'v', 'g', 'd', 'e', 'e', 'zh', 'z', 'i', 'y', 'k', 'l', 'm', 'n', 'o', 'p',
     'r', 's', 't', 'u', 'f', 'kh', 'ts', 'ch', 'sh', 'shch', '', 'y', '', 'e', 'yu', 'ya'],
))


def slug(value):
    text = ''.join(TRANSLIT.get(char, char) for char in value.lower())
    return re.sub(r'[^a-z0-9]+', '-', text).strip('-')


def load_catalog():
    with CATALOG.open(encoding='utf-8') as handle:
        return {row['MCC'] for row in csv.DictReader(handle)}


def expand(items, catalog):
    """Expand 'AAAA-BBBB' ranges to catalogue codes; explicit single codes are kept as is."""
    codes = []
    for item in items:
        if '-' in item:
            start, end = (int(part) for part in item.split('-'))
            codes.extend(code for code in (f'{i:04d}' for i in range(start, end + 1))
                         if code in catalog)
        else:
            codes.append(item)
    return sorted(set(codes))


def note(kind, text, value=None):
    return {'kind': kind, 'operator': None, 'value': value, 'originalText': text}


def ecosystem(entries):
    """'3991 (Мегамаркет)' → code plus a condition naming the services it applies to."""
    codes, conditions = [], []
    names = {'3990': 'Яндекс', '3991': 'Сбер', '3992': 'Газпром'}
    for entry in entries:
        match = re.match(r'(\d{4})\s*(?:\((.*)\))?', entry)
        code, services = match.group(1), match.group(2)
        codes.append(code)
        text = f'MCC {code} учитывается только по сервисам экосистемы {names.get(code, "")}'
        conditions.append(note('ecosystem_service', text + (f': {services}' if services else '')))
    return codes, conditions


def category_document(bank_key, item, catalog, kind='mcc'):
    name = item['name']
    codes = expand(item.get('mcc', []), catalog)
    conditions = []
    eco_codes, eco_conditions = ecosystem(item.get('ecosystem', []))
    codes = sorted(set(codes) | set(eco_codes))
    conditions.extend(eco_conditions)
    if item.get('note'):
        conditions.append(note('note', item['note']))
    document = {
        'sourceKey': slug(name),
        'name': name,
        'description': item.get('note'),
        'includedMcc': codes,
        'excludedMcc': [],
        'conditions': conditions,
        'completeness': 'exact_mcc' if codes else 'text_only',
    }
    if kind != 'mcc':
        document['kind'] = kind
    manual = BANK_SERVICES.get((bank_key, name)) or MANUAL_MCC_CATEGORIES.get((bank_key, name))
    if manual is not None:
        document['canonicalKeys'] = manual
    return document


def special_kind(bank_key, name):
    if name in ALL_PURCHASES:
        return 'all_purchases'
    if name in PAYMENT_METHODS:
        return 'payment_method'
    if name in OTHER:
        return 'other'
    if (bank_key, name) in BANK_SERVICES:
        return 'bank_service'
    return 'other'


def build_snapshot(bank, catalog):
    key = bank['key']
    program = PROGRAMS[key]
    categories = []
    for item in bank['categories']:
        kind = 'bank_service' if (key, item['name']) in BANK_SERVICES else 'mcc'
        categories.append(category_document(key, item, catalog, kind))
    for item in bank.get('special_categories', []):
        categories.append(category_document(key, item, catalog, special_kind(key, item['name'])))
    for item in bank.get('partner_categories', []):
        document = category_document(key, item, catalog, 'partner')
        document['sourceKey'] = 'partner-' + document['sourceKey']
        if item['name'] in PARTNERS:
            document['canonicalKeys'] = PARTNERS[item['name']]
        categories.append(document)
    for name, merchants in (bank.get('merchant_lists') or {}).items():
        target = next(item for item in categories if item['name'] == name)
        target['conditions'].append(note(
            'merchant_names',
            'Категория определяется по названию продавца (Merchant name)',
            '; '.join(merchants),
        ))

    exclusions = [
        {
            'mcc': expand(group['mcc'], catalog),
            'kind': EXCLUSION_KINDS[group['kind']],
            'reason': group['reason'],
        }
        for group in bank['exclusions']
    ]
    conditions = [note('program_rule', rule) for rule in bank['rules']]
    conditions += [note('exclusion_text', text) for text in bank.get('text_exclusions', [])]
    conditions.append(note('source_document', f'Источник: {bank["source_file"]}'))
    conditions.append(note('validity_note', f'Срок действия: {bank["valid_hint"]}'))
    source = {
        'type': program['source'],
        'url': program.get('url'),
        'parserName': 'manual-transcription',
        'parserVersion': '2026-10-05',
    }
    return {
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': key,
        'programKey': program['programKey'],
        'programName': bank['program'],
        'productScope': None,
        'collectedAt': COLLECTED_AT,
        'source': source,
        'validity': program['validity'],
        'completeness': 'exact_mcc',
        'globalExcludedMcc': [],
        'exclusions': exclusions,
        'conditions': conditions,
        'categories': categories,
    }


def main():
    catalog = load_catalog()
    source = json.loads(SOURCE.read_text(encoding='utf-8'))
    snapshots = [build_snapshot(bank, catalog) for bank in source['banks']]
    for snapshot in snapshots:
        keys = [item['sourceKey'] for item in snapshot['categories']]
        duplicates = {key for key in keys if keys.count(key) > 1}
        if duplicates:
            raise SystemExit(f'{snapshot["bankId"]}: duplicate category keys {sorted(duplicates)}')
    TARGET.mkdir(parents=True, exist_ok=True)
    for snapshot in snapshots:
        path = TARGET / f'{snapshot["bankId"]}.json'
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
        print(f'{snapshot["bankId"]}: {len(snapshot["categories"])} categories, '
              f'{sum(len(group["mcc"]) for group in snapshot["exclusions"])} excluded MCC entries')


if __name__ == '__main__':
    main()

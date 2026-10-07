from datetime import datetime, timedelta

import pytest

from canonical_categories import (
    compute_canonical_links,
    load_bundled_canonical_categories,
    resolve_canonical_by_name,
    upsert_canonical_categories,
)
from main import (
    BANK_IMPORT_NAMES,
    AuthSession,
    AuthUser,
    Bank,
    BankCard,
    BankRuleRevision,
    CanonicalCategory,
    CanonicalCategoryMcc,
    CardUser,
    CashbackCategory,
    MccCode,
    _token_digest,
    _utc_now,
    app,
    db,
)
from mcc_catalog import load_bundled_mcc_catalog, upsert_mcc_catalog

CANONICAL = load_bundled_canonical_categories()


@pytest.fixture()
def client_and_headers():
    app.config.update(TESTING=True)
    with app.app_context():
        db.create_all()
        connection = db.session.connection()
        upsert_mcc_catalog(connection, MccCode.__table__, load_bundled_mcc_catalog())
        upsert_canonical_categories(
            connection,
            CanonicalCategory.__table__,
            CanonicalCategoryMcc.__table__,
            CANONICAL,
        )
        now = _utc_now()
        banks = {key: Bank(name=name, icon_key=key) for key, name in BANK_IMPORT_NAMES.items()}
        user = AuthUser(
            username='canonical-admin',
            password_hash='unused-in-this-test',
            role='admin',
            auth_enabled=True,
            created_at=now,
            updated_at=now,
        )
        db.session.add_all([*banks.values(), user])
        db.session.flush()
        token = 'synthetic-canonical-test-token'
        db.session.add(AuthSession(
            token_digest=_token_digest(token),
            user_id=user.id,
            created_at=now,
            expires_at=now + timedelta(hours=1),
        ))
        db.session.commit()
        yield (
            app.test_client(),
            {'Authorization': f'Bearer {token}'},
            {key: bank.id for key, bank in banks.items()},
        )
        db.session.remove()
        db.drop_all()


def snapshot(bank_id, **overrides):
    document = {
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': bank_id,
        'programKey': 'synthetic-program',
        'programName': 'Синтетическая программа',
        'collectedAt': '2026-10-02T10:00:00Z',
        'source': {'type': 'manual_verified', 'parserName': 'synthetic', 'parserVersion': '1'},
        'validity': {'from': '2026-10-01', 'confidence': 'exact'},
        'completeness': 'exact_mcc',
        'globalExcludedMcc': ['6011'],
        'exclusions': [
            {'mcc': ['4900', '4813'], 'kind': 'unless_category', 'reason': 'Только с категорией'},
            {'mcc': ['4511'], 'kind': 'conditional', 'reason': 'Только через сервис банка'},
            {'mcc': ['6011'], 'kind': 'conditional', 'reason': 'Повторно указан условно'},
        ],
        'categories': [
            {'sourceKey': 'cafe', 'name': 'Кафе и рестораны',
             'includedMcc': ['5811', '5812', '5813', '5814']},
            {'sourceKey': 'utilities', 'name': 'ЖКХ', 'includedMcc': ['4900']},
            {'sourceKey': 'everything', 'name': 'Все покупки', 'kind': 'all_purchases',
             'includedMcc': ['5271']},
            {'sourceKey': 'scooters', 'name': 'Самокаты', 'includedMcc': [],
             'canonicalKeys': ['scooters'], 'completeness': 'text_only'},
        ],
    }
    document.update(overrides)
    return document


def upload_and_publish(client, headers, document):
    created = client.post(
        '/api/admin/mcc-rule-snapshots', json={'document': document}, headers=headers,
    )
    assert created.status_code == 201, created.get_json()
    revision_id = created.get_json()['id']
    published = client.post(
        f'/api/admin/mcc-rule-revisions/{revision_id}/publish', headers=headers,
    )
    assert published.status_code == 200
    return published.get_json()


def test_bundled_canonical_categories_are_consistent():
    keys = [row['key'] for row in CANONICAL]
    catalogue = {row['code'] for row in load_bundled_mcc_catalog()}
    assert len(keys) == len(set(keys)) == 43
    assert {row['group_key'] for row in CANONICAL} >= {'food', 'auto', 'travel', 'payments'}
    for row in CANONICAL:
        assert set(row['core_mcc']) <= catalogue, row['key']
        assert row['aliases'], row['key']
    assert [row['key'] for row in CANONICAL if not row['core_mcc']] == ['scooters']


@pytest.mark.parametrize(('codes', 'expected'), [
    # A cafe list with fast food inside is broader than either canonical entry.
    (['5811', '5812', '5813', '5814'],
     {'restaurants': 'broader', 'fastfood': 'broader'}),
    # 5921 inside a supermarket list does not turn it into an alcohol offer.
    (['5411', '5412', '5422', '5441', '5451', '5462', '5499', '5921'],
     {'groceries': 'exact'}),
    # A single car-sharing code is a narrower variant of the canonical category.
    (['7512'], {'car_rental': 'narrower'}),
    (['5045', '5544', '7332'], {}),
])
def test_links_are_computed_from_mcc_overlap(codes, expected):
    links = compute_canonical_links(codes, CANONICAL)
    assert {link['key']: link['relation'] for link in links} == expected


def test_typed_exclusions_and_category_links_round_trip(client_and_headers):
    client, headers, banks = client_and_headers
    revision = upload_and_publish(client, headers, snapshot(banks['vtb']))

    assert revision['global_excluded_mcc'] == ['6011']
    by_code = {item['mcc']: item for item in revision['exclusions']}
    assert by_code['6011']['kind'] == 'always'
    assert by_code['6011']['reason'] == 'Повторно указан условно'
    assert by_code['4900'] == {'mcc': '4900', 'kind': 'unless_category',
                               'reason': 'Только с категорией'}
    assert by_code['4511']['kind'] == 'conditional'

    categories = {item['source_key']: item for item in revision['categories']}
    assert {link['key']: link['relation'] for link in categories['cafe']['canonical']} == {
        'restaurants': 'broader', 'fastfood': 'broader',
    }
    assert categories['cafe']['kind'] == 'mcc'
    assert categories['everything']['kind'] == 'all_purchases'
    assert categories['everything']['canonical'] == []
    assert categories['scooters']['canonical'] == [{
        'key': 'scooters', 'title': 'Самокаты', 'relation': 'exact',
        'coverage': None, 'source': 'manual',
    }]


def test_unknown_canonical_key_and_exclusion_kind_are_rejected(client_and_headers):
    client, headers, banks = client_and_headers
    document = snapshot(banks['vtb'])
    document['categories'][3]['canonicalKeys'] = ['not-a-category']
    response = client.post(
        '/api/admin/mcc-rule-snapshots', json={'document': document}, headers=headers,
    )
    assert response.status_code == 400
    assert 'unknown canonical category' in response.get_json()['error']

    document = snapshot(banks['vtb'], exclusions=[{'mcc': ['6011'], 'kind': 'sometimes'}])
    response = client.post(
        '/api/admin/mcc-rule-snapshots', json={'document': document}, headers=headers,
    )
    assert response.status_code == 400
    assert BankRuleRevision.query.count() == 0


@pytest.mark.parametrize(('code', 'status', 'category'), [
    ('6011', 'excluded', None),
    ('4900', 'category_only', 'ЖКХ'),
    ('4813', 'excluded', None),
    ('4511', 'conditional', None),
    ('5814', 'category', 'Кафе и рестораны'),
    ('7011', 'not_in_categories', None),
])
def test_mcc_check_explains_category_and_exclusion(client_and_headers, code, status, category):
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))

    response = client.get(f'/api/mcc/{code}/bank-rules?as_of=2026-10-10', headers=headers)

    assert response.status_code == 200
    rows = response.get_json()['banks']
    assert len(rows) == 1
    assert rows[0]['bank']['name'] == BANK_IMPORT_NAMES['vtb']
    assert rows[0]['status'] == status
    names = [item['name'] for item in rows[0]['categories']]
    assert names == ([category] if category else names)


def _offers(banks, rows):
    """Create one owner, a card per bank key and October offers; return offer ids by name."""
    owner = CardUser(name='Синтетический владелец')
    db.session.add(owner)
    db.session.flush()
    cards = {}
    ids = {}
    start, end = datetime(2026, 10, 1), datetime(2026, 11, 1)
    for bank_key, name in rows:
        if bank_key not in cards:
            card = BankCard(payment_system='Мир', card_type='virtual', last_four_digits='0000',
                            bank_id=banks[bank_key], user_id=owner.id)
            db.session.add(card)
            db.session.flush()
            cards[bank_key] = card.id
        offer = CashbackCategory(name=name, start_date=start, end_date=end,
                                 cashback_percent=5, card_id=cards[bank_key])
        db.session.add(offer)
        db.session.flush()
        ids[(bank_key, name)] = offer.id
    db.session.commit()
    return ids


@pytest.mark.parametrize(('code', 'earning'), [
    # A listed code earns in its category and in "all purchases".
    ('5814', {'Кафе и рестораны', 'Все покупки'}),
    # Not in any category: only "all purchases" earns.
    ('7011', {'Все покупки'}),
    # Excluded unless a category lists it: only that category earns.
    ('4900', {'ЖКХ'}),
    ('6011', set()),
])
def test_mcc_check_names_offers_that_earn(client_and_headers, code, earning):
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))
    ids = _offers(banks, [('vtb', 'Кафе и рестораны'), ('vtb', 'ЖКХ'),
                          ('vtb', 'Все покупки'), ('vtb', 'Такси')])

    rows = client.get(
        f'/api/mcc/{code}/bank-rules?as_of=2026-10-10', headers=headers,
    ).get_json()['banks']

    assert rows[0]['offer_ids'] == sorted(ids[('vtb', name)] for name in earning)


def test_mcc_list_returns_titled_catalogue(client_and_headers):
    client, headers, _ = client_and_headers

    rows = client.get('/api/mcc', headers=headers).get_json()

    assert len(rows) == 1077
    assert rows[0] == {'code': '0742', 'title': 'Ветеринарные услуги'}


def test_offer_mcc_rules_resolve_the_bank_category_by_name(client_and_headers):
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))
    ids = _offers(banks, [('vtb', 'кафе И рестораны'), ('vtb', 'Такси'),
                          ('ozon', 'Кафе и рестораны')])

    response = client.get(f"/api/cashback/{ids[('vtb', 'кафе И рестораны')]}/mcc-rules",
                          headers=headers)

    assert response.status_code == 200
    payload = response.get_json()
    assert payload['category']['name'] == 'Кафе и рестораны'
    assert [item['code'] for item in payload['category']['included']] == [
        '5811', '5812', '5813', '5814',
    ]
    assert payload['category']['included'][3]['title']
    exclusions = {item['mcc']: item for item in payload['exclusions']}
    assert exclusions['6011']['kind'] == 'always'
    assert exclusions['6011']['title']
    for key in (('vtb', 'Такси'), ('ozon', 'Кафе и рестораны')):
        missing = client.get(f'/api/cashback/{ids[key]}/mcc-rules', headers=headers)
        assert missing.status_code == 404
    assert client.get('/api/cashback/999999/mcc-rules', headers=headers).status_code == 404


def test_canonical_search_returns_broader_bank_categories(client_and_headers):
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))

    listing = client.get('/api/canonical-categories', headers=headers).get_json()
    assert listing[0]['key'] == 'groceries'
    assert listing[0]['core_mcc'][:2] == ['5411', '5412']

    response = client.get(
        '/api/canonical-categories/fastfood/bank-categories?as_of=2026-10-10', headers=headers,
    )
    offers = response.get_json()['bank_categories']
    assert [(item['category']['name'], item['relation']) for item in offers] == [
        ('Кафе и рестораны', 'broader'),
    ]
    assert offers[0]['also_covers'] == ['restaurants']
    missing = client.get('/api/canonical-categories/unknown/bank-categories', headers=headers)
    assert missing.status_code == 404


def test_bundled_bank_rules_import_is_idempotent(client_and_headers):
    client, headers, _ = client_and_headers
    runner = app.test_cli_runner()

    first = runner.invoke(args=['import-bank-mcc-rules'])
    assert first.exit_code == 0, first.output
    assert 'created: 6, unchanged: 0, published: 6, skipped: 0' in first.output
    second = runner.invoke(args=['import-bank-mcc-rules'])
    assert second.exit_code == 0, second.output
    assert 'created: 0, unchanged: 6, published: 0, skipped: 0' in second.output
    assert BankRuleRevision.query.filter_by(status='published').count() == 6

    fastfood = client.get(
        '/api/canonical-categories/fastfood/bank-categories?as_of=2026-10-10', headers=headers,
    ).get_json()['bank_categories']
    found = {(item['bank']['name'], item['category']['name'], item['relation'])
             for item in fastfood}
    assert (BANK_IMPORT_NAMES['vtb'], 'Кафе и рестораны', 'broader') in found
    assert (BANK_IMPORT_NAMES['tbank'], 'Фастфуд', 'exact') in found

    rail = client.get('/api/mcc/4011/bank-rules?as_of=2026-10-10', headers=headers).get_json()
    statuses = {row['bank']['name']: row['status'] for row in rail['banks']}
    assert statuses[BANK_IMPORT_NAMES['yandex']] == 'excluded'
    assert statuses[BANK_IMPORT_NAMES['tbank']] == 'category'


def test_import_skips_banks_that_are_not_configured(client_and_headers):
    Bank.query.filter_by(name=BANK_IMPORT_NAMES['ozon']).delete()
    db.session.commit()

    result = app.test_cli_runner().invoke(args=['import-bank-mcc-rules', '--draft'])

    assert result.exit_code == 0, result.output
    assert 'skipped ozon.json:ozon' in result.output
    assert 'created: 5, unchanged: 0, published: 0, skipped: 1' in result.output


@pytest.mark.parametrize(('name', 'expected'), [
    ('Фастфуд, кафе и рестораны', ['restaurants', 'fastfood']),
    ('Вет клиники и зоомагазины', ['pets']),
    ('Авиа в Тревел', ['airline']),
    ('Путешествия', ['airline', 'hotels', 'rail', 'travel_agency']),
    ('Красота', ['beauty_salons', 'cosmetics']),
    ('Онлайн-кинотеатры', ['online_cinema']),
    ('Пятёрочка', []),
    ('Все покупки', []),
])
def test_offer_names_suggest_canonical_categories(name, expected):
    assert resolve_canonical_by_name(name) == expected


def test_personal_offers_inherit_bank_rule_links(client_and_headers):
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))
    owner = CardUser(name='Синтетический владелец')
    db.session.add(owner)
    db.session.flush()
    cards = {}
    for key in ('vtb', 'ozon'):
        card = BankCard(payment_system='Мир', card_type='virtual', last_four_digits='0000',
                        bank_id=banks[key], user_id=owner.id)
        db.session.add(card)
        db.session.flush()
        cards[key] = card.id
    start, end = datetime(2026, 10, 1), datetime(2026, 11, 1)
    for card_key, name in (('vtb', 'Кафе и рестораны'), ('ozon', 'Кафе и рестораны'),
                           ('ozon', 'Пятёрочка')):
        db.session.add(CashbackCategory(name=name, start_date=start, end_date=end,
                                        cashback_percent=5, card_id=cards[card_key]))
    db.session.commit()

    offers = client.get('/api/cashback', headers=headers).get_json()

    keys = {(item['card_id'], item['name']): item['canonical_keys'] for item in offers}
    # VTB's published category includes 5814, so its offer also covers fast food.
    assert keys[(cards['vtb'], 'Кафе и рестораны')] == ['restaurants', 'fastfood']
    # Ozon has no rules here: the name rules decide, and a brand stays unmapped.
    assert keys[(cards['ozon'], 'Кафе и рестораны')] == ['restaurants']
    assert keys[(cards['ozon'], 'Пятёрочка')] == []


def test_import_finds_differently_named_bank_by_icon_key(client_and_headers):
    Bank.query.filter_by(name=BANK_IMPORT_NAMES['ozon']).one().name = 'Ozon Банк'
    Bank.query.filter_by(name=BANK_IMPORT_NAMES['yandex']).one().name = 'Яндекс Пэй'
    Bank.query.filter_by(name=BANK_IMPORT_NAMES['alfa']).one().name = 'Альфа-Банк'
    db.session.add(Bank(name='Альфа-Банк (второй)', icon_key='alfa'))
    db.session.commit()

    result = app.test_cli_runner().invoke(args=['import-bank-mcc-rules', '--draft'])

    assert result.exit_code == 0, result.output
    # Two banks share the alfa key, so the import refuses to guess.
    assert 'skipped alfa.json:alfa' in result.output
    assert 'created ozon.json:ozon' in result.output
    assert 'created yandex.json:yandex' in result.output
    assert 'created: 5, unchanged: 0, published: 0, skipped: 1' in result.output

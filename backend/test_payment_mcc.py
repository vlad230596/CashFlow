"""MCC codes on planned payments and the best-card suggestion they drive."""

import importlib.util
from datetime import date, datetime
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations

import main
from main import BankCard, CardUser, CashbackCategory, db
from test_canonical_categories import (  # noqa: F401 - the fixture is used by name
    client_and_headers,
    snapshot,
    upload_and_publish,
)

NOVEMBER = (datetime(2026, 11, 1), datetime(2026, 12, 1))
DECEMBER = (datetime(2026, 12, 1), datetime(2027, 1, 1))


@pytest.fixture()
def today(monkeypatch):
    current = {'value': date(2026, 11, 17)}
    monkeypatch.setattr(main, '_business_today', lambda: current['value'])
    return current


def _card(bank_id, owner_id, digits, *, active=True):
    card = BankCard(payment_system='Мир', card_type='virtual', last_four_digits=digits,
                    bank_id=bank_id, user_id=owner_id, is_active=active)
    db.session.add(card)
    db.session.flush()
    return card


def _offer(card, name, percent, period=NOVEMBER, *, selected=True, confirmed=True):
    offer = CashbackCategory(
        name=name, start_date=period[0], end_date=period[1], cashback_percent=percent,
        card_id=card.id, is_selected=selected, is_bank_confirmed=confirmed,
    )
    db.session.add(offer)
    db.session.flush()
    return offer


@pytest.fixture()
def family(client_and_headers):  # noqa: F811
    """Three VTB cards with November and December offers under published rules."""
    client, headers, banks = client_and_headers
    upload_and_publish(client, headers, snapshot(banks['vtb']))
    owner = CardUser(name='Синтетический владелец')
    db.session.add(owner)
    db.session.flush()
    cafe = _card(banks['vtb'], owner.id, '1111')
    everything = _card(banks['vtb'], owner.id, '2222')
    closed = _card(banks['vtb'], owner.id, '3333', active=False)
    offers = {
        'cafe': _offer(cafe, 'Кафе и рестораны', 5),
        'taxi': _offer(cafe, 'Такси', 7),
        'all': _offer(everything, 'Все покупки', 1.5),
        'unselected': _offer(everything, 'Кафе и рестораны', 8, selected=False),
        'unconfirmed': _offer(everything, 'Кафе и рестораны', 9, confirmed=False),
        'closed': _offer(closed, 'Кафе и рестораны', 10),
        'december': _offer(everything, 'Кафе и рестораны', 7, DECEMBER),
    }
    db.session.commit()
    return client, headers, {'cafe': cafe.id, 'all': everything.id, 'closed': closed.id}, {
        key: offer.id for key, offer in offers.items()
    }


def _create(client, headers, **overrides):
    payload = {
        'name': 'Кафе по подписке',
        'kind': 'recurring',
        'expected_amount': '1200',
        'interval': {'count': 1, 'unit': 'month'},
        'next_due_date': '2026-11-25',
    }
    payload.update(overrides)
    return client.post('/api/payments', headers=headers, json=payload)


def test_payment_without_mcc_has_no_suggestion(client_and_headers, today):  # noqa: F811
    client, headers, _ = client_and_headers
    payload = _create(client, headers).get_json()
    assert payload['mcc_code'] is None
    assert payload['card_suggestion'] is None


@pytest.mark.parametrize('value', ['123', '12345', 'abcd', 5814, True])
def test_invalid_mcc_is_rejected(client_and_headers, today, value):  # noqa: F811
    client, headers, _ = client_and_headers
    response = _create(client, headers, mcc_code=value)
    assert response.status_code == 400
    assert 'mcc_code' in response.get_json()['error']


def test_best_active_card_on_the_due_date(family, today):
    client, headers, cards, offers = family

    response = _create(client, headers, mcc_code='5814')

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['mcc_code'] == '5814'
    suggestion = payload['card_suggestion']
    assert suggestion['status'] == 'best'
    assert suggestion['as_of'] == '2026-11-25'
    # The 10% offer sits on an inactive card; 8% is not selected, 9% not confirmed.
    assert suggestion['best'] == {
        'offer_id': offers['cafe'],
        'card_id': cards['cafe'],
        'bank_id': suggestion['best']['bank_id'],
        'bank_name': suggestion['best']['bank_name'],
        'last_four_digits': '1111',
        'category_name': 'Кафе и рестораны',
        'category_type': 'standard',
        'cashback_percent': 5,
    }
    assert [item['offer_id'] for item in suggestion['alternatives']] == [offers['all']]

    # The list and detail answers carry the same suggestion.
    listed = client.get('/api/payments', headers=headers).get_json()['items'][0]
    assert listed['card_suggestion'] == suggestion
    detail = client.get(f"/api/payments/{payload['id']}", headers=headers).get_json()
    assert detail['card_suggestion'] == suggestion


def test_suggestion_follows_the_due_date_month(family, today):
    client, headers, cards, offers = family
    created = _create(client, headers, mcc_code='5814').get_json()

    moved = client.put(
        f"/api/payments/{created['id']}", headers=headers,
        json={'next_due_date': '2026-12-10'},
    ).get_json()

    assert moved['card_suggestion']['as_of'] == '2026-12-10'
    assert moved['card_suggestion']['best']['offer_id'] == offers['december']
    assert moved['card_suggestion']['best']['card_id'] == cards['all']


def test_overdue_payment_uses_today(family, today):
    client, headers, _, offers = family
    created = _create(client, headers, mcc_code='5814', next_due_date='2026-11-10').get_json()
    today['value'] = date(2026, 12, 3)

    detail = client.get(f"/api/payments/{created['id']}", headers=headers).get_json()

    assert detail['card_suggestion']['as_of'] == '2026-12-03'
    assert detail['card_suggestion']['best']['offer_id'] == offers['december']


def test_excluded_code_has_no_bonus_and_unknown_rules_say_so(family, today):
    client, headers, _, _ = family
    excluded = _create(client, headers, mcc_code='6011').get_json()
    assert excluded['card_suggestion'] == {
        'mcc_code': '6011', 'as_of': '2026-11-25', 'status': 'no_bonus',
        'best': None, 'alternatives': [],
    }


def test_no_rules_status(client_and_headers, today):  # noqa: F811
    client, headers, _ = client_and_headers
    payload = _create(client, headers, mcc_code='5814').get_json()
    assert payload['card_suggestion']['status'] == 'no_rules'
    assert payload['card_suggestion']['best'] is None


def test_update_and_clear_mcc(family, today):
    client, headers, _, _ = family
    created = _create(client, headers).get_json()

    updated = client.put(
        f"/api/payments/{created['id']}", headers=headers, json={'mcc_code': '4900'},
    ).get_json()
    assert updated['mcc_code'] == '4900'
    # 4900 earns only inside a category listing it; no card has «ЖКХ».
    assert updated['card_suggestion']['status'] == 'no_bonus'

    cleared = client.put(
        f"/api/payments/{created['id']}", headers=headers, json={'mcc_code': ''},
    ).get_json()
    assert cleared['mcc_code'] is None
    assert cleared['card_suggestion'] is None

    untouched = client.put(
        f"/api/payments/{created['id']}", headers=headers, json={'name': 'Другое'},
    ).get_json()
    assert untouched['mcc_code'] is None


def test_paid_one_off_payment_drops_the_suggestion(family, today):
    client, headers, _, _ = family
    created = _create(client, headers, mcc_code='5814', kind='one_off', interval=None).get_json()
    assert created['card_suggestion']['status'] == 'best'

    paid = client.post(
        f"/api/payments/{created['id']}/records", headers=headers, json={'paid_at': '2026-11-17'},
    ).get_json()

    assert paid['is_completed'] is True
    assert paid['mcc_code'] == '5814'
    assert paid['card_suggestion'] is None


def test_bank_rules_still_name_earning_offers(family, today):
    client, headers, _, offers = family
    rows = client.get('/api/mcc/5814/bank-rules?as_of=2026-11-20', headers=headers).get_json()
    earning = rows['banks'][0]['offer_ids']
    assert earning == sorted(
        offers[key] for key in ('cafe', 'all', 'unselected', 'unconfirmed', 'closed')
    )


def test_migration_adds_and_drops_the_column():
    path = Path(__file__).parent / 'migrations/versions/0015_payment_mcc.py'
    spec = importlib.util.spec_from_file_location('payment_mcc_migration', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.down_revision == '0014_zenmoney_balances'
    engine = sa.create_engine('sqlite://')
    metadata = sa.MetaData()
    table = sa.Table(
        'planned_payment',
        metadata,
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(200), nullable=False),
    )
    metadata.create_all(engine)
    with engine.begin() as connection:
        connection.execute(table.insert(), [{'id': 1, 'name': 'Детский сад'}])
        operations = Operations(MigrationContext.configure(connection))
        with Operations.context(operations.migration_context):
            module.upgrade()
        columns = {
            item['name']: item
            for item in sa.inspect(connection).get_columns('planned_payment')
        }
        assert columns['mcc_code']['nullable'] is True
        assert connection.execute(
            sa.text('SELECT mcc_code FROM planned_payment')
        ).scalar() is None
        with Operations.context(operations.migration_context):
            module.downgrade()
        assert 'mcc_code' not in {
            item['name'] for item in sa.inspect(connection).get_columns('planned_payment')
        }
        assert connection.execute(sa.text('SELECT COUNT(*) FROM planned_payment')).scalar() == 1

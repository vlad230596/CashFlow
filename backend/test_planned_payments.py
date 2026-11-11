from datetime import date

import pytest

import main
import payment_schedule
from main import AuthUser, Bank, CardUser, _hash_password, _utc_now, app, db

ADMIN_PASSWORD = 'correct horse battery staple'
VIEWER_PASSWORD = 'another correct horse battery'


@pytest.fixture()
def client(monkeypatch):
    app.config.update(TESTING=True, CASHFLOW_SESSION_TTL_HOURS=12)
    monkeypatch.setattr(main, '_business_today', lambda: date(2026, 11, 11))
    with app.app_context():
        db.create_all()
        now = _utc_now()
        db.session.add_all([
            AuthUser(
                username='admin',
                password_hash=_hash_password(ADMIN_PASSWORD),
                role='admin',
                auth_enabled=True,
                created_at=now,
                updated_at=now,
            ),
            AuthUser(
                username='viewer',
                password_hash=_hash_password(VIEWER_PASSWORD),
                role='viewer',
                auth_enabled=True,
                created_at=now,
                updated_at=now,
            ),
            Bank(name='Test bank'),
            CardUser(name='Card profile'),
        ])
        db.session.commit()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def _login(client, username, password):
    response = client.post(
        '/api/auth/login',
        json={'username': username, 'password': password},
    )
    assert response.status_code == 200
    return {'Authorization': f"Bearer {response.get_json()['access_token']}"}


def _admin(client):
    return _login(client, 'admin', ADMIN_PASSWORD)


def _viewer(client):
    return _login(client, 'viewer', VIEWER_PASSWORD)


def _create_card(client, admin):
    response = client.post(
        '/api/cards',
        headers=admin,
        json={
            'payment_system': 'Mir',
            'card_type': 'physical',
            'last_four_digits': '1234',
            'bank_id': 1,
            'user_id': 1,
        },
    )
    assert response.status_code == 201
    return response.get_json()['id']


def _create(client, headers, **overrides):
    payload = {
        'name': 'Детский сад',
        'kind': 'recurring',
        'expected_amount': '8500',
        'currency': 'rub',
        'interval': {'count': 1, 'unit': 'month'},
        'next_due_date': '2026-11-25',
    }
    payload.update(overrides)
    return client.post('/api/payments', headers=headers, json=payload)


def _pay(client, headers, payment_id, **payload):
    return client.post(f'/api/payments/{payment_id}/records', headers=headers, json=payload)


# Pure schedule math -------------------------------------------------------


def test_month_end_anchor_does_not_drift():
    anchor = date(2026, 1, 31)
    dates = [payment_schedule.occurrence(anchor, 1, 'month', i) for i in range(5)]
    assert dates == [
        date(2026, 1, 31),
        date(2026, 2, 28),
        date(2026, 3, 31),
        date(2026, 4, 30),
        date(2026, 5, 31),
    ]
    assert payment_schedule.next_occurrence_after(anchor, 1, 'month', date(2026, 2, 28)) == (
        date(2026, 3, 31)
    )


def test_leap_day_yearly_and_week_schedules():
    leap = date(2024, 2, 29)
    assert payment_schedule.next_occurrence_after(leap, 1, 'year', leap) == date(2025, 2, 28)
    assert payment_schedule.next_occurrence_after(leap, 1, 'year', date(2027, 3, 1)) == (
        date(2028, 2, 29)
    )
    anchor = date(2026, 11, 2)
    assert payment_schedule.next_occurrence_after(anchor, 2, 'week', date(2026, 11, 15)) == (
        date(2026, 11, 16)
    )
    assert payment_schedule.next_occurrence_after(anchor, 2, 'week', date(2026, 11, 16)) == (
        date(2026, 11, 30)
    )
    assert payment_schedule.next_occurrence_after(anchor, 1, 'day', date(2026, 10, 1)) == anchor


def test_occurrence_helpers():
    anchor = date(2026, 1, 31)
    assert payment_schedule.is_occurrence(anchor, 1, 'month', date(2026, 2, 28))
    assert not payment_schedule.is_occurrence(anchor, 1, 'month', date(2026, 2, 27))
    assert not payment_schedule.is_occurrence(anchor, 1, 'month', date(2025, 12, 31))
    assert payment_schedule.occurrences_between(
        anchor, 3, 'month', date(2026, 2, 1), date(2026, 12, 31),
    ) == [date(2026, 4, 30), date(2026, 7, 31), date(2026, 10, 31)]


# API ------------------------------------------------------------------------


def test_create_recurring_defaults_and_viewer_access(client):
    viewer = _viewer(client)

    response = _create(client, viewer)

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['kind'] == 'recurring'
    assert payload['expected_amount'] == '8500.00'
    assert payload['currency'] == 'RUB'
    assert payload['card_id'] is None
    assert payload['note'] is None
    assert payload['interval'] == {'count': 1, 'unit': 'month'}
    assert payload['anchor_date'] == '2026-11-25'
    assert payload['next_due_date'] == '2026-11-25'
    assert payload['reminder_days'] == [1]
    assert payload['is_completed'] is False
    assert payload['records'] == []


def test_mark_paid_advances_to_next_anchored_date_not_paid_date(client):
    viewer = _viewer(client)
    payment = _create(client, viewer).get_json()

    # Paid early on the 11th: the next due date stays anchored to the 25th.
    response = _pay(client, viewer, payment['id'], paid_at='2026-11-11', amount='8700')

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['next_due_date'] == '2026-12-25'
    assert payload['expected_amount'] == '8500.00'
    assert payload['last_record']['due_date'] == '2026-11-25'
    assert payload['last_record']['paid_at'] == '2026-11-11'
    assert payload['last_record']['amount'] == '8700.00'

    assert _pay(client, viewer, payment['id']).get_json()['next_due_date'] == '2027-01-25'


def test_month_end_anchor_through_api(client):
    viewer = _viewer(client)
    payment = _create(
        client,
        viewer,
        next_due_date='2026-02-28',
        anchor_date='2026-01-31',
    ).get_json()
    assert payment['anchor_date'] == '2026-01-31'

    paid = _pay(client, viewer, payment['id'], paid_at='2026-02-27').get_json()
    assert paid['next_due_date'] == '2026-03-31'
    paid = _pay(client, viewer, payment['id'], paid_at='2026-03-30').get_json()
    assert paid['next_due_date'] == '2026-04-30'

    rejected = _create(client, viewer, next_due_date='2026-02-27', anchor_date='2026-01-31')
    assert rejected.status_code == 400
    assert 'schedule' in rejected.get_json()['error']


def test_one_off_completes_and_leaves_active_list(client):
    viewer = _viewer(client)
    payment = _create(
        client,
        viewer,
        name='Страховка',
        kind='one_off',
        interval=None,
        next_due_date='2026-11-13',
        reminder_days=[3, 1, 1],
    ).get_json()
    assert payment['interval'] is None
    assert payment['reminder_days'] == [3, 1]

    response = _pay(client, viewer, payment['id'])
    assert response.status_code == 201
    payload = response.get_json()
    assert payload['is_completed'] is True
    assert payload['next_due_date'] == '2026-11-13'
    assert payload['last_record']['paid_at'] == '2026-11-11'

    assert _pay(client, viewer, payment['id']).status_code == 409
    active = client.get('/api/payments', headers=viewer).get_json()
    assert active['total'] == 0
    completed = client.get('/api/payments?status=completed', headers=viewer).get_json()
    assert [item['id'] for item in completed['items']] == [payment['id']]

    assert _create(
        client, viewer, kind='one_off', interval={'count': 1, 'unit': 'month'},
    ).status_code == 400


def test_undo_latest_record_restores_due_date_and_completion(client):
    viewer = _viewer(client)
    recurring = _create(client, viewer).get_json()
    first = _pay(client, viewer, recurring['id']).get_json()['last_record']
    second = _pay(client, viewer, recurring['id']).get_json()['last_record']

    older = client.delete(
        f"/api/payments/{recurring['id']}/records/{first['id']}", headers=viewer,
    )
    assert older.status_code == 409
    undone = client.delete(
        f"/api/payments/{recurring['id']}/records/{second['id']}", headers=viewer,
    ).get_json()
    assert undone['next_due_date'] == '2026-12-25'
    assert [record['id'] for record in undone['records']] == [first['id']]

    one_off = _create(
        client, viewer, kind='one_off', interval=None, next_due_date='2026-11-13',
    ).get_json()
    record = _pay(client, viewer, one_off['id']).get_json()['last_record']
    restored = client.delete(
        f"/api/payments/{one_off['id']}/records/{record['id']}", headers=viewer,
    ).get_json()
    assert restored['is_completed'] is False
    assert restored['next_due_date'] == '2026-11-13'


def test_mark_paid_validation_uses_moscow_today(client):
    viewer = _viewer(client)
    payment = _create(client, viewer).get_json()

    future = _pay(client, viewer, payment['id'], paid_at='2026-11-12')
    assert future.status_code == 400
    assert _pay(client, viewer, payment['id'], amount='0').status_code == 400
    assert _pay(client, viewer, payment['id'], card_id=999).status_code == 404


def test_edit_reanchors_and_validates(client):
    admin = _admin(client)
    viewer = _viewer(client)
    card_id = _create_card(client, admin)
    payment = _create(client, viewer, card_id=card_id, note='  группа 3 ').get_json()
    assert payment['card_id'] == card_id
    assert payment['note'] == 'группа 3'

    response = client.put(
        f"/api/payments/{payment['id']}",
        headers=viewer,
        json={
            'next_due_date': '2026-12-10',
            'reminder_days': [2, 0],
            'card_id': None,
            'note': '',
        },
    )
    assert response.status_code == 200
    payload = response.get_json()
    assert payload['anchor_date'] == '2026-12-10'
    assert payload['next_due_date'] == '2026-12-10'
    assert payload['reminder_days'] == [2, 0]
    assert payload['card_id'] is None
    assert payload['note'] is None

    # Changing only the amount keeps the month-end anchor intact.
    month_end = _create(
        client, viewer, next_due_date='2026-11-30', anchor_date='2026-10-31',
    ).get_json()
    kept = client.put(
        f"/api/payments/{month_end['id']}",
        headers=viewer,
        json={'expected_amount': '9000.50', 'next_due_date': '2026-11-30'},
    ).get_json()
    assert kept['anchor_date'] == '2026-10-31'
    assert kept['expected_amount'] == '9000.50'

    for invalid in (
        {'kind': 'one_off'},
        {'name': ' '},
        {'interval': {'count': 0, 'unit': 'month'}},
        {'reminder_days': [-1]},
        {'next_due_date': '2026-13-01'},
        {'currency': 'RUBLE'},
    ):
        response = client.put(f"/api/payments/{payment['id']}", headers=viewer, json=invalid)
        assert response.status_code == 400, invalid
    assert client.put(
        f"/api/payments/{payment['id']}", headers=viewer, json={'card_id': 999},
    ).status_code == 404
    unchanged = client.get(f"/api/payments/{payment['id']}", headers=viewer).get_json()
    assert unchanged['name'] == 'Детский сад'
    assert unchanged['next_due_date'] == '2026-12-10'


def test_archive_restore_and_delete(client):
    viewer = _viewer(client)
    payment = _create(client, viewer).get_json()
    path = f"/api/payments/{payment['id']}"

    archived = client.post(f'{path}/archive', headers=viewer)
    assert archived.status_code == 200
    assert archived.get_json()['is_archived'] is True
    assert client.post(f'{path}/archive', headers=viewer).status_code == 409
    assert _pay(client, viewer, payment['id']).status_code == 409
    assert client.get('/api/payments?status=archived', headers=viewer).get_json()['total'] == 1

    restored = client.post(
        f'{path}/restore', headers=viewer, json={'next_due_date': '2027-01-05'},
    ).get_json()
    assert restored['is_archived'] is False
    assert restored['next_due_date'] == '2027-01-05'
    assert restored['anchor_date'] == '2027-01-05'
    assert client.post(f'{path}/restore', headers=viewer, json={}).status_code == 409

    assert client.delete(path, headers=viewer).status_code == 204
    assert client.get(path, headers=viewer).status_code == 404


def test_payments_are_private_to_owner(client):
    admin = _admin(client)
    viewer = _viewer(client)
    payment = _create(client, viewer).get_json()
    path = f"/api/payments/{payment['id']}"

    assert client.get('/api/payments', headers=admin).get_json()['total'] == 0
    assert client.get(path, headers=admin).status_code == 404
    assert client.put(path, headers=admin, json={'name': 'x'}).status_code == 404
    assert client.delete(path, headers=admin).status_code == 404
    assert client.post(f'{path}/archive', headers=admin).status_code == 404
    assert _pay(client, admin, payment['id']).status_code == 404
    assert client.get('/api/payments/upcoming', headers=admin).get_json()['total'] == 0
    assert client.get('/api/payments').status_code == 401


def test_upcoming_expands_schedule_with_overdue_items(client):
    viewer = _viewer(client)
    _create(client, viewer, next_due_date='2026-10-25')
    _create(
        client,
        viewer,
        name='Налог',
        kind='one_off',
        interval=None,
        next_due_date='2026-12-01',
        expected_amount='1200',
    )
    done = _create(client, viewer, name='Done', kind='one_off', interval=None).get_json()
    _pay(client, viewer, done['id'])

    response = client.get('/api/payments/upcoming?until=2027-01-31', headers=viewer)

    assert response.status_code == 200
    payload = response.get_json()
    assert payload['today'] == '2026-11-11'
    assert [(item['name'], item['due_date'], item['is_overdue']) for item in payload['items']] == [
        ('Детский сад', '2026-10-25', True),
        ('Детский сад', '2026-11-25', False),
        ('Налог', '2026-12-01', False),
        ('Детский сад', '2026-12-25', False),
        ('Детский сад', '2027-01-25', False),
    ]
    assert client.get(
        '/api/payments/upcoming?until=2026-11-01', headers=viewer,
    ).status_code == 400
    assert client.get(
        '/api/payments/upcoming?until=2030-01-01', headers=viewer,
    ).status_code == 400


def test_list_filters_and_create_validation(client):
    viewer = _viewer(client)
    assert client.get('/api/payments?status=bogus', headers=viewer).status_code == 400
    assert client.get('/api/payments?kind=bogus', headers=viewer).status_code == 400
    _create(client, viewer)
    _create(client, viewer, name='Разовый', kind='one_off', interval=None)
    one_off = client.get('/api/payments?kind=one_off', headers=viewer).get_json()
    assert [item['name'] for item in one_off['items']] == ['Разовый']

    for invalid in (
        {'kind': 'weekly'},
        {'interval': None},
        {'next_due_date': None},
        {'expected_amount': '-1'},
        {'anchor_date': '2026-12-01'},
        {'note': 5},
    ):
        assert _create(client, viewer, **invalid).status_code == 400, invalid
    assert _create(client, viewer, card_id=999).status_code == 404

from datetime import date

import pytest

from main import (
    AuthUser,
    Bank,
    CardUser,
    SubscriptionActivePeriod,
    SubscriptionPayment,
    _hash_password,
    _utc_now,
    app,
    db,
)


@pytest.fixture()
def client():
    app.config.update(TESTING=True, CASHFLOW_SESSION_TTL_HOURS=12)
    with app.app_context():
        db.create_all()
        now = _utc_now()
        db.session.add_all([
            AuthUser(
                username='admin',
                password_hash=_hash_password('correct horse battery staple'),
                role='admin',
                auth_enabled=True,
                created_at=now,
                updated_at=now,
            ),
            AuthUser(
                username='viewer',
                password_hash=_hash_password('another correct horse battery'),
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


def _create_subscription(client, headers, card_id, **overrides):
    payload = {
        'name': 'Cloud storage',
        'kind': 'subscription',
        'expected_amount': '3590.00',
        'currency': 'rub',
        'card_id': card_id,
        'billing_interval': {'count': 1, 'unit': 'year'},
        'last_payment': {'paid_at': '2026-03-01'},
    }
    payload.update(overrides)
    return client.post('/api/subscriptions', headers=headers, json=payload)


def test_create_from_last_payment_computes_next_date_and_defaults(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    viewer = _login(client, 'viewer', 'another correct horse battery')
    card_id = _create_card(client, admin)

    response = _create_subscription(client, viewer, card_id)

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['expected_amount'] == '3590.00'
    assert payload['currency'] == 'RUB'
    assert payload['billing_interval'] == {'count': 1, 'unit': 'year'}
    assert payload['next_payment_date'] == '2027-03-01'
    assert payload['reminder_days'] == [30, 7, 1]
    assert payload['last_payment']['paid_at'] == '2026-03-01'
    assert len(payload['payments']) == 1
    assert len(payload['active_periods']) == 1
    assert payload['active_periods'][0]['ended_at'] is None


def test_explicit_next_date_wins_and_trial_has_short_reminders(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    card_id = _create_card(client, admin)

    response = _create_subscription(
        client,
        admin,
        card_id,
        kind='trial',
        billing_interval={'count': 14, 'unit': 'day'},
        next_payment_date='2026-03-20',
    )

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['next_payment_date'] == '2026-03-20'
    assert payload['reminder_days'] == [3, 1]


def test_confirm_payment_appends_history_and_updates_expectation(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    card_id = _create_card(client, admin)
    subscription = _create_subscription(
        client,
        admin,
        card_id,
        billing_interval={'count': 1, 'unit': 'month'},
        last_payment={'paid_at': '2020-01-31'},
    ).get_json()

    response = client.post(
        f"/api/subscriptions/{subscription['id']}/payments",
        headers=admin,
        json={'paid_at': '2020-02-29', 'amount': '4290', 'card_id': card_id},
    )

    assert response.status_code == 201
    payload = response.get_json()
    assert payload['expected_amount'] == '4290.00'
    assert payload['next_payment_date'] == '2020-03-29'
    assert payload['last_payment']['amount'] == '4290.00'
    assert [payment['paid_at'] for payment in payload['payments']] == [
        '2020-02-29',
        '2020-01-31',
    ]
    with app.app_context():
        assert SubscriptionPayment.query.count() == 2


def test_confirm_payment_rejects_retry_for_same_date(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    card_id = _create_card(client, admin)
    subscription = _create_subscription(
        client,
        admin,
        card_id,
        billing_interval={'count': 1, 'unit': 'month'},
        last_payment={'paid_at': '2020-01-31'},
    ).get_json()
    url = f"/api/subscriptions/{subscription['id']}/payments"
    payment = {'paid_at': '2020-02-29', 'amount': '4290', 'card_id': card_id}

    assert client.post(url, headers=admin, json=payment).status_code == 201
    retry = client.post(url, headers=admin, json=payment)

    assert retry.status_code == 409
    assert retry.get_json() == {'error': 'Payment for this date already exists'}
    with app.app_context():
        assert SubscriptionPayment.query.count() == 2


def test_archive_and_restore_preserve_history_and_open_new_period(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    card_id = _create_card(client, admin)
    subscription = _create_subscription(client, admin, card_id).get_json()
    url = f"/api/subscriptions/{subscription['id']}"

    archived = client.post(f'{url}/archive', headers=admin)
    assert archived.status_code == 200
    assert archived.get_json()['is_archived'] is True
    assert archived.get_json()['active_periods'][0]['ended_at'] is not None
    assert client.post(
        f'{url}/payments',
        headers=admin,
        json={'paid_at': '2020-03-01'},
    ).status_code == 409

    missing_date = client.post(f'{url}/restore', headers=admin, json={})
    assert missing_date.status_code == 400
    restored = client.post(
        f'{url}/restore',
        headers=admin,
        json={'next_payment_date': '2027-04-01'},
    )
    assert restored.status_code == 200
    payload = restored.get_json()
    assert payload['is_archived'] is False
    assert payload['next_payment_date'] == '2027-04-01'
    assert len(payload['payments']) == 1
    assert len(payload['active_periods']) == 2
    assert payload['active_periods'][1]['ended_at'] is None
    with app.app_context():
        assert SubscriptionActivePeriod.query.count() == 2


def test_subscriptions_are_private_to_authenticated_owner(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    viewer = _login(client, 'viewer', 'another correct horse battery')
    card_id = _create_card(client, admin)
    subscription = _create_subscription(client, admin, card_id).get_json()

    assert client.get('/api/subscriptions', headers=viewer).get_json() == {
        'items': [],
        'total': 0,
    }
    assert client.get(
        f"/api/subscriptions/{subscription['id']}", headers=viewer
    ).status_code == 404
    assert client.put(
        f"/api/subscriptions/{subscription['id']}",
        headers=viewer,
        json={'name': 'Stolen'},
    ).status_code == 404


def test_edit_list_filters_and_validation(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    card_id = _create_card(client, admin)
    created = _create_subscription(client, admin, card_id).get_json()

    updated = client.put(
        f"/api/subscriptions/{created['id']}",
        headers=admin,
        json={
            'name': 'Updated cloud',
            'expected_amount': '4000.50',
            'reminder_days': [1, 7, 7, 30],
        },
    )
    assert updated.status_code == 200
    assert updated.get_json()['name'] == 'Updated cloud'
    assert updated.get_json()['reminder_days'] == [30, 7, 1]

    assert client.post(
        f"/api/subscriptions/{created['id']}/archive", headers=admin
    ).status_code == 200
    assert client.get('/api/subscriptions', headers=admin).get_json()['total'] == 0
    assert client.get(
        '/api/subscriptions?status=archived', headers=admin
    ).get_json()['total'] == 1
    assert client.get(
        '/api/subscriptions?status=invalid', headers=admin
    ).status_code == 400

    bad = _create_subscription(
        client,
        admin,
        card_id,
        expected_amount='12.345',
        last_payment={'paid_at': date.today().isoformat()},
    )
    assert bad.status_code == 400
    assert 'amount' in bad.get_json()['error']

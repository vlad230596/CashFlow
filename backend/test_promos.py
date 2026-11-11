from datetime import date

import pytest

import main
from main import AuthUser, PromoItem, _hash_password, _utc_now, app, db

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


def _create(client, headers, **overrides):
    payload = {
        'kind': 'promo',
        'title': 'Ozon: скидка 500 ₽',
        'merchant': 'Ozon',
        'promo_code': 'OZON500',
        'expires_at': '2026-11-30',
    }
    payload.update(overrides)
    response = client.post('/api/promos', headers=headers, json=payload)
    assert response.status_code == 201, response.get_json()
    return response.get_json()


def test_viewer_creates_promo_with_defaults_and_verbatim_source(client):
    viewer = _viewer(client)
    source = '  OZON: промокод OZON500\nдо 30 ноября  '
    item = _create(client, viewer, source_text=source)

    assert item['kind'] == 'promo'
    assert item['reminder_days'] == [3, 1]
    assert item['status'] == 'active'
    assert item['days_left'] == 19
    assert item['source_text'] == source
    assert item['is_used'] is False and item['is_archived'] is False

    detail = client.get(f"/api/promos/{item['id']}", headers=viewer)
    assert detail.status_code == 200
    assert detail.get_json()['promo_code'] == 'OZON500'


def test_points_item_and_unknown_expiry(client):
    viewer = _viewer(client)
    points = _create(
        client, viewer, kind='points', title='Пятёрочка: 300 баллов',
        promo_code=None, points_amount='300', points_unit='баллов',
        expires_at='2026-12-15', reminder_days=[7, 1, 1],
    )
    assert points['points_amount'] == '300.00'
    assert points['points_unit'] == 'баллов'
    assert points['reminder_days'] == [7, 1]

    no_expiry = _create(client, viewer, title='Без срока', expires_at=None)
    assert no_expiry['expires_at'] is None
    assert no_expiry['days_left'] is None
    assert no_expiry['status'] == 'active'


@pytest.mark.parametrize(('override', 'message'), [
    ({'kind': 'coupon'}, 'kind must be promo or points'),
    ({'title': '  '}, 'title must contain'),
    ({'title': None}, 'title is required'),
    ({'expires_at': '30.11.2026'}, 'expires_at must be a date'),
    ({'starts_at': '2026-12-01'}, 'starts_at cannot be later than expires_at'),
    ({'points_amount': '-5'}, 'points_amount must be a non-negative number'),
    ({'points_amount': 'много'}, 'points_amount must be a decimal number'),
    ({'reminder_days': [-1]}, 'reminder_days must be a list'),
    ({'promo_code': 'X' * 101}, 'promo_code cannot exceed 100 characters'),
    ({'client_id': 'bad id'}, 'client_id must be'),
])
def test_validation(client, override, message):
    viewer = _viewer(client)
    payload = {'kind': 'promo', 'title': 'Промокод', 'expires_at': '2026-11-30'}
    payload.update(override)
    response = client.post('/api/promos', headers=viewer, json=payload)
    assert response.status_code == 400
    assert message in response.get_json()['error']


def test_client_id_makes_offline_creation_idempotent(client):
    viewer = _viewer(client)
    first = client.post('/api/promos', headers=viewer, json={
        'client_id': 'local-0001-abcd', 'title': 'Офлайн', 'kind': 'promo',
    })
    assert first.status_code == 201
    retry = client.post('/api/promos', headers=viewer, json={
        'client_id': 'local-0001-abcd', 'title': 'Офлайн (повтор)', 'kind': 'promo',
    })
    assert retry.status_code == 200
    assert retry.get_json()['id'] == first.get_json()['id']
    assert retry.get_json()['title'] == 'Офлайн'
    # The same client id is independent per owner.
    other = client.post('/api/promos', headers=_admin(client), json={
        'client_id': 'local-0001-abcd', 'title': 'Чужой', 'kind': 'promo',
    })
    assert other.status_code == 201
    with app.app_context():
        assert PromoItem.query.count() == 2


def test_list_sorted_by_expiry_with_derived_statuses_and_filters(client):
    viewer = _viewer(client)
    later = _create(client, viewer, title='Позже', expires_at='2026-12-31')
    soon = _create(client, viewer, title='Скоро', expires_at='2026-11-12')
    none = _create(client, viewer, title='Без срока', expires_at=None)
    expired = _create(client, viewer, title='Истёк', expires_at='2026-11-10')
    used = _create(client, viewer, title='Использован', expires_at='2026-11-20')
    archived = _create(client, viewer, title='Архив', expires_at='2026-11-25')
    assert client.post(f"/api/promos/{used['id']}/use", headers=viewer).status_code == 200
    assert client.post(
        f"/api/promos/{archived['id']}/archive", headers=viewer,
    ).status_code == 200

    def titles(status):
        response = client.get(f'/api/promos?status={status}', headers=viewer)
        assert response.status_code == 200
        return [item['title'] for item in response.get_json()['items']]

    assert titles('active') == ['Скоро', 'Позже', 'Без срока']
    assert titles('expired') == ['Истёк']
    assert titles('used') == ['Использован']
    assert titles('archived') == ['Архив']
    assert titles('all') == [
        'Истёк', 'Скоро', 'Использован', 'Архив', 'Позже', 'Без срока',
    ]
    statuses = {
        item['id']: item['status']
        for item in client.get('/api/promos', headers=viewer).get_json()['items']
    }
    assert statuses == {
        later['id']: 'active', soon['id']: 'active', none['id']: 'active',
        expired['id']: 'expired', used['id']: 'used', archived['id']: 'archived',
    }
    assert client.get('/api/promos?status=bad', headers=viewer).status_code == 400


def test_use_unuse_archive_restore_and_conflicts(client):
    viewer = _viewer(client)
    item = _create(client, viewer)
    path = f"/api/promos/{item['id']}"

    used = client.post(f'{path}/use', headers=viewer)
    assert used.status_code == 200
    assert used.get_json()['status'] == 'used'
    assert used.get_json()['used_at'] is not None
    assert client.post(f'{path}/use', headers=viewer).status_code == 409

    restored = client.post(f'{path}/unuse', headers=viewer)
    assert restored.get_json()['status'] == 'active'
    assert client.post(f'{path}/unuse', headers=viewer).status_code == 409

    assert client.post(f'{path}/archive', headers=viewer).get_json()['status'] == 'archived'
    assert client.post(f'{path}/archive', headers=viewer).status_code == 409
    assert client.post(f'{path}/restore', headers=viewer).get_json()['status'] == 'active'
    assert client.post(f'{path}/restore', headers=viewer).status_code == 409


def test_update_partial_fields_and_delete(client):
    viewer = _viewer(client)
    item = _create(client, viewer, source_text='Исходный текст')
    path = f"/api/promos/{item['id']}"

    response = client.put(path, headers=viewer, json={
        'expires_at': None,
        'promo_code': '  NEW10 ',
        'reminder_days': [],
    })
    assert response.status_code == 200
    updated = response.get_json()
    assert updated['expires_at'] is None
    assert updated['promo_code'] == 'NEW10'
    assert updated['reminder_days'] == []
    assert updated['title'] == item['title']
    assert updated['source_text'] == 'Исходный текст'

    bad = client.put(path, headers=viewer, json={'starts_at': '2026-12-01',
                                                  'expires_at': '2026-11-01'})
    assert bad.status_code == 400
    assert client.get(path, headers=viewer).get_json()['starts_at'] is None

    assert client.delete(path, headers=viewer).status_code == 204
    assert client.get(path, headers=viewer).status_code == 404


def test_promos_are_owner_scoped(client):
    item = _create(client, _admin(client))
    viewer = _viewer(client)
    path = f"/api/promos/{item['id']}"
    assert client.get(path, headers=viewer).status_code == 404
    assert client.put(path, headers=viewer, json={'title': 'x'}).status_code == 404
    assert client.post(f'{path}/use', headers=viewer).status_code == 404
    assert client.delete(path, headers=viewer).status_code == 404
    assert client.get('/api/promos', headers=viewer).get_json()['items'] == []
    assert client.get('/api/promos').status_code == 401


def test_parse_endpoint(client):
    viewer = _viewer(client)
    response = client.post('/api/promos/parse', headers=viewer, json={
        'text': 'Самокат: промокод SAM300 на скидку 300 ₽ до 10 ноября',
    })
    assert response.status_code == 200
    result = response.get_json()
    assert result['promo_code'] == 'SAM300'
    assert result['merchant'] == 'Самокат'
    # 10 November is already past on 11 November 2026 (Moscow): next year.
    assert result['expires_at'] == '2027-11-10'
    assert result['today'] == '2026-11-11'
    with app.app_context():
        assert PromoItem.query.count() == 0

    assert client.post('/api/promos/parse', headers=viewer,
                       json={'text': '  '}).status_code == 400
    assert client.post('/api/promos/parse', headers=viewer,
                       json={'text': 'x' * 10001}).status_code == 400
    assert client.post('/api/promos/parse', headers=viewer,
                       data='text').status_code == 415

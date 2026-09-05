from datetime import datetime, timedelta

import pytest

from main import (
    AuthSession,
    AuthUser,
    _as_utc,
    _hash_password,
    _utc_now,
    app,
    db,
)


@pytest.fixture()
def client():
    app.config.update(
        TESTING=True,
        CASHFLOW_SESSION_TTL_HOURS=12,
    )
    with app.app_context():
        assert str(db.engine.url) == 'sqlite://'
        db.create_all()
        now = _utc_now()
        db.session.add(AuthUser(
            username='admin',
            password_hash=_hash_password('correct horse battery staple'),
            role='admin',
            auth_enabled=True,
            created_at=now,
            updated_at=now,
        ))
        db.session.commit()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def login(client):
    response = client.post('/api/auth/login', json={
        'username': 'ADMIN',
        'password': 'correct horse battery staple',
    })
    assert response.status_code == 200
    return response.get_json()['access_token']


def test_protected_routes_require_a_bearer_token(client):
    response = client.get('/api/banks')
    assert response.status_code == 401


def test_login_and_current_user(client):
    token = login(client)
    response = client.get(
        '/api/auth/me',
        headers={'Authorization': f'Bearer {token}'},
    )
    assert response.status_code == 200
    assert response.get_json() == {
        'id': 1,
        'username': 'admin',
        'role': 'admin',
        'auth_enabled': True,
    }


def test_logout_revokes_the_session(client):
    token = login(client)
    headers = {'Authorization': f'Bearer {token}'}
    assert client.post('/api/auth/logout', headers=headers).status_code == 204
    assert client.get('/api/auth/me', headers=headers).status_code == 401


def test_expired_session_is_rejected(client):
    token = login(client)
    with app.app_context():
        session = AuthSession.query.one()
        session.expires_at = _utc_now() - timedelta(seconds=1)
        db.session.commit()
    response = client.get(
        '/api/auth/me',
        headers={'Authorization': f'Bearer {token}'},
    )
    assert response.status_code == 401


def test_active_session_is_extended_and_expiration_is_exposed(client):
    token = login(client)
    with app.app_context():
        session = AuthSession.query.one()
        old_expiration = _utc_now() + timedelta(hours=1)
        session.expires_at = old_expiration
        db.session.commit()

    response = client.get(
        '/api/auth/me',
        headers={'Authorization': f'Bearer {token}'},
    )

    assert response.status_code == 200
    exposed_expiration = datetime.fromisoformat(
        response.headers['X-CashFlow-Session-Expires-At']
    )
    assert exposed_expiration > old_expiration
    with app.app_context():
        assert _as_utc(AuthSession.query.one().expires_at) == exposed_expiration


def test_viewer_cannot_mutate_business_data(client):
    with app.app_context():
        now = _utc_now()
        db.session.add(AuthUser(
            username='viewer',
            password_hash=_hash_password('another correct horse battery'),
            role='viewer',
            auth_enabled=True,
            created_at=now,
            updated_at=now,
        ))
        db.session.commit()
    response = client.post('/api/auth/login', json={
        'username': 'viewer',
        'password': 'another correct horse battery',
    })
    token = response.get_json()['access_token']
    response = client.post(
        '/api/cashback',
        json={},
        headers={'Authorization': f'Bearer {token}'},
    )
    assert response.status_code == 403

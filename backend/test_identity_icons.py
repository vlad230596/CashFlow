import pytest

from main import USER_ICON_KEYS
from test_auth import login

pytest_plugins = ('test_auth',)


def test_bank_and_user_icons_are_created_and_editable(client):
    headers = {'Authorization': f'Bearer {login(client)}'}

    bank_response = client.post(
        '/api/banks',
        json={
            'name': 'Т-Банк',
            'description': 'Основной банк',
            'icon_key': 'tbank',
        },
        headers=headers,
    )
    assert bank_response.status_code == 201
    bank = bank_response.get_json()
    assert bank['icon_key'] == 'tbank'

    changed_bank = client.put(
        f"/api/banks/{bank['id']}",
        json={'name': 'Т-Банк', 'description': '', 'icon_key': 'generic'},
        headers=headers,
    )
    assert changed_bank.status_code == 200
    assert changed_bank.get_json()['icon_key'] == 'generic'

    user_response = client.post(
        '/api/users',
        json={'name': 'Анна', 'icon_key': 'girl'},
        headers=headers,
    )
    assert user_response.status_code == 201
    user = user_response.get_json()
    assert user['icon_key'] == 'girl'

    changed_user = client.put(
        f"/api/users/{user['id']}",
        json={'name': 'Анна', 'icon_key': 'person'},
        headers=headers,
    )
    assert changed_user.status_code == 200
    assert changed_user.get_json()['icon_key'] == 'person'


def test_unknown_identity_icon_is_rejected(client):
    headers = {'Authorization': f'Bearer {login(client)}'}
    response = client.post(
        '/api/users',
        json={'name': 'Некто', 'icon_key': 'unknown'},
        headers=headers,
    )
    assert response.status_code == 400


def test_bank_integration_identity_survives_rename_and_icon_change(client):
    from main import _resolve_import_card, _resolve_rules_bank

    headers = {'Authorization': f'Bearer {login(client)}'}
    bank = client.post('/api/banks', headers=headers,
                       json={'name': 'Альфа-Банк', 'icon_key': 'generic'}).get_json()
    assert bank['bank_key'] == 'alfa'
    changed = client.put(f"/api/banks/{bank['id']}", headers=headers,
                         json={'name': 'Мой основной банк', 'icon_key': 'tbank'})
    assert changed.status_code == 200
    assert changed.get_json()['bank_key'] == 'alfa'
    assert _resolve_rules_bank('alfa').id == bank['id']
    assert _resolve_rules_bank('tbank') is None
    user = client.post('/api/users', headers=headers, json={'name': 'Test'}).get_json()
    card = client.post('/api/cards', headers=headers, json={
        'bank_id': bank['id'], 'user_id': user['id'], 'last_four_digits': '1234',
        'payment_system': 'Visa', 'card_type': 'physical',
    }).get_json()
    assert _resolve_import_card('alfa', user['id'], {})[0].id == card['id']
    duplicate = client.post('/api/banks', headers=headers,
                            json={'name': 'Другой профиль', 'bank_key': 'alfa'})
    assert duplicate.status_code == 409
    invalid = client.put(f"/api/banks/{bank['id']}", headers=headers,
                         json={'bank_key': 'invented'})
    assert invalid.status_code == 400


def test_custom_bank_icon_does_not_establish_integration_identity(client):
    from main import _resolve_rules_bank

    headers = {'Authorization': f'Bearer {login(client)}'}
    bank = client.post('/api/banks', headers=headers,
                       json={'name': 'Custom', 'icon_key': 'tbank'}).get_json()
    assert bank['bank_key'] is None
    assert _resolve_rules_bank('tbank') is None


@pytest.mark.parametrize('emoji', [
    '🦊', '👍🏽', '👨‍👩‍👧‍👦',
    '🏴\U000e0067\U000e0062\U000e0065\U000e006e\U000e0067\U000e007f',
])
def test_emoji_survives_create_update_and_reload(client, emoji):
    headers = {'Authorization': f'Bearer {login(client)}'}
    created = client.post('/api/users', json={'name': 'Тест', 'icon_key': 'person'},
                          headers=headers)
    user_id = created.get_json()['id']
    key = f'emoji:{emoji}'
    response = client.put(f'/api/users/{user_id}',
                          json={'name': 'Тест', 'icon_key': key}, headers=headers)
    assert response.status_code == 200
    assert response.get_json()['icon_key'] == key
    assert client.get('/api/users', headers=headers).get_json()[0]['icon_key'] == key
    assert client.post('/api/users', json={'name': 'Другой', 'icon_key': key},
                       headers=headers).status_code == 201


@pytest.mark.parametrize('key', ['emoji:hello', 'emoji:🦊🦊', 'emoji:', [], {}, None])
def test_invalid_emoji_is_rejected_without_changing_user(client, key):
    headers = {'Authorization': f'Bearer {login(client)}'}
    created = client.post('/api/users', json={'name': 'Тест', 'icon_key': 'girl'},
                          headers=headers).get_json()
    response = client.put(f'/api/users/{created["id"]}',
                          json={'name': 'Изменено', 'icon_key': key}, headers=headers)
    assert response.status_code == 400
    assert client.get('/api/users', headers=headers).get_json() == [created]


def test_entire_emoji_catalogue_fits_existing_schema():
    emoji_keys = [key for key in USER_ICON_KEYS if key.startswith('emoji:')]
    assert len(emoji_keys) == 3953
    assert max(map(len, emoji_keys)) <= 24

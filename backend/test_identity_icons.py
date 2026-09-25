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

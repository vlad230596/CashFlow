from datetime import datetime

from test_auth import client as authenticated_client
from test_auth import login

client = authenticated_client


def test_selection_requires_bank_confirmation(client):
    headers = {'Authorization': f'Bearer {login(client)}'}
    def post(path, data):
        response = client.post('/api/' + path, json=data, headers=headers)
        assert response.status_code in (200, 201)
        return response.get_json()

    bank = post('banks', {'name': 'Т-Банк'})
    user = post('users', {'name': 'Owner'})
    card = post('cards', {
        'payment_system': 'Visa', 'card_type': 'physical',
        'last_four_digits': '1234', 'bank_id': bank['id'], 'user_id': user['id'],
    })
    now = datetime.now()
    category = post('cashback', {
        'name': 'Test', 'start_date': f'{now.year}-01-01T00:00:00',
        'end_date': f'{now.year + 1}-01-01T00:00:00', 'cashback_percent': 10,
        'card_id': card['id'], 'is_selected': True, 'is_bank_confirmed': True,
    })
    assert category['is_bank_confirmed'] is False
    assert client.get('/api/active_cashback', headers=headers).get_json() == []

    imported = {'name': 'Monthly', 'percent': 10, 'selected': True}
    document = {
        'schemaVersion': 1, 'generatedAt': now.isoformat(),
        'banks': [{
            'bankId': 'tbank', 'collectionStatus': 'ready',
            'authenticationStatus': 'authenticated',
            'selection': {'selectedCount': 1, 'maxSelectable': 1},
            'categories': [imported],
        }],
    }
    payload = {'document': document, 'user_id': user['id']}
    post('cashback/import', payload)
    assert client.get('/api/active_cashback', headers=headers).get_json() == []
    imported['confirmed'] = True
    post('cashback/import', payload)
    active = client.get('/api/active_cashback', headers=headers).get_json()
    assert [item['name'] for item in active] == ['Monthly']
    imported['selected'] = False
    imported['confirmed'] = False
    post('cashback/import', payload)
    assert client.get('/api/active_cashback', headers=headers).get_json() == []
    categories = client.get('/api/cashback', headers=headers).get_json()
    monthly = next(item for item in categories if item['name'] == 'Monthly')
    assert monthly['is_selected'] is True
    assert monthly['is_bank_confirmed'] is False

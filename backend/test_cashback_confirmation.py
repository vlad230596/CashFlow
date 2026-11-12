from datetime import datetime, timedelta

from main import CashbackCategory, app, db
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

    with app.app_context():
        db.session.add(CashbackCategory(
            name='Stale overlapping selection',
            start_date=now - timedelta(days=45),
            end_date=now + timedelta(days=45),
            cashback_percent=5,
            card_id=card['id'],
            is_selected=True,
            is_bank_confirmed=True,
        ))
        db.session.commit()

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


def test_ozon_import_keeps_the_category_cap(client):
    """Regression: the cap shown on an Ozon category card must reach the app.

    The extension sends it as `maxCashbackAmount` and in the description; a
    later snapshot from the selection list without the detail sheet must not
    erase it. Values are synthetic.
    """
    headers = {'Authorization': f'Bearer {login(client)}'}

    def post(path, data):
        response = client.post('/api/' + path, json=data, headers=headers)
        assert response.status_code in (200, 201), response.get_json()
        return response.get_json()

    bank = post('banks', {'name': 'Ozon Банк'})
    user = post('users', {'name': 'Owner'})
    post('cards', {
        'payment_system': 'Mir', 'card_type': 'physical',
        'last_four_digits': '4321', 'bank_id': bank['id'], 'user_id': user['id'],
    })
    now = datetime.now()

    def import_categories(categories):
        return post('cashback/import', {'user_id': user['id'], 'document': {
            'schemaVersion': 1, 'generatedAt': now.isoformat(),
            'banks': [{
                'bankId': 'ozon', 'collectionStatus': 'ready',
                'authenticationStatus': 'authenticated',
                'selection': {'selectedCount': 2, 'maxSelectable': 5},
                'categories': categories,
            }],
        }})

    def caps():
        return {
            item['name']: item['max_cashback_amount']
            for item in client.get('/api/cashback', headers=headers).get_json()
        }

    common = {'percent': 5, 'percentLabel': '5%', 'selected': True, 'confirmed': True}
    result = import_categories([
        {**common, 'name': 'Тестовое обучение', 'maxCashbackAmount': 1500,
         'description': 'Тестовые школы и курсы\nКешбэк до 1 500 ₽'},
        # Only the text carries the cap: the server parses it as well.
        {**common, 'name': 'Тестовая химчистка',
         'description': 'Тестовые химчистки\nКешбэк до 1 000 ₽'},
    ])
    assert result['imported_banks'][0]['categories'] == 2
    assert caps() == {'Тестовое обучение': 1500.0, 'Тестовая химчистка': 1000.0}
    education = next(
        item for item in client.get('/api/cashback', headers=headers).get_json()
        if item['name'] == 'Тестовое обучение'
    )
    assert education['description'] == 'Тестовые школы и курсы'

    import_categories([
        {**common, 'name': 'Тестовое обучение', 'description': None},
        {**common, 'name': 'Тестовая химчистка', 'maxCashbackAmount': 800},
    ])
    assert caps() == {'Тестовое обучение': 1500.0, 'Тестовая химчистка': 800.0}

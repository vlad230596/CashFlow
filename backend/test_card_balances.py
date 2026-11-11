"""ZenMoney card balances: secret handling, refresh lease, matching and API roles.

All ZenMoney data here is invented; the network call is always replaced.
"""

import io
import json
import logging
from datetime import timedelta
from urllib.error import HTTPError, URLError

import pytest
from cryptography.fernet import Fernet

import main
import zenmoney
from main import (
    AuthUser,
    Bank,
    BankCard,
    CardUser,
    CardZenmoneyLink,
    ZenmoneyAccount,
    ZenmoneyIntegration,
    _hash_password,
    _utc_now,
    app,
    db,
)

ADMIN_PASSWORD = 'correct horse battery staple'
EDITOR_PASSWORD = 'editor correct horse battery'
VIEWER_PASSWORD = 'another correct horse battery'
TOKEN = 'zm-SYNTHETIC-token-0123456789abcdef'
SECRETS_KEY = Fernet.generate_key().decode('ascii')


def _diff(**overrides):
    """A synthetic ZenMoney diff shaped like /v8/diff/ (invented values)."""
    document = {
        'serverTimestamp': 1_800_000_000,
        'instrument': [
            {'id': 2, 'title': 'Российский рубль', 'shortTitle': 'RUB', 'symbol': '₽',
             'rate': 1, 'changed': 1},
            {'id': 1, 'title': 'Доллар США', 'shortTitle': 'USD', 'symbol': '$',
             'rate': 90, 'changed': 1},
        ],
        'company': [
            {'id': 4624, 'title': 'Тинькофф Банк', 'fullTitle': None, 'changed': 1,
             'deleted': False},
            {'id': 4902, 'title': 'ПАО Сбербанк', 'fullTitle': None, 'changed': 1,
             'deleted': False},
            {'id': 15420, 'title': 'Альфа-Банк', 'fullTitle': None, 'changed': 1,
             'deleted': False},
        ],
        'account': [
            {'id': 'acc-tbank-debit', 'title': 'Tinkoff Black', 'type': 'ccard',
             'company': 4624, 'instrument': 2, 'syncID': ['1111'], 'balance': 15234.5,
             'creditLimit': 0, 'archive': False, 'user': 1, 'changed': 1},
            {'id': 'acc-tbank-credit', 'title': 'Tinkoff Platinum', 'type': 'ccard',
             'company': 4624, 'instrument': 2, 'syncID': ['2222'], 'balance': -20000,
             'creditLimit': 100000, 'archive': False, 'user': 1, 'changed': 1},
            {'id': 'acc-sber', 'title': 'Сбер Visa', 'type': 'ccard', 'company': 4902,
             'instrument': 2, 'syncID': ['3333', '40817810000000003333'], 'balance': 800,
             'creditLimit': 0, 'archive': False, 'user': 1, 'changed': 1},
            {'id': 'acc-dup-a', 'title': 'Карта A', 'type': 'ccard', 'company': None,
             'instrument': 2, 'syncID': ['4444'], 'balance': 1, 'creditLimit': 0,
             'archive': False, 'user': 1, 'changed': 1},
            {'id': 'acc-dup-b', 'title': 'Карта B', 'type': 'ccard', 'company': None,
             'instrument': 2, 'syncID': ['4444'], 'balance': 2, 'creditLimit': 0,
             'archive': False, 'user': 1, 'changed': 1},
            {'id': 'acc-debt', 'title': 'Долги', 'type': 'debt', 'company': None,
             'instrument': 2, 'syncID': None, 'balance': 0, 'creditLimit': 0,
             'archive': False, 'user': 1, 'changed': 1},
        ],
        'transaction': [{'id': 'tx-1', 'income': 0, 'outcome': 100}],
    }
    document.update(overrides)
    return document


class FakeZenMoney:
    def __init__(self, responses=None):
        self.responses = list(responses or [])
        self.calls = []

    def __call__(self, token, *, server_timestamp=0, force_fetch=('account',)):
        self.calls.append({
            'token': token,
            'server_timestamp': server_timestamp,
            'force_fetch': tuple(force_fetch),
        })
        response = self.responses.pop(0) if self.responses else _diff()
        if isinstance(response, Exception):
            raise response
        return response


@pytest.fixture()
def fake_zm(monkeypatch):
    fake = FakeZenMoney()
    monkeypatch.setattr(main, '_zenmoney_fetch_diff', fake)
    return fake


@pytest.fixture()
def client(monkeypatch, fake_zm):
    app.config.update(
        TESTING=True,
        CASHFLOW_SESSION_TTL_HOURS=12,
        CASHFLOW_SECRETS_KEY=SECRETS_KEY,
    )
    with app.app_context():
        db.create_all()
        now = _utc_now()
        for username, password, role in (
            ('admin', ADMIN_PASSWORD, 'admin'),
            ('editor', EDITOR_PASSWORD, 'editor'),
            ('viewer', VIEWER_PASSWORD, 'viewer'),
        ):
            db.session.add(AuthUser(
                username=username,
                password_hash=_hash_password(password),
                role=role,
                auth_enabled=True,
                created_at=now,
                updated_at=now,
            ))
        tbank = Bank(name='Т-Банк', bank_key='tbank')
        sber = Bank(name='Сбер', bank_key='sber')
        alfa = Bank(name='Альфа', bank_key='alfa')
        owner = CardUser(name='Владелец')
        db.session.add_all([tbank, sber, alfa, owner])
        db.session.flush()
        db.session.add_all([
            BankCard(id=1, payment_system='Мир', card_type='physical',
                     last_four_digits='1111', bank_id=tbank.id, user_id=owner.id),
            BankCard(id=2, payment_system='Visa', card_type='physical',
                     last_four_digits='2222', bank_id=tbank.id, user_id=owner.id),
            BankCard(id=3, payment_system='Visa', card_type='physical',
                     last_four_digits='3333', bank_id=sber.id, user_id=owner.id),
            BankCard(id=4, payment_system='Мир', card_type='virtual',
                     last_four_digits='4444', bank_id=alfa.id, user_id=owner.id),
            BankCard(id=5, payment_system='Мир', card_type='virtual',
                     last_four_digits='5555', bank_id=alfa.id, user_id=owner.id),
        ])
        db.session.commit()
        yield app.test_client()
        db.session.remove()
        db.drop_all()
    app.config['CASHFLOW_SECRETS_KEY'] = None


def _login(client, username, password):
    response = client.post(
        '/api/auth/login',
        json={'username': username, 'password': password},
    )
    assert response.status_code == 200
    return {'Authorization': f"Bearer {response.get_json()['access_token']}"}


def _admin(client):
    return _login(client, 'admin', ADMIN_PASSWORD)


def _editor(client):
    return _login(client, 'editor', EDITOR_PASSWORD)


def _viewer(client):
    return _login(client, 'viewer', VIEWER_PASSWORD)


def _set_token(client, token=TOKEN):
    response = client.put('/api/admin/zenmoney/token', headers=_admin(client),
                          json={'token': token})
    assert response.status_code == 200, response.get_json()
    return response.get_json()


def _age_snapshot(minutes):
    integration = db.session.get(ZenmoneyIntegration, 1)
    shift = timedelta(minutes=minutes)
    for field in ('last_attempt_at', 'last_success_at', 'last_error_at'):
        value = getattr(integration, field)
        if value is not None:
            setattr(integration, field, value - shift)
    for account in ZenmoneyAccount.query.all():
        account.fetched_at = account.fetched_at - shift
    db.session.commit()


# --- secret handling ---------------------------------------------------------


def test_encryption_round_trip_and_wrong_key():
    ciphertext = zenmoney.encrypt_secret(SECRETS_KEY, TOKEN)
    assert TOKEN not in ciphertext
    assert zenmoney.decrypt_secret(SECRETS_KEY, ciphertext) == TOKEN
    with pytest.raises(zenmoney.SecretUnreadable):
        zenmoney.decrypt_secret(Fernet.generate_key().decode(), ciphertext)
    with pytest.raises(zenmoney.SecretsUnavailable):
        zenmoney.secret_box('')
    with pytest.raises(zenmoney.SecretsUnavailable):
        zenmoney.secret_box('not-a-fernet-key')


def test_token_is_stored_encrypted_and_never_returned_or_logged(client, fake_zm, caplog):
    caplog.set_level(logging.DEBUG)
    fake_zm.responses = [_diff(), zenmoney.TokenRejected('ZenMoney rejected the token (HTTP 401)')]
    status = _set_token(client)
    assert status['status'] == 'ok'
    assert status['token_set'] is True
    assert fake_zm.calls[0]['token'] == TOKEN
    assert fake_zm.calls[0]['server_timestamp'] == 0

    stored = db.session.get(ZenmoneyIntegration, 1).token_ciphertext
    assert TOKEN not in stored
    assert zenmoney.decrypt_secret(SECRETS_KEY, stored) == TOKEN

    bodies = [
        client.get('/api/admin/zenmoney', headers=_admin(client)).get_data(as_text=True),
        client.get('/api/card-balances', headers=_viewer(client)).get_data(as_text=True),
        client.get('/api/card-balances/mapping',
                   headers=_editor(client)).get_data(as_text=True),
        client.post('/api/card-balances/refresh',
                    headers=_editor(client)).get_data(as_text=True),
    ]
    # The second refresh was throttled; force a failing call past the interval.
    _age_snapshot(1)
    bodies.append(client.post('/api/card-balances/refresh',
                              headers=_editor(client)).get_data(as_text=True))
    for body in bodies:
        assert TOKEN not in body
        assert stored not in body
    assert 'token_invalid' in bodies[-1]
    assert TOKEN not in caplog.text
    assert 'ZenMoney refresh failed: token_invalid' in caplog.text


def test_missing_secrets_key_reports_not_configured(client, fake_zm):
    app.config['CASHFLOW_SECRETS_KEY'] = None
    status = client.get('/api/admin/zenmoney', headers=_admin(client)).get_json()
    assert status['status'] == 'not_configured'
    assert status['configured'] is False
    response = client.put('/api/admin/zenmoney/token', headers=_admin(client),
                          json={'token': TOKEN})
    assert response.status_code == 503
    assert response.get_json()['error'] == 'secrets_not_configured'
    balances = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert balances['balances'] == []
    assert balances['integration']['status'] == 'not_configured'
    assert fake_zm.calls == []


def test_role_checks(client):
    viewer, editor = _viewer(client), _editor(client)
    assert client.get('/api/admin/zenmoney', headers=editor).status_code == 403
    assert client.put('/api/admin/zenmoney/token', headers=editor,
                      json={'token': TOKEN}).status_code == 403
    assert client.delete('/api/admin/zenmoney/token', headers=editor).status_code == 403
    assert client.get('/api/card-balances/mapping', headers=viewer).status_code == 403
    assert client.put('/api/card-balances/mapping/1', headers=viewer,
                      json={'account_id': None}).status_code == 403
    assert client.post('/api/card-balances/refresh', headers=viewer).status_code == 403
    assert client.get('/api/card-balances', headers=viewer).status_code == 200
    assert client.get('/api/card-balances').status_code == 401
    assert client.get('/api/card-balances/mapping', headers=editor).status_code == 200


def test_invalid_token_input_is_rejected(client):
    admin = _admin(client)
    for token in ('', '   ', 'two words', 'x' * 5000):
        response = client.put('/api/admin/zenmoney/token', headers=admin, json={'token': token})
        assert response.status_code == 400


# --- parsing -----------------------------------------------------------------


def test_parse_diff_keeps_accounts_and_references_only():
    parsed = zenmoney.parse_diff(_diff(deletion=[{'id': 'acc-dup-b', 'object': 'account'}]))
    ids = [account['id'] for account in parsed['accounts']]
    assert ids == ['acc-tbank-debit', 'acc-tbank-credit', 'acc-sber', 'acc-dup-a']
    credit = parsed['accounts'][1]
    assert str(credit['balance']) == '-20000.00'
    assert str(credit['credit_limit']) == '100000.00'
    assert parsed['instruments'][2] == 'RUB'
    assert parsed['companies'][4902] == 'ПАО Сбербанк'
    assert parsed['server_timestamp'] == 1_800_000_000
    assert 'transaction' not in parsed
    assert str(zenmoney.available_amount('ccard', credit['balance'],
                                         credit['credit_limit'])) == '80000.00'
    assert str(zenmoney.available_amount('checking', credit['balance'],
                                         credit['credit_limit'])) == '-20000.00'


def test_fetch_diff_maps_http_errors_without_leaking_the_token():
    def opener_raising(error):
        def opener(request, timeout):
            assert request.get_header('Authorization') == f'Bearer {TOKEN}'
            body = json.loads(request.data)
            assert body['forceFetch'] == ['account']
            assert body['serverTimestamp'] == 5
            raise error
        return opener

    cases = [
        (HTTPError('u', 401, 'Unauthorized', {}, io.BytesIO(b'')), zenmoney.TokenRejected),
        (HTTPError('u', 503, 'Unavailable', {}, io.BytesIO(b'')), zenmoney.UpstreamFailure),
        (URLError('timed out'), zenmoney.NetworkFailure),
        (TimeoutError(), zenmoney.NetworkFailure),
    ]
    for error, expected in cases:
        with pytest.raises(expected) as raised:
            zenmoney.fetch_diff(TOKEN, server_timestamp=5, opener=opener_raising(error))
        assert TOKEN not in str(raised.value)

    class Response(io.BytesIO):
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    ok = zenmoney.fetch_diff(TOKEN, opener=lambda request, timeout: Response(
        json.dumps(_diff()).encode()))
    assert ok['serverTimestamp'] == 1_800_000_000
    with pytest.raises(zenmoney.TokenRejected):
        zenmoney.fetch_diff(TOKEN, opener=lambda request, timeout: Response(
            b'{"error": {"message": "Invalid token"}}'))
    with pytest.raises(zenmoney.UpstreamFailure):
        zenmoney.fetch_diff(TOKEN, opener=lambda request, timeout: Response(b'<html>'))


# --- matching ----------------------------------------------------------------


def test_company_titles_map_to_bank_keys():
    assert zenmoney.bank_key_for_company('Тинькофф Банк') == 'tbank'
    assert zenmoney.bank_key_for_company('ПАО Сбербанк') == 'sber'
    assert zenmoney.bank_key_for_company('Банк ВТБ (ПАО)') == 'vtb'
    assert zenmoney.bank_key_for_company('Абсолют Банк') is None
    assert zenmoney.bank_key_for_company(None) is None


def test_suggestions_and_ambiguity():
    accounts = [
        {'id': 'a', 'sync_ids': ['1111'], 'company_bank_key': 'tbank'},
        {'id': 'b', 'sync_ids': ['40817810000000001111'], 'company_bank_key': 'sber'},
        {'id': 'c', 'sync_ids': ['1111'], 'company_bank_key': None, 'archived': True},
        {'id': 'd', 'sync_ids': ['9999'], 'company_bank_key': 'tbank'},
    ]
    suggestions = zenmoney.suggest_accounts(
        {'last_four_digits': '1111', 'bank_key': 'tbank'}, accounts)
    assert suggestions == [
        {'account_id': 'a', 'bank_match': True},
        {'account_id': 'b', 'bank_match': False},
    ]
    assert zenmoney.unambiguous_match(suggestions) == 'a'
    two_unknown = [{'account_id': 'x', 'bank_match': None},
                   {'account_id': 'y', 'bank_match': None}]
    assert zenmoney.unambiguous_match(two_unknown) is None
    assert zenmoney.unambiguous_match([{'account_id': 'x', 'bank_match': None}]) == 'x'
    assert zenmoney.unambiguous_match([{'account_id': 'x', 'bank_match': False}]) is None


def test_refresh_auto_links_only_unambiguous_cards(client):
    _set_token(client)
    links = {link.card_id: link for link in CardZenmoneyLink.query.all()}
    assert links[1].account_id == 'acc-tbank-debit' and links[1].source == 'auto'
    assert links[2].account_id == 'acc-tbank-credit'
    assert links[3].account_id == 'acc-sber'
    assert 4 not in links  # two accounts carry 4444
    assert 5 not in links  # nothing carries 5555

    mapping = client.get('/api/card-balances/mapping', headers=_editor(client)).get_json()
    card4 = next(card for card in mapping['cards'] if card['card_id'] == 4)
    assert card4['ambiguous'] is True
    assert {item['account_id'] for item in card4['suggestions']} == {'acc-dup-a', 'acc-dup-b'}
    assert 'acc-debt' not in {account['id'] for account in mapping['accounts']}


def test_editor_confirms_changes_and_unlinks(client):
    _set_token(client)
    editor = _editor(client)
    response = client.put('/api/card-balances/mapping/4', headers=editor,
                          json={'account_id': 'acc-dup-b'})
    assert response.status_code == 200
    assert response.get_json()['link']['source'] == 'manual'
    assert client.put('/api/card-balances/mapping/4', headers=editor,
                      json={'account_id': 'nope'}).status_code == 404
    assert client.put('/api/card-balances/mapping/99', headers=editor,
                      json={'account_id': None}).status_code == 404
    # An explicit "no account" survives later refreshes.
    assert client.put('/api/card-balances/mapping/1', headers=editor,
                      json={'account_id': None}).status_code == 200
    _age_snapshot(20)
    balances = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    by_card = {item['card_id']: item for item in balances['balances']}
    assert 1 not in by_card
    assert by_card[4]['account_id'] == 'acc-dup-b'
    assert db.session.get(CardZenmoneyLink, 1).account_id is None
    # Reset to automatic matching.
    assert client.delete('/api/card-balances/mapping/1', headers=editor).status_code == 204
    assert db.session.get(CardZenmoneyLink, 1) is None


# --- balances and refresh ----------------------------------------------------


def test_balances_payload_has_fetched_at_and_credit_available(client):
    _set_token(client)
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['status'] == 'ok'
    assert payload['integration']['refresh_outcome'] == 'not_due'
    by_card = {item['card_id']: item for item in payload['balances']}
    assert set(by_card) == {1, 2, 3}
    assert by_card[1]['balance'] == '15234.50'
    assert by_card[1]['currency'] == 'RUB'
    assert by_card[1]['fetched_at'] is not None
    assert by_card[2]['available'] == '80000.00'
    assert by_card[2]['credit_limit'] == '100000.00'


def test_no_token_shows_nothing(client, fake_zm):
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['status'] == 'no_token'
    assert payload['balances'] == []
    assert fake_zm.calls == []


def test_stale_snapshot_refreshes_on_read_and_fresh_does_not(client, fake_zm):
    _set_token(client)
    assert len(fake_zm.calls) == 1
    client.get('/api/card-balances', headers=_viewer(client))
    assert len(fake_zm.calls) == 1
    _age_snapshot(16)
    fake_zm.responses = [_diff(account=[dict(_diff()['account'][0], balance=99.99)],
                               serverTimestamp=1_800_000_500)]
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['refresh_outcome'] == 'refreshed'
    assert len(fake_zm.calls) == 2
    # Incremental diff from the stored server timestamp.
    assert fake_zm.calls[1]['server_timestamp'] == 1_800_000_000
    by_card = {item['card_id']: item for item in payload['balances']}
    assert by_card[1]['balance'] == '99.99'
    # Accounts absent from a forced account fetch were deleted in ZenMoney.
    assert 2 not in by_card
    assert db.session.get(ZenmoneyAccount, 'acc-sber').missing_since is not None
    assert db.session.get(ZenmoneyIntegration, 1).server_timestamp == 1_800_000_500


def test_unknown_references_are_force_fetched_once(client, fake_zm):
    _set_token(client)
    _age_snapshot(16)
    new_account = {'id': 'acc-new', 'title': 'Новая', 'type': 'ccard', 'company': 777,
                   'instrument': 3, 'syncID': ['5555'], 'balance': 10, 'creditLimit': 0,
                   'archive': False}
    fake_zm.responses = [
        _diff(account=[*_diff()['account'], new_account], company=[], instrument=[]),
        _diff(account=[], company=[{'id': 777, 'title': 'Альфа-Банк'}],
              instrument=[{'id': 3, 'shortTitle': 'EUR'}]),
    ]
    client.post('/api/card-balances/refresh', headers=_editor(client))
    assert fake_zm.calls[-1]['force_fetch'] == ('instrument', 'company')
    account = db.session.get(ZenmoneyAccount, 'acc-new')
    assert account.currency == 'EUR' and account.company_title == 'Альфа-Банк'
    # Known references were kept from the stored snapshot.
    assert db.session.get(ZenmoneyAccount, 'acc-sber').company_title == 'ПАО Сбербанк'
    assert db.session.get(CardZenmoneyLink, 5).account_id == 'acc-new'


def test_token_rejection_marks_invalid_keeps_data_and_stops_auto_refresh(client, fake_zm):
    _set_token(client)
    _age_snapshot(16)
    fake_zm.responses = [zenmoney.TokenRejected('ZenMoney rejected the token (HTTP 401)')]
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['status'] == 'token_invalid'
    assert payload['integration']['last_error']['kind'] == 'token_invalid'
    assert len(payload['balances']) == 3  # old balances with their old fetched_at
    calls = len(fake_zm.calls)
    _age_snapshot(60)
    client.get('/api/card-balances', headers=_viewer(client))
    assert len(fake_zm.calls) == calls  # no automatic retries with a rejected token
    # Re-entering the token clears the state and fetches the full diff again.
    status = _set_token(client, TOKEN + 'x')
    assert status['status'] == 'ok'
    assert fake_zm.calls[-1]['server_timestamp'] == 0


def test_network_error_keeps_old_snapshot_and_backs_off(client, fake_zm):
    _set_token(client)
    before = client.get('/api/card-balances?refresh=never',
                        headers=_viewer(client)).get_json()['balances']
    _age_snapshot(16)
    fake_zm.responses = [zenmoney.NetworkFailure('ZenMoney is unreachable (timeout)')]
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['status'] == 'error'
    assert payload['integration']['last_error']['kind'] == 'network'
    after = payload['balances']
    assert [item['balance'] for item in after] == [item['balance'] for item in before]
    assert all(item['fetched_at'] < payload['integration']['last_attempt_at'] for item in after)
    calls = len(fake_zm.calls)
    # Within the error back-off window automatic reads do not call ZenMoney.
    _age_snapshot(2)
    client.get('/api/card-balances', headers=_viewer(client))
    assert len(fake_zm.calls) == calls
    _age_snapshot(4)
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert len(fake_zm.calls) == calls + 1
    assert payload['integration']['status'] == 'ok'
    assert payload['integration']['last_error'] is None


def test_refresh_lease_prevents_stampede(client, fake_zm):
    _set_token(client)
    _age_snapshot(16)
    integration = db.session.get(ZenmoneyIntegration, 1)
    integration.refresh_started_at = _utc_now()  # another worker is fetching
    db.session.commit()
    calls = len(fake_zm.calls)
    for _ in range(3):
        payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
        assert payload['integration']['refresh_outcome'] == 'busy'
        assert payload['integration']['refreshing'] is True
    assert len(fake_zm.calls) == calls
    # A lease abandoned by a crashed worker is taken over after it expires.
    integration = db.session.get(ZenmoneyIntegration, 1)
    integration.refresh_started_at = _utc_now() - timedelta(minutes=3)
    db.session.commit()
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['refresh_outcome'] == 'refreshed'
    assert db.session.get(ZenmoneyIntegration, 1).refresh_started_at is None


def test_due_check_race_cannot_call_twice(client, fake_zm):
    """A caller that decided "due" before another refresh finished is refused."""
    _set_token(client)
    calls = len(fake_zm.calls)
    # Pretend the due check passed although the last attempt was just now.
    original = main._zenmoney_refresh_due
    main._zenmoney_refresh_due = lambda *args, **kwargs: True
    try:
        assert main._refresh_zenmoney(force=False) == 'busy'
    finally:
        main._zenmoney_refresh_due = original
    assert len(fake_zm.calls) == calls


def test_manual_refresh_is_throttled(client, fake_zm):
    _set_token(client)
    editor = _editor(client)
    payload = client.post('/api/card-balances/refresh', headers=editor).get_json()
    assert payload['integration']['refresh_outcome'] == 'not_due'
    _age_snapshot(1)
    payload = client.post('/api/card-balances/refresh', headers=editor).get_json()
    assert payload['integration']['refresh_outcome'] == 'refreshed'


def test_removing_token_hides_balances(client, fake_zm):
    _set_token(client)
    response = client.delete('/api/admin/zenmoney/token', headers=_admin(client))
    assert response.get_json()['status'] == 'no_token'
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['balances'] == []
    assert ZenmoneyAccount.query.count() == 0


def test_unreadable_ciphertext_asks_for_reentry(client, fake_zm):
    _set_token(client)
    app.config['CASHFLOW_SECRETS_KEY'] = Fernet.generate_key().decode()
    _age_snapshot(16)
    payload = client.get('/api/card-balances', headers=_viewer(client)).get_json()
    assert payload['integration']['status'] == 'token_invalid'
    assert payload['integration']['last_error']['kind'] == 'token_unreadable'


def test_deleting_a_card_removes_its_link(client):
    _set_token(client)
    assert client.delete('/api/cards/1', headers=_admin(client)).status_code == 204
    assert db.session.get(CardZenmoneyLink, 1) is None

"""ZenMoney balance integration: token encryption, diff fetch, parsing and card matching.

This module has no Flask or ORM dependency. It never logs, returns or embeds the
ZenMoney token in exception messages; callers store only the ciphertext.
"""

import json
import socket
import time
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from cryptography.fernet import Fernet, InvalidToken

from bank_identity import BANK_ALIASES, bank_key_for_name, normalized_bank_name

ZENMONEY_DIFF_URL = 'https://api.zenmoney.ru/v8/diff/'
# Two short calls at most per refresh keep a balance read under the app's 15 s limit.
FETCH_TIMEOUT_SECONDS = 6
MAX_RESPONSE_BYTES = 32 * 1024 * 1024
TOKEN_MAX_LENGTH = 4096
# Pseudo-accounts that never correspond to a payment card.
IGNORED_ACCOUNT_TYPES = {'debt'}
CENT = Decimal('0.01')


# ---------------------------------------------------------------------------
# Secret storage
# ---------------------------------------------------------------------------


class SecretsUnavailable(Exception):
    """CASHFLOW_SECRETS_KEY is missing or is not a valid Fernet key."""


class SecretUnreadable(Exception):
    """The stored ciphertext cannot be decrypted with the current key."""


def secret_box(key):
    """Return a Fernet instance for the configured key or raise SecretsUnavailable."""
    if not key or not str(key).strip():
        raise SecretsUnavailable('CASHFLOW_SECRETS_KEY is not set')
    try:
        return Fernet(str(key).strip().encode('ascii'))
    except (ValueError, TypeError, UnicodeEncodeError) as error:
        raise SecretsUnavailable('CASHFLOW_SECRETS_KEY is not a valid Fernet key') from error


def encrypt_secret(key, plaintext):
    return secret_box(key).encrypt(plaintext.encode('utf-8')).decode('ascii')


def decrypt_secret(key, ciphertext):
    box = secret_box(key)
    try:
        return box.decrypt(ciphertext.encode('ascii')).decode('utf-8')
    except (InvalidToken, ValueError, UnicodeError):
        raise SecretUnreadable('The stored secret cannot be decrypted') from None


def validated_token(value):
    token = str(value or '').strip()
    if not token:
        raise ValueError('token is required')
    if len(token) > TOKEN_MAX_LENGTH or any(ch.isspace() for ch in token):
        raise ValueError('token must be a single line without spaces')
    return token


# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------


class ZenMoneyError(Exception):
    kind = 'upstream'


class TokenRejected(ZenMoneyError):
    kind = 'token_invalid'


class NetworkFailure(ZenMoneyError):
    kind = 'network'


class UpstreamFailure(ZenMoneyError):
    kind = 'upstream'


def fetch_diff(token, *, server_timestamp=0, force_fetch=('account',), opener=urlopen,
               now=time.time, timeout=FETCH_TIMEOUT_SECONDS):
    """POST the ZenMoney diff request and return the decoded JSON object.

    Exception messages are composed here and never contain the token or the
    upstream response body.
    """
    body = {
        'currentClientTimestamp': int(now()),
        'serverTimestamp': int(server_timestamp or 0),
        'forceFetch': list(force_fetch),
    }
    request = Request(
        ZENMONEY_DIFF_URL,
        data=json.dumps(body).encode('utf-8'),
        method='POST',
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'CashFlow balance sync/1.0',
        },
    )
    try:
        with opener(request, timeout=timeout) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except HTTPError as error:
        if error.code in (401, 403):
            raise TokenRejected(f'ZenMoney rejected the token (HTTP {error.code})') from None
        raise UpstreamFailure(f'ZenMoney answered HTTP {error.code}') from None
    except (URLError, socket.timeout, TimeoutError, ConnectionError, OSError) as error:
        reason = getattr(error, 'reason', None) or type(error).__name__
        if isinstance(reason, BaseException):
            reason = type(reason).__name__
        raise NetworkFailure(f'ZenMoney is unreachable ({reason})') from None
    if len(raw) > MAX_RESPONSE_BYTES:
        raise UpstreamFailure('ZenMoney response is too large')
    try:
        payload = json.loads(raw.decode('utf-8'))
    except (UnicodeDecodeError, ValueError):
        raise UpstreamFailure('ZenMoney returned malformed JSON') from None
    if not isinstance(payload, dict):
        raise UpstreamFailure('ZenMoney returned an unexpected document')
    if payload.get('error'):
        error = payload['error']
        text = json.dumps(error, ensure_ascii=False).lower() if error else ''
        if any(word in text for word in ('token', 'unauthorized', 'auth')):
            raise TokenRejected('ZenMoney rejected the token')
        raise UpstreamFailure('ZenMoney reported an error')
    return payload


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def _money(value):
    if value is None or isinstance(value, bool):
        return Decimal('0.00')
    try:
        return Decimal(str(value)).quantize(CENT, rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError):
        return Decimal('0.00')


def _int_or_none(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _sync_ids(value):
    if not isinstance(value, list):
        return []
    result = []
    for item in value:
        text = str(item or '').strip()
        if text and text not in result:
            result.append(text[:32])
    return result


def parse_diff(payload):
    """Extract only accounts and the companies/instruments they reference.

    Returns a dict with `server_timestamp`, `accounts` (list), `deleted_ids`,
    `companies` ({id: title}) and `instruments` ({id: code}).
    """
    companies = {}
    for item in payload.get('company') or []:
        if isinstance(item, dict) and _int_or_none(item.get('id')) is not None:
            title = str(item.get('title') or item.get('fullTitle') or '').strip()
            companies[int(item['id'])] = title[:200]
    instruments = {}
    for item in payload.get('instrument') or []:
        if isinstance(item, dict) and _int_or_none(item.get('id')) is not None:
            code = str(item.get('shortTitle') or '').strip().upper()
            instruments[int(item['id'])] = code[:8]

    deleted_ids = {
        str(item.get('id'))
        for item in payload.get('deletion') or []
        if isinstance(item, dict) and item.get('object') == 'account' and item.get('id')
    }

    accounts = []
    for item in payload.get('account') or []:
        if not isinstance(item, dict) or not item.get('id'):
            continue
        account_type = str(item.get('type') or '').strip()[:16]
        if account_type in IGNORED_ACCOUNT_TYPES:
            continue
        account_id = str(item['id'])[:64]
        if account_id in deleted_ids:
            continue
        accounts.append({
            'id': account_id,
            'title': str(item.get('title') or '').strip()[:200] or 'Счёт',
            'type': account_type or 'checking',
            'company_id': _int_or_none(item.get('company')),
            'instrument_id': _int_or_none(item.get('instrument')),
            'sync_ids': _sync_ids(item.get('syncID')),
            'balance': _money(item.get('balance')),
            'credit_limit': _money(item.get('creditLimit')),
            'archived': bool(item.get('archive')),
        })
    return {
        'server_timestamp': _int_or_none(payload.get('serverTimestamp')),
        'accounts': accounts,
        'deleted_ids': deleted_ids,
        'companies': companies,
        'instruments': instruments,
    }


def available_amount(account_type, balance, credit_limit):
    """Money that can be spent now: a credit card adds its unused limit."""
    if account_type == 'ccard' and credit_limit and credit_limit > 0:
        return balance + credit_limit
    return balance


# ---------------------------------------------------------------------------
# Card matching
# ---------------------------------------------------------------------------

_ALIAS_FRAGMENTS = {
    key: tuple(
        fragment
        for fragment in {normalized_bank_name(alias) for alias in aliases}
        # "тбанк" would also match «Абсолют Банк»; generic *банк aliases match only exactly.
        if len(fragment) >= 3 and not fragment.endswith(('банк', 'bank'))
    )
    for key, aliases in BANK_ALIASES.items()
}


def bank_key_for_company(title):
    """Map a ZenMoney company title such as «ПАО Сбербанк» to a CashFlow bank key."""
    if not title:
        return None
    exact = bank_key_for_name(title)
    if exact:
        return exact
    normalized = normalized_bank_name(title)
    matches = {
        key
        for key, fragments in _ALIAS_FRAGMENTS.items()
        if any(fragment in normalized for fragment in fragments)
    }
    return next(iter(matches)) if len(matches) == 1 else None


def suggest_accounts(card, accounts):
    """Rank ZenMoney accounts for one card.

    `card` has `last_four_digits` and `bank_key`; each account has `id`,
    `sync_ids`, `company_bank_key`, `archived` and `missing`. Only accounts whose
    syncID contains the card's last four digits are suggested. `bank_match` is
    True/False when both sides know their bank, otherwise None.
    """
    digits = str(card.get('last_four_digits') or '').strip()
    if len(digits) != 4:
        return []
    card_bank = card.get('bank_key')
    suggestions = []
    for account in accounts:
        if account.get('missing') or account.get('archived'):
            continue
        if not any(sync_id.endswith(digits) for sync_id in account.get('sync_ids') or []):
            continue
        account_bank = account.get('company_bank_key')
        bank_match = None if not card_bank or not account_bank else card_bank == account_bank
        suggestions.append({'account_id': account['id'], 'bank_match': bank_match})
    rank = {True: 0, None: 1, False: 2}
    suggestions.sort(key=lambda item: (rank[item['bank_match']], item['account_id']))
    return suggestions


def unambiguous_match(suggestions):
    """Return the one account that can be linked automatically, or None."""
    confirmed = [item for item in suggestions if item['bank_match'] is True]
    if len(confirmed) == 1:
        return confirmed[0]['account_id']
    if confirmed:
        return None
    plausible = [item for item in suggestions if item['bank_match'] is None]
    if len(plausible) == 1 and len(suggestions) == 1:
        return plausible[0]['account_id']
    return None

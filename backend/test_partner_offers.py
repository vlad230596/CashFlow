from datetime import datetime, timezone

import pytest

import main as main_module
from main import (
    AuthUser,
    Bank,
    CardUser,
    PartnerOffer,
    PartnerOfferImportRun,
    PartnerOfferPreference,
    PartnerOfferSnapshot,
    _fetch_partner_icon,
    _hash_password,
    _partner_limit_from_text,
    _utc_now,
    app,
    db,
)


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(main_module, '_utc_now', lambda: datetime(2026, 9, 20, tzinfo=timezone.utc))
    app.config.update(TESTING=True, CASHFLOW_SESSION_TTL_HOURS=12)
    with app.app_context():
        db.create_all()
        now = _utc_now()
        db.session.add_all(
            [
                AuthUser(
                    username="admin",
                    password_hash=_hash_password("correct horse battery staple"),
                    role="admin",
                    auth_enabled=True,
                    created_at=now,
                    updated_at=now,
                ),
                AuthUser(
                    username="viewer",
                    password_hash=_hash_password("another correct horse battery"),
                    role="viewer",
                    auth_enabled=True,
                    created_at=now,
                    updated_at=now,
                ),
                Bank(name="Т-Банк"),
                CardUser(name="Владелец банковского профиля"),
            ]
        )
        db.session.commit()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def _login(client, username, password):
    response = client.post(
        "/api/auth/login",
        json={
            "username": username,
            "password": password,
        },
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.get_json()['access_token']}"}


def _document(offers):
    return {
        "schemaVersion": 1,
        "generatedAt": "2026-09-16T08:00:00Z",
        "banks": [
            {
                "bankId": "tbank",
                "collectedAt": "2026-09-16T07:59:00Z",
                "extendedOffers": offers,
                "extendedSummary": {
                    "collectedAt": "2026-09-16T07:59:00Z",
                    "previewCount": len(offers),
                    "errors": [],
                },
            }
        ],
    }


def _offer(source_id="tbank:355589"):
    return {
        "id": source_id,
        "name": "Самокат",
        "offerKind": "cashback",
        "percent": 9,
        "rateLabel": "Кэшбэк до 9%",
        "expirationLabel": "До 30 сентября",
        "description": "Доставка продуктов",
        "conditions": "Максимум — 1 200 бонусов",
        "limits": ["Максимум — 1 200 бонусов"],
        "maxCashbackAmount": 1200,
        "detailsStatus": "complete",
        "detailCollectedAt": "2026-09-16T07:58:00Z",
        "sourceUrl": "https://example.test/offers/355589",
    }


def _import(client, headers, offers, complete=False):
    return client.post(
        "/api/partner-offers/import",
        headers=headers,
        json={
            "card_user_id": 1,
            "document": _document(offers),
            "complete_bank_ids": ["tbank"] if complete else [],
            "collector_version": "test-1",
        },
    )


def test_import_accepts_extension_calendar_dates(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    raw = {**_offer(), 'startDate': '01.10.2026', 'endDate': '31.10.2026'}
    response = _import(client, admin, [raw])
    assert response.status_code == 200, response.get_json()
    assert _import(client, admin, [raw]).status_code == 200
    with app.app_context():
        snapshot = PartnerOfferSnapshot.query.one()
        assert main_module._as_utc(snapshot.starts_at) == datetime(
            2026, 9, 30, 21, tzinfo=timezone.utc,
        )
        assert main_module._as_utc(snapshot.ends_at) == datetime(
            2026, 10, 31, 21, tzinfo=timezone.utc,
        )


def test_import_rejects_impossible_calendar_date(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    response = _import(client, admin, [{**_offer(), 'endDate': '31.02.2026'}])
    assert response.status_code == 400
    with app.app_context():
        assert PartnerOffer.query.count() == 0
        assert PartnerOfferSnapshot.query.count() == 0


def test_limit_parser_preserves_unit_and_scope():
    assert _partner_limit_from_text("1000 бонусов на покупку") == (
        "max_cashback",
        1000.0,
        "bonus",
        "purchase",
    )
    assert _partner_limit_from_text("Не более 5000 баллов в месяц") == (
        "max_cashback",
        5000.0,
        "points",
        "month",
    )
    assert _partner_limit_from_text("Минимальная сумма 400 ₽") == (
        "minimum_purchase",
        400.0,
        "RUB",
        "unknown",
    )


def test_deadline_filter_is_default_and_all_results_are_paginated(client, monkeypatch):
    admin = _login(client, 'admin', 'correct horse battery staple')
    expired = {**_offer('expired'), 'expirationLabel': 'Последний день'}
    unknown = {**_offer('unknown'), 'expirationLabel': None}
    upcoming = {**_offer('upcoming'), 'startDate': '2026-09-25T00:00:00Z'}
    assert _import(client, admin, [expired, unknown, upcoming]).status_code == 200
    payload = client.get('/api/partner-offers', headers=admin).get_json()
    assert payload['total'] == 1
    assert payload['items'][0]['snapshot']['ends_at'] is None
    all_rows = client.get(
        '/api/partner-offers?active_only=false&limit=1&offset=1', headers=admin,
    ).get_json()
    assert all_rows['total'] == 3
    assert len(all_rows['items']) == 1
    assert client.get('/api/partner-offers?active_only=oops', headers=admin).status_code == 400
    monkeypatch.setattr(
        main_module, '_utc_now',
        lambda: datetime(2026, 9, 16, 21, tzinfo=timezone.utc),
    )
    # End at midnight Moscow is exclusive, even at the exact boundary.
    assert client.get('/api/partner-offers', headers=admin).get_json()['total'] == 1


def test_reimport_uses_file_date_and_preserves_preferences(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    raw = {**_offer(), 'expirationLabel': 'Последний день'}
    assert _import(client, admin, [raw]).status_code == 200
    assert _import(client, admin, [raw]).status_code == 200
    with app.app_context():
        assert PartnerOfferSnapshot.query.count() == 1
        snapshot = PartnerOfferSnapshot.query.one()
        assert main_module._as_utc(snapshot.ends_at) == datetime(
            2026, 9, 16, 21, tzinfo=timezone.utc,
        )
    document = _document([raw])
    document['generatedAt'] = '2026-09-17T08:00:00Z'
    response = client.post('/api/partner-offers/import', headers=admin, json={
        'card_user_id': 1, 'document': document,
    })
    assert response.status_code == 200
    with app.app_context():
        assert PartnerOffer.query.count() == 1
        assert PartnerOfferSnapshot.query.count() == 2


def test_legacy_repair_is_preview_by_default(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    assert _import(client, admin, [_offer()]).status_code == 200
    with app.app_context():
        snapshot = PartnerOfferSnapshot.query.one()
        snapshot.ends_at = None
        db.session.commit()
    runner = app.test_cli_runner()
    assert runner.invoke(args=['repair-partner-deadlines']).exit_code == 0
    with app.app_context():
        assert PartnerOfferSnapshot.query.one().ends_at is None
    result = runner.invoke(args=['repair-partner-deadlines', '--apply'])
    assert result.exit_code == 0
    assert 'Repaired: 1' in result.output
    assert 'Repaired: 0' in runner.invoke(
        args=['repair-partner-deadlines', '--apply'],
    ).output


def test_purge_removes_only_offers_without_a_known_deadline(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    undated = {**_offer('tbank:1'), 'expirationLabel': None}
    dated = _offer('tbank:2')
    assert _import(client, admin, [undated, dated]).status_code == 200
    with app.app_context():
        undated_id = PartnerOffer.query.filter_by(source_key='tbank:1').one().id
    viewer = _login(client, 'viewer', 'another correct horse battery')
    assert client.put(f'/api/partner-offers/{undated_id}/preference', headers=viewer,
                      json={'rating': 'hidden'}).status_code == 200
    runner = app.test_cli_runner()

    preview = runner.invoke(args=['purge-undated-partner-offers'])

    assert preview.exit_code == 0, preview.output
    assert 'Would delete: 1 (available: 1); deadline recoverable, kept: 0' in preview.output
    with app.app_context():
        assert PartnerOffer.query.count() == 2

    result = runner.invoke(args=['purge-undated-partner-offers', '--apply'])

    assert result.exit_code == 0, result.output
    assert 'Deleted: 1' in result.output
    with app.app_context():
        assert [offer.source_key for offer in PartnerOffer.query] == ['tbank:2']
        assert PartnerOfferSnapshot.query.count() == 1
        assert PartnerOfferPreference.query.count() == 0


def test_purge_keeps_offers_whose_deadline_can_be_repaired(client):
    admin = _login(client, 'admin', 'correct horse battery staple')
    assert _import(client, admin, [_offer()]).status_code == 200
    with app.app_context():
        PartnerOfferSnapshot.query.one().ends_at = None
        db.session.commit()

    result = app.test_cli_runner().invoke(args=['purge-undated-partner-offers', '--apply'])

    assert 'Deleted: 0 (available: 0); deadline recoverable, kept: 1' in result.output
    with app.app_context():
        assert PartnerOffer.query.count() == 1


def test_partner_icon_uses_same_origin_proxy(client, monkeypatch):
    admin = _login(client, "admin", "correct horse battery staple")
    offer = _offer()
    offer["iconUrl"] = "https://cdn1.ozone.ru/icon.webp"
    assert _import(client, admin, [offer]).status_code == 200

    payload = client.get("/api/partner-offers", headers=admin).get_json()
    assert payload["items"][0]["snapshot"]["icon_url"] == (
        "http://localhost/api/partner-offers/1/icon"
    )

    class FakeUpstream:
        headers = {"Content-Type": "application/octet-stream"}

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return None

        def geturl(self):
            return offer["iconUrl"]

        def read(self, _limit):
            return b"RIFF\x00\x00\x00\x00WEBPicon"

    _fetch_partner_icon.cache_clear()
    monkeypatch.setattr(main_module, "urlopen", lambda *_args, **_kwargs: FakeUpstream())
    response = client.get("/api/partner-offers/1/icon")
    assert response.status_code == 200
    assert response.content_type == "image/webp"
    assert response.headers["Cache-Control"].startswith("public, max-age=86400")


def test_import_is_idempotent_and_preserves_exact_semantics(client):
    admin = _login(client, "admin", "correct horse battery staple")

    first = _import(client, admin, [_offer()])
    second = _import(client, admin, [_offer()])

    assert first.status_code == 200
    assert first.get_json()["created_offers"] == 1
    assert first.get_json()["created_snapshots"] == 1
    assert second.status_code == 200
    assert second.get_json()["created_offers"] == 0
    assert second.get_json()["reused_snapshots"] == 1
    with app.app_context():
        assert PartnerOffer.query.count() == 1
        assert PartnerOfferSnapshot.query.count() == 1
        assert PartnerOfferImportRun.query.count() == 2

    response = client.get("/api/partner-offers/1", headers=admin)
    payload = response.get_json()
    assert payload["bank_name"] == "Т-Банк"
    snapshot = payload["snapshot"]
    assert snapshot["rate_qualifier"] == "up_to"
    assert snapshot["rate_value"] == 9.0
    assert snapshot["limits"] == [
        {
            "type": "max_cashback",
            "value": 1200.0,
            "unit": "bonus",
            "scope": "unknown",
            "original_text": "Максимум — 1 200 бонусов",
        },
    ]


def test_viewer_changes_only_own_preference_and_hidden_stays_hidden(client):
    admin = _login(client, "admin", "correct horse battery staple")
    viewer = _login(client, "viewer", "another correct horse battery")
    assert _import(client, admin, [_offer()]).status_code == 200

    response = client.put(
        "/api/partner-offers/1/preference",
        headers=viewer,
        json={"rating": "hidden"},
    )
    assert response.status_code == 200
    assert response.get_json()["rating"] == "hidden"

    assert _import(client, admin, [_offer()]).status_code == 200
    normal_list = client.get("/api/partner-offers", headers=viewer).get_json()
    hidden_list = client.get(
        "/api/partner-offers?rating=hidden",
        headers=viewer,
    ).get_json()
    admin_list = client.get("/api/partner-offers", headers=admin).get_json()
    assert normal_list["total"] == 0
    assert hidden_list["total"] == 1
    assert admin_list["total"] == 1
    assert admin_list["items"][0]["preference"] == "undecided"
    with app.app_context():
        assert PartnerOfferPreference.query.count() == 1


def test_only_explicitly_complete_catalog_marks_missing_offer_unavailable(client):
    admin = _login(client, "admin", "correct horse battery staple")
    assert _import(client, admin, [_offer()], complete=True).status_code == 200

    partial = _import(client, admin, [], complete=False)
    assert partial.status_code == 200
    with app.app_context():
        assert PartnerOffer.query.one().is_available is True

    complete = _import(client, admin, [], complete=True)
    assert complete.status_code == 200
    with app.app_context():
        assert PartnerOffer.query.one().is_available is False


def test_import_requires_editor_but_viewer_preference_is_allowed(client):
    viewer = _login(client, "viewer", "another correct horse battery")
    response = _import(client, viewer, [_offer()])
    assert response.status_code == 403

from datetime import datetime, timezone

import pytest

import main
from main import AuthSession, CashbackCategory, app, db
from test_auth import client as authenticated_client
from test_auth import login

client = authenticated_client


def setup_card(client):
    headers = {"Authorization": f"Bearer {login(client)}"}
    bank = client.post("/api/banks", json={"name": "Test"}, headers=headers).get_json()
    user = client.post("/api/users", json={"name": "Test"}, headers=headers).get_json()
    card = client.post(
        "/api/cards",
        headers=headers,
        json={
            "bank_id": bank["id"],
            "user_id": user["id"],
            "last_four_digits": "1234",
            "payment_system": "Visa",
            "card_type": "physical",
        },
    ).get_json()
    return headers, card


def payload(card):
    return {
        "name": "Test",
        "card_id": card["id"],
        "cashback_percent": 5,
        "start_date": "2026-10-01",
        "end_date": "2026-11-01",
    }


def test_delete_card_returns_empty_204(client):
    headers, card = setup_card(client)
    response = client.delete(f"/api/cards/{card['id']}", headers=headers)
    assert response.status_code == 204
    assert response.data == b""
    assert client.get(f"/api/cards/{card['id']}", headers=headers).status_code == 404


def test_card_created_at_default_preserves_naive_utc_contract(client):
    before = datetime.now(timezone.utc).replace(tzinfo=None)
    _, card = setup_card(client)
    after = datetime.now(timezone.utc).replace(tzinfo=None)
    created = datetime.fromisoformat(card['created_at'])
    assert created.tzinfo is None
    assert before <= created <= after


@pytest.mark.parametrize(
    "changes",
    [
        {"end_date": "2026-10-01"},
        {"start_date": None},
        {"cashback_percent": "5"},
        {"cashback_percent": -1},
        {"cashback_percent": True},
        {"category_type": []},
        {"category_type": "wrong"},
        {"is_selected": "false"},
        {"card_id": True},
        {"min_purchase_amount": -1},
        {"max_cashback_amount": float("inf")},
    ],
)
def test_create_and_update_use_same_validation_without_changing_evidence(client, changes):
    headers, card = setup_card(client)
    original = payload(card)
    category = client.post("/api/cashback", json=original, headers=headers).get_json()
    with app.app_context():
        db.session.get(CashbackCategory, category["id"]).is_bank_confirmed = True
        db.session.commit()
    assert (
        client.post("/api/cashback", json={**original, **changes}, headers=headers).status_code
        == 400
    )
    assert (
        client.put(f"/api/cashback/{category['id']}", json=changes, headers=headers).status_code
        == 400
    )
    saved = client.get(f"/api/cashback/{category['id']}", headers=headers).get_json()
    assert saved["is_bank_confirmed"] is True
    assert saved["end_date"] == "2026-11-01T00:00:00"


def test_cashback_timezone_and_active_period_use_moscow_wall_time(client, monkeypatch):
    headers, card = setup_card(client)
    response = client.post(
        "/api/cashback",
        headers=headers,
        json={
            **payload(card),
            "start_date": "2026-09-30T21:00:00Z",
            "end_date": "2026-10-31T21:00:00Z",
            "is_selected": True,
        },
    )
    assert response.status_code == 201
    category = response.get_json()
    assert category["start_date"] == "2026-10-01T00:00:00"
    with app.app_context():
        db.session.get(CashbackCategory, category["id"]).is_bank_confirmed = True
        AuthSession.query.one().expires_at = datetime(2026, 11, 2, tzinfo=timezone.utc)
        db.session.commit()
    db.session.expire_all()
    monkeypatch.setattr(
        main, "_utc_now", lambda: datetime(2026, 10, 31, 20, 59, tzinfo=timezone.utc)
    )
    assert [
        item["id"] for item in client.get("/api/active_cashback", headers=headers).get_json()
    ] == [category["id"]]
    monkeypatch.setattr(main, "_utc_now", lambda: datetime(2026, 10, 31, 21, tzinfo=timezone.utc))
    assert client.get("/api/active_cashback", headers=headers).get_json() == []

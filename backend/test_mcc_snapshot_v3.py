from datetime import datetime, timedelta

import main
from main import (
    BankCard,
    CanonicalCategory,
    CanonicalCategoryMcc,
    CardUser,
    CashbackCategory,
    MccCode,
    db,
)
from test_mcc_rules import client_and_headers as client_and_headers
from test_mcc_rules import publish, snapshot, upload


def seed_scenario(client, headers, bank_id):
    """Small synthetic contract covering every status and multiple programs."""
    db.session.add(
        CanonicalCategory(
            key="sports",
            group_key="leisure",
            group_title="Leisure",
            title="Sports",
            aliases=["Synthetic sport"],
            default_priority=1,
            sort_order=1,
        )
    )
    db.session.add(MccCode(code="0002", title="Synthetic MCC"))
    db.session.flush()
    db.session.add(CanonicalCategoryMcc(canonical_key="sports", mcc_code="0002"))
    db.session.commit()
    document = snapshot(bank_id)
    document["exclusions"] = [
        {"mcc": ["0002", "0005"], "kind": "unless_category", "reason": "Only selected category"},
        {"mcc": ["0003"], "kind": "conditional", "reason": "Payment condition"},
    ]
    document["categories"] = [
        {
            "sourceKey": "sports",
            "name": "Sports",
            "includedMcc": ["0002", "0003"],
            "excludedMcc": ["0004"],
            "description": "Synthetic sports",
            "canonicalKeys": ["sports"],
        },
        {
            "sourceKey": "all",
            "name": "All purchases",
            "includedMcc": [],
            "excludedMcc": ["0006"],
            "kind": "all_purchases",
        },
        {"sourceKey": "special", "name": "Special", "includedMcc": ["0007"]},
    ]
    first = upload(client, headers, document)
    assert first.status_code == 201
    assert publish(client, headers, first.get_json()["id"]).status_code == 200
    second = {
        **snapshot(bank_id),
        "programKey": "second-program",
        "programName": "Second program",
        "categories": [{"sourceKey": "sports", "name": "Sports", "includedMcc": ["0008"]}],
    }
    revision = upload(client, headers, second).get_json()
    assert publish(client, headers, revision["id"]).status_code == 200
    db.session.add(CardUser(name="Synthetic owner"))
    db.session.flush()
    card = BankCard(
        bank_id=bank_id,
        user_id=1,
        last_four_digits="1234",
        payment_system="Visa",
        card_type="physical",
    )
    db.session.add(card)
    db.session.flush()
    for name, start, end in [
        ("Sports", datetime(2026, 9, 1), datetime(2026, 10, 1)),
        ("All purchases", datetime(2026, 9, 1), datetime(2026, 10, 1)),
        ("Sports", datetime(2026, 8, 1), datetime(2026, 9, 1)),
        ("No published rule", datetime(2026, 9, 1), datetime(2026, 10, 1)),
        ("Sports", datetime(2026, 9, 15, 3), datetime(2026, 9, 16, 3)),
    ]:
        db.session.add(
            CashbackCategory(
                name=name, start_date=start, end_date=end, cashback_percent=5, card_id=card.id
            )
        )
    db.session.add(MccCode(code="0009", title="Unmatched catalogue code"))
    db.session.commit()


def materialize_lookup(payload, code):
    banks = []
    for revision in payload["revisions"]:
        entry = (
            payload["mcc_index"]
            .get(code, {})
            .get(
                str(revision["id"]),
                payload.get("mcc_defaults", {}).get(str(revision["id"]), {}),
            )
        )
        matched = entry.get("category_ids", [])
        earning = set(entry.get("earning_category_ids", []))
        position = entry.get("exclusion_index")
        banks.append(
            {
                "bank": payload["banks"][str(revision["bank_id"])],
                "revision_id": revision["id"],
                "program": revision["program"],
                "completeness": revision["completeness"],
                "status": entry.get("status", "not_in_categories"),
                "exclusion": revision["exclusions"][position] if position is not None else None,
                "categories": [
                    {key: category[key] for key in ("id", "name", "kind", "canonical")}
                    for category in revision["categories"]
                    if category["id"] in matched
                ],
                "offer_ids": sorted(
                    int(offer_id)
                    for offer_id, binding in payload["offer_bindings"].items()
                    if binding["active"]
                    and binding["bank_id"] == revision["bank_id"]
                    and earning.intersection(
                        binding["category_ids_by_revision"].get(str(revision["id"]), [])
                    )
                ),
            }
        )
    return {
        "mcc": payload["mcc_details"].get(code, {"code": code}),
        "as_of": payload["as_of"],
        "banks": banks,
        "canonical": [
            payload["canonical_categories"][key] for key in payload["canonical_mcc"].get(code, [])
        ],
    }


def materialize_offer(payload, offer_id):
    from main import _offer_mcc_payload, _parse_rule_datetime

    binding = payload["offer_bindings"][str(offer_id)]
    for revision in payload["revisions"]:
        ids = binding["category_ids_by_revision"].get(str(revision["id"]), [])
        if not ids:
            continue
        category = next(item for item in revision["categories"] if item["id"] in ids)
        offer = db.session.get(CashbackCategory, offer_id)
        titles = {code: item["title"] for code, item in payload["mcc_details"].items()}
        return _offer_mcc_payload(
            offer,
            binding["bank_id"],
            _parse_rule_datetime(payload["as_of"], "as_of"),
            revision,
            category,
            titles,
        )
    return None


def test_v3_exact_all_code_and_offer_parity_without_expanded_builder(
    client_and_headers, monkeypatch
):
    client, headers, bank_id = client_and_headers
    seed_scenario(client, headers, bank_id)

    def forbidden(*args):
        raise AssertionError("Schema 3 must not expand a per-code API matrix")

    monkeypatch.setattr(main, "_build_mcc_offline_snapshot", forbidden)
    monkeypatch.setattr(main, "compact_snapshot", forbidden)
    response = client.get("/api/mcc/offline-snapshot?schema=3&as_of=2026-09-15", headers=headers)
    assert response.status_code == 200
    payload = response.get_json()
    assert payload["schema_version"] == 3
    assert "shared_payloads" not in payload
    for code in [row["code"] for row in payload["catalogue"]] + ["9999"]:
        individual = client.get(f"/api/mcc/{code}/bank-rules?as_of=2026-09-15", headers=headers)
        assert materialize_lookup(payload, code) == individual.get_json()
    for offer_id in payload["offer_bindings"]:
        individual = client.get(
            f"/api/cashback/{offer_id}/mcc-rules?as_of=2026-09-15", headers=headers
        )
        expected = individual.get_json() if individual.status_code == 200 else None
        assert materialize_offer(payload, int(offer_id)) == expected


def test_v3_etag_shortcuts_content_and_separates_rule_and_binding_versions(
    client_and_headers,
    monkeypatch,
):
    client, headers, bank_id = client_and_headers
    seed_scenario(client, headers, bank_id)
    path = "/api/mcc/offline-snapshot?schema=3&as_of=2026-09-15"
    first = client.get(path, headers=headers)
    payload = first.get_json()
    etag = first.headers["ETag"]
    assert etag.startswith('W/"mcc-v3-')
    assert first.headers["Cache-Control"] == "private, max-age=0, must-revalidate"
    assert "Authorization" in first.headers["Vary"]

    def forbidden(*args):
        raise AssertionError("Unchanged sources must not serialize revisions or rebuild the index")

    monkeypatch.setattr(main, "_revision_to_dict", forbidden)
    monkeypatch.setattr(main, "build_rule_content", forbidden)
    later = main._utc_now() + timedelta(seconds=5)
    monkeypatch.setattr(main, "_utc_now", lambda: later)
    unchanged = client.get(path, headers={**headers, "If-None-Match": etag})
    assert unchanged.status_code == 304
    assert unchanged.data == b""
    assert unchanged.headers["ETag"] == etag
    manifest = client.get("/api/mcc/offline-manifest?as_of=2026-09-15", headers=headers).get_json()
    assert manifest["content_version"] == payload["content_version"]
    offer = db.session.get(CashbackCategory, 1)
    offer.name = "No longer matched"
    db.session.commit()
    changed = client.get(path, headers={**headers, "If-None-Match": etag})
    assert changed.status_code == 200
    fresh = changed.get_json()
    assert fresh["rules_version"] == payload["rules_version"]
    assert fresh["bindings_version"] != payload["bindings_version"]
    assert fresh["content_version"] != payload["content_version"]


def test_v3_date_boundaries_and_invalid_schema(client_and_headers):
    client, headers, bank_id = client_and_headers
    seed_scenario(client, headers, bank_id)
    first = client.get("/api/mcc/offline-snapshot?schema=3&as_of=2026-09-15", headers=headers)
    second = client.get(
        "/api/mcc/offline-snapshot?schema=3&as_of=2026-09-16",
        headers={**headers, "If-None-Match": first.headers["ETag"]},
    )
    assert second.status_code == 200
    assert first.get_json()["offer_bindings"]["5"]["active"] is True
    assert second.get_json()["offer_bindings"]["5"]["active"] is False
    assert first.get_json()["rules_version"] == second.get_json()["rules_version"]
    assert first.get_json()["bindings_version"] != second.get_json()["bindings_version"]
    assert client.get("/api/mcc/offline-snapshot?schema=1", headers=headers).status_code == 400
    assert client.get("/api/mcc/offline-manifest?as_of=invalid", headers=headers).status_code == 400


def test_v3_rules_catalogue_canonical_and_account_invalidate_private_validator(client_and_headers):
    from main import AuthSession, AuthUser, CanonicalCategory, _token_digest, _utc_now

    client, headers, bank_id = client_and_headers
    seed_scenario(client, headers, bank_id)
    path = "/api/mcc/offline-snapshot?schema=3&as_of=2026-09-15"
    previous = client.get(path, headers=headers)
    for mutate in (
        lambda: setattr(
            db.session.get(MccCode, "0002"), "description", "New reference description"
        ),
        lambda: setattr(db.session.get(CanonicalCategory, "sports"), "title", "Renamed canonical"),
    ):
        mutate()
        db.session.commit()
        current = client.get(path, headers={**headers, "If-None-Match": previous.headers["ETag"]})
        assert current.status_code == 200
        assert current.get_json()["rules_version"] != previous.get_json()["rules_version"]
        previous = current
    changed = snapshot(bank_id, included=["0009"])
    revision = upload(client, headers, changed).get_json()
    assert publish(client, headers, revision["id"]).status_code == 200
    current = client.get(path, headers={**headers, "If-None-Match": previous.headers["ETag"]})
    assert current.status_code == 200
    assert current.get_json()["rules_version"] != previous.get_json()["rules_version"]
    now = _utc_now()
    user = AuthUser(
        username="snapshot-viewer",
        password_hash="unused",
        role="viewer",
        auth_enabled=True,
        created_at=now,
        updated_at=now,
    )
    db.session.add(user)
    db.session.flush()
    db.session.add(
        AuthSession(
            user_id=user.id,
            token_digest=_token_digest("other-snapshot-account"),
            created_at=now,
            expires_at=now + timedelta(hours=1),
        )
    )
    db.session.commit()
    other = client.get(
        path,
        headers={
            "Authorization": "Bearer other-snapshot-account",
            "If-None-Match": current.headers["ETag"],
        },
    )
    assert other.status_code == 200
    assert other.headers["ETag"] != current.headers["ETag"]
    assert other.get_json()["rules_version"] == current.get_json()["rules_version"]
    assert client.get(path, headers={"If-None-Match": current.headers["ETag"]}).status_code == 401


def test_v3_all_bundled_mcc_lookup_results_match_existing_api(client_and_headers, monkeypatch):
    from canonical_categories import load_bundled_canonical_categories, upsert_canonical_categories
    from main import BANK_IMPORT_NAMES, Bank, _parse_rule_datetime, app
    from mcc_catalog import load_bundled_mcc_catalog, upsert_mcc_catalog

    client, headers, _ = client_and_headers
    upsert_mcc_catalog(db.session.connection(), MccCode.__table__, load_bundled_mcc_catalog())
    upsert_canonical_categories(
        db.session.connection(),
        CanonicalCategory.__table__,
        CanonicalCategoryMcc.__table__,
        load_bundled_canonical_categories(),
    )
    db.session.add_all(Bank(name=name, bank_key=key) for key, name in BANK_IMPORT_NAMES.items())
    db.session.commit()
    imported = app.test_cli_runner().invoke(args=["import-bank-mcc-rules", "--publish"])
    assert imported.exit_code == 0, imported.output
    published = list(main._published_payloads(_parse_rule_datetime("2026-10-14", "as_of")))
    db.session.add(CardUser(name="Bundled synthetic owner"))
    db.session.flush()
    for bank, revision in published:
        card = BankCard(
            bank_id=bank.id,
            user_id=1,
            last_four_digits="1234",
            payment_system="Visa",
            card_type="physical",
        )
        db.session.add(card)
        db.session.flush()
        for category in revision["categories"]:
            db.session.add(
                CashbackCategory(
                    name=category["name"],
                    start_date=datetime(2026, 10, 1),
                    end_date=datetime(2026, 11, 1),
                    cashback_percent=5,
                    card_id=card.id,
                )
            )
    db.session.commit()
    payload = client.get(
        "/api/mcc/offline-snapshot?schema=3&as_of=2026-10-14", headers=headers
    ).get_json()
    # The online handler still evaluates each MCC independently. Reuse only
    # immutable rule query results so this exhaustive check avoids 1000 SQL reloads.
    monkeypatch.setattr(main, "_published_payloads", lambda as_of: iter(published))
    assert len(payload["catalogue"]) >= 1105
    for row in payload["catalogue"]:
        code = row["code"]
        expected = client.get(f"/api/mcc/{code}/bank-rules?as_of=2026-10-14", headers=headers)
        assert materialize_lookup(payload, code) == expected.get_json(), code


def test_shared_dart_fixture_is_generated_from_current_server_contract(
    client_and_headers, monkeypatch
):
    import json
    from datetime import timezone
    from pathlib import Path

    fixture = json.loads(
        (Path(__file__).parent.parent / "contracts" / "mcc-offline-v3.fixture.json").read_text(
            encoding="utf-8"
        )
    )
    client, headers, bank_id = client_and_headers
    monkeypatch.setattr(main, "_utc_now", lambda: datetime(2026, 9, 15, tzinfo=timezone.utc))
    seed_scenario(client, headers, bank_id)
    response = client.get("/api/mcc/offline-snapshot?schema=3&as_of=2026-09-15", headers=headers)
    assert response.get_json() == fixture["snapshot"]
    for code, expected in fixture["lookups"].items():
        response = client.get(f"/api/mcc/{code}/bank-rules?as_of=2026-09-15", headers=headers)
        assert response.get_json() == expected
    for offer_id, expected in fixture["offer_rules"].items():
        response = client.get(
            f"/api/cashback/{offer_id}/mcc-rules?as_of=2026-09-15", headers=headers
        )
        assert (response.get_json() if response.status_code == 200 else None) == expected


def test_v3_rule_revision_half_open_dates_invalidate_selected_rules(client_and_headers):
    client, headers, bank_id = client_and_headers
    seed_scenario(client, headers, bank_id)
    finite = {
        **snapshot(bank_id),
        "programKey": "finite-program",
        "validity": {"from": "2026-09-15", "to": "2026-09-16", "confidence": "exact"},
    }
    revision = upload(client, headers, finite).get_json()
    assert publish(client, headers, revision["id"]).status_code == 200
    documents = []
    for as_of in ("2026-09-14T23:59:59.999Z", "2026-09-15", "2026-09-16"):
        result = client.get("/api/mcc/offline-snapshot?schema=3&as_of=" + as_of, headers=headers)
        assert result.status_code == 200
        documents.append(result.get_json())
    assert revision["id"] not in [item["id"] for item in documents[0]["revisions"]]
    assert revision["id"] in [item["id"] for item in documents[1]["revisions"]]
    assert revision["id"] not in [item["id"] for item in documents[2]["revisions"]]
    assert documents[0]["rules_version"] == documents[2]["rules_version"]
    assert documents[1]["rules_version"] != documents[0]["rules_version"]

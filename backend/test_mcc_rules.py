from datetime import datetime, timedelta, timezone

import pytest

from main import (
    AuthSession,
    AuthUser,
    Bank,
    BankRuleRevision,
    _token_digest,
    _utc_now,
    app,
    db,
)


@pytest.fixture()
def client_and_headers():
    app.config.update(TESTING=True)
    with app.app_context():
        db.create_all()
        now = _utc_now()
        bank = Bank(name='Синтетический банк')
        user = AuthUser(
            username='mcc-admin',
            password_hash='unused-in-this-test',
            role='admin',
            auth_enabled=True,
            created_at=now,
            updated_at=now,
        )
        db.session.add_all([bank, user])
        db.session.flush()
        token = 'synthetic-mcc-test-token'
        db.session.add(AuthSession(
            token_digest=_token_digest(token),
            user_id=user.id,
            created_at=now,
            expires_at=now + timedelta(hours=1),
        ))
        db.session.commit()
        yield app.test_client(), {'Authorization': f'Bearer {token}'}, bank.id
        db.session.remove()
        db.drop_all()


def snapshot(bank_id, valid_from='2026-09-01', included=None, collected_at=None):
    return {
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': bank_id,
        'programKey': 'synthetic-program',
        'programName': 'Синтетическая программа',
        'collectedAt': collected_at or '2026-09-02T10:00:00Z',
        'source': {
            'type': 'manual_verified',
            'url': 'https://example.invalid/synthetic-rules',
            'parserName': 'synthetic-fixture',
            'parserVersion': '1',
        },
        'validity': {
            'from': valid_from,
            'confidence': 'exact',
        },
        'completeness': 'partial_mcc',
        'globalExcludedMcc': ['0001'],
        'conditions': [{
            'kind': 'payment_method',
            'operator': 'not_equals',
            'value': 'sbp',
            'originalText': 'Синтетическое ограничение оплаты',
        }],
        'categories': [{
            'sourceId': 'sports',
            'name': 'Синтетический спорт',
            'includedMcc': included or ['0002', '0003'],
            'excludedMcc': ['0004'],
            'description': 'Тестовое описание, не являющееся банковскими данными',
            'completeness': 'partial_mcc',
        }],
    }


def upload(client, headers, document):
    return client.post(
        '/api/admin/mcc-rule-snapshots',
        json={'document': document},
        headers=headers,
    )


def publish(client, headers, revision_id):
    return client.post(
        f'/api/admin/mcc-rule-revisions/{revision_id}/publish',
        headers=headers,
    )


def test_snapshot_is_draft_until_published(client_and_headers):
    client, headers, bank_id = client_and_headers

    response = upload(client, headers, snapshot(bank_id))
    assert response.status_code == 201
    revision = response.get_json()
    assert revision['status'] == 'draft'
    assert revision['categories'][0]['included_mcc'] == ['0002', '0003']
    assert revision['categories'][0]['excluded_mcc'] == ['0004']

    hidden = client.get(
        f'/api/banks/{bank_id}/mcc-rules?as_of=2026-09-15',
        headers=headers,
    )
    assert hidden.status_code == 200
    assert hidden.get_json()['rules'] == []

    published = publish(client, headers, revision['id'])
    assert published.status_code == 200
    assert published.get_json()['status'] == 'published'

    visible = client.get(
        f'/api/banks/{bank_id}/mcc-rules?as_of=2026-09-15',
        headers=headers,
    ).get_json()['rules'][0]
    assert visible['global_excluded_mcc'] == ['0001']
    assert visible['categories'][0]['name'] == 'Синтетический спорт'
    assert visible['conditions'][0]['value'] == 'sbp'


def test_identical_rules_are_idempotent_even_when_collected_again(client_and_headers):
    client, headers, bank_id = client_and_headers
    first = upload(client, headers, snapshot(bank_id)).get_json()
    repeated_document = snapshot(bank_id, collected_at='2026-09-05T12:00:00Z')

    response = upload(client, headers, repeated_document)

    assert response.status_code == 200
    repeated = response.get_json()
    assert repeated['id'] == first['id']
    assert repeated['last_seen_at'].startswith('2026-09-05T12:00:00')
    with app.app_context():
        assert BankRuleRevision.query.count() == 1


def test_history_resolves_latest_applicable_revision(client_and_headers):
    client, headers, bank_id = client_and_headers
    september = upload(client, headers, snapshot(bank_id)).get_json()
    assert publish(client, headers, september['id']).status_code == 200
    october = upload(
        client,
        headers,
        snapshot(bank_id, valid_from='2026-10-01', included=['0005']),
    ).get_json()
    assert publish(client, headers, october['id']).status_code == 200

    september_rules = client.get(
        f'/api/banks/{bank_id}/mcc-rules?as_of=2026-09-30',
        headers=headers,
    ).get_json()['rules'][0]
    october_rules = client.get(
        f'/api/banks/{bank_id}/mcc-rules?as_of=2026-10-01',
        headers=headers,
    ).get_json()['rules'][0]

    assert september_rules['id'] == september['id']
    assert september_rules['categories'][0]['included_mcc'] == ['0002', '0003']
    assert october_rules['id'] == october['id']
    assert october_rules['categories'][0]['included_mcc'] == ['0005']


def test_known_at_reconstructs_rules_before_a_correction(client_and_headers):
    client, headers, bank_id = client_and_headers
    original = upload(client, headers, snapshot(bank_id)).get_json()
    publish(client, headers, original['id'])
    correction = upload(
        client,
        headers,
        snapshot(bank_id, included=['0005']),
    ).get_json()
    publish(client, headers, correction['id'])
    with app.app_context():
        original_revision = db.session.get(BankRuleRevision, original['id'])
        correction_revision = db.session.get(BankRuleRevision, correction['id'])
        original_revision.published_recorded_at = datetime(2026, 9, 2, tzinfo=timezone.utc)
        original_revision.superseded_at = datetime(2026, 9, 10, tzinfo=timezone.utc)
        correction_revision.published_recorded_at = datetime(2026, 9, 10, tzinfo=timezone.utc)
        db.session.commit()

    past_knowledge = client.get(
        f'/api/banks/{bank_id}/mcc-rules'
        '?as_of=2026-09-15&known_at=2026-09-05',
        headers=headers,
    ).get_json()['rules'][0]
    current_knowledge = client.get(
        f'/api/banks/{bank_id}/mcc-rules?as_of=2026-09-15',
        headers=headers,
    ).get_json()['rules'][0]

    assert past_knowledge['id'] == original['id']
    assert current_knowledge['id'] == correction['id']


def test_category_endpoint_includes_program_exclusions(client_and_headers):
    client, headers, bank_id = client_and_headers
    revision = upload(client, headers, snapshot(bank_id)).get_json()
    publish(client, headers, revision['id'])
    category_id = revision['categories'][0]['id']

    response = client.get(
        f'/api/banks/{bank_id}/categories/{category_id}/mcc-rules?as_of=2026-09-15',
        headers=headers,
    )

    assert response.status_code == 200
    payload = response.get_json()
    assert payload['global_excluded_mcc'] == ['0001']
    assert payload['category']['included_mcc'] == ['0002', '0003']
    assert payload['category']['excluded_mcc'] == ['0004']


def test_admin_can_list_drafts_and_published_revisions(client_and_headers):
    client, headers, bank_id = client_and_headers
    first = upload(client, headers, snapshot(bank_id)).get_json()
    publish(client, headers, first['id'])
    second = upload(
        client,
        headers,
        snapshot(bank_id, valid_from='2026-10-01', included=['0005']),
    ).get_json()

    response = client.get(
        f'/api/admin/mcc-rule-revisions?bank_id={bank_id}',
        headers=headers,
    )

    assert response.status_code == 200
    revisions = response.get_json()
    assert {item['status'] for item in revisions} == {'draft', 'published'}
    assert {item['id'] for item in revisions} == {first['id'], second['id']}


def test_auto_import_has_an_explicit_not_configured_state(client_and_headers):
    client, headers, bank_id = client_and_headers

    response = client.post(
        f'/api/admin/banks/{bank_id}/mcc-rules/auto-import',
        headers=headers,
    )

    assert response.status_code == 501
    assert response.get_json()['code'] == 'automatic_source_not_configured'


def test_invalid_or_ambiguous_mcc_rules_are_rejected_atomically(client_and_headers):
    client, headers, bank_id = client_and_headers
    document = snapshot(bank_id)
    document['categories'][0]['excludedMcc'] = ['0002']

    response = upload(client, headers, document)

    assert response.status_code == 400
    assert 'both includes and excludes MCC 0002' in response.get_json()['error']
    with app.app_context():
        assert BankRuleRevision.query.count() == 0


def test_admin_snapshot_endpoint_rejects_editor(client_and_headers):
    client, headers, bank_id = client_and_headers
    with app.app_context():
        user = AuthUser.query.filter_by(username='mcc-admin').one()
        user.role = 'editor'
        db.session.commit()

    response = upload(client, headers, snapshot(bank_id))

    assert response.status_code == 403

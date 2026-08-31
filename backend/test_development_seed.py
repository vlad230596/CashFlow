from datetime import date, datetime

import pytest

from development_seed import SeedDataExistsError, seed_development_data
from main import AuthUser, Bank, BankCard, CardUser, CashbackCategory, app, db


@pytest.fixture()
def seeded_database():
    with app.app_context():
        db.create_all()
        yield
        db.session.remove()
        db.drop_all()


def test_seed_creates_canonical_dataset(seeded_database):
    counts = seed_development_data(
        'dev-admin',
        'synthetic development password',
        reference_date=date(2026, 8, 31),
    )

    assert counts == {
        'auth_users': 1,
        'banks': 6,
        'card_users': 3,
        'cards': 8,
        'categories': 672,
        'target_month': '2026-09-01',
    }
    assert AuthUser.query.one().username == 'dev-admin'
    assert AuthUser.query.one().role == 'admin'
    assert Bank.query.count() == 6
    assert CardUser.query.count() == 3
    assert BankCard.query.filter_by(is_active=False).count() == 1
    assert CashbackCategory.query.filter_by(category_type='stackable_bonus').count() == 96

    response = app.test_client().post('/api/auth/login', json={
        'username': 'dev-admin',
        'password': 'synthetic development password',
    })
    assert response.status_code == 200

    for card in BankCard.query.filter_by(is_active=True):
        selected = CashbackCategory.query.filter_by(
            card_id=card.id,
            start_date=datetime(2026, 9, 1),
            category_type='standard',
            is_selected=True,
        ).count()
        assert selected == card.max_cashback_categories


def test_seed_refuses_non_empty_database_without_reset(seeded_database):
    seed_development_data('dev-admin', 'synthetic development password')

    with pytest.raises(SeedDataExistsError, match='not empty'):
        seed_development_data('dev-admin', 'another development password')


def test_reset_replaces_existing_data(seeded_database):
    seed_development_data('dev-admin', 'synthetic development password')
    db.session.add(Bank(name='Лишний банк'))
    db.session.commit()

    counts = seed_development_data(
        'replacement-admin',
        'replacement development password',
        reset=True,
        reference_date=date(2026, 9, 1),
    )

    assert counts['banks'] == 6
    assert Bank.query.filter_by(name='Лишний банк').first() is None
    assert AuthUser.query.one().username == 'replacement-admin'


def test_cli_refuses_any_database_except_cashflow_dev(seeded_database):
    result = app.test_cli_runner().invoke(args=['seed-development'])

    assert result.exit_code == 1
    assert 'expected "cashflow_dev"' in result.output

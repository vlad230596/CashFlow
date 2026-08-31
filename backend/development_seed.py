from datetime import date, datetime, timedelta

from sqlalchemy import text

from main import (
    AuthUser,
    Bank,
    BankCard,
    CardUser,
    CashbackCategory,
    _hash_password,
    _normalize_username,
    _utc_now,
    db,
)


class SeedDataExistsError(RuntimeError):
    pass


BANKS = (
    ('Т-Банк', 'Синтетический профиль банка для DEV.'),
    ('Альфа-Банк', 'Синтетический профиль банка для DEV.'),
    ('ВТБ', 'Синтетический профиль банка для DEV.'),
    ('Сбер', 'Синтетический профиль банка для DEV.'),
    ('Яндекс Банк', 'Синтетический профиль банка для DEV.'),
    ('Ozon Банк', 'Синтетический профиль банка для DEV.'),
)

CARD_USERS = (
    'Тест — Анна',
    'Тест — Михаил',
    'Тест — Семейные расходы',
)

CARDS = (
    ('Т-Банк', 0, 'Мир', 'physical', '1001', True, 4),
    ('Т-Банк', 2, 'MasterCard', 'virtual', '1002', True, 3),
    ('Альфа-Банк', 1, 'Visa', 'physical', '2001', True, 4),
    ('ВТБ', 0, 'Мир', 'physical', '3001', True, 3),
    ('Сбер', 2, 'Мир', 'physical', '4001', True, 4),
    ('Яндекс Банк', 1, 'Мир', 'virtual', '5001', True, 2),
    ('Ozon Банк', 2, 'Мир', 'virtual', '6001', True, 3),
    ('Альфа-Банк', 0, 'MasterCard', 'physical', '2099', False, 3),
)

CATEGORY_TEMPLATES = (
    ('Супермаркеты', 5.0, 'standard', 1500.0, None, 'Продуктовые магазины и доставка.'),
    ('Кафе и рестораны', 7.0, 'standard', 2000.0, None, 'Кафе, рестораны и фастфуд.'),
    ('АЗС', 10.0, 'standard', 2500.0, 1000.0, 'Заправочные станции; покупка от 1 000 ₽.'),
    ('Такси и каршеринг', 5.0, 'standard', 1200.0, None, 'Поездки и краткосрочная аренда.'),
    ('Аптеки', 3.0, 'standard', 1000.0, None, 'Аптеки и товары для здоровья.'),
    ('Путешествия', 8.0, 'standard', 5000.0, 10000.0, 'Билеты и отели; покупка от 10 000 ₽.'),
    (
        'Онлайн-покупки +1%',
        1.0,
        'stackable_bonus',
        750.0,
        None,
        'Суммируется с выбранной категорией.',
    ),
)


def _month_start(value, offset=0):
    month_index = value.year * 12 + value.month - 1 + offset
    return datetime(month_index // 12, month_index % 12 + 1, 1)


def _default_cashback_month(reference_date):
    reference = reference_date or date.today()
    offset = 0 if reference.day <= 20 else 1
    return _month_start(reference, offset)


def _existing_counts():
    return {
        'auth_users': db.session.query(AuthUser).count(),
        'banks': db.session.query(Bank).count(),
        'card_users': db.session.query(CardUser).count(),
        'cards': db.session.query(BankCard).count(),
        'categories': db.session.query(CashbackCategory).count(),
    }


def _clear_business_data():
    if db.engine.dialect.name == 'postgresql':
        db.session.execute(text(
            'TRUNCATE TABLE cashback_category, bank_card, card_user, bank '
            'RESTART IDENTITY CASCADE'
        ))
        return

    for model in (
        CashbackCategory,
        BankCard,
        CardUser,
        Bank,
    ):
        db.session.query(model).delete()


def seed_development_data(
    admin_username='devadmin',
    admin_password=None,
    *,
    reset=False,
    reference_date=None,
):
    existing = _existing_counts()
    business_counts = {
        name: count
        for name, count in existing.items()
        if name != 'auth_users' and count
    }
    if business_counts and not reset:
        summary = ', '.join(f'{name}={count}' for name, count in business_counts.items())
        raise SeedDataExistsError(
            f'Development business data is not empty ({summary}). Use --reset to replace it.'
        )

    create_admin = existing['auth_users'] == 0
    if create_admin:
        if admin_password is None:
            raise ValueError('Admin password is required when no authentication user exists')
        username = _normalize_username(admin_username)
        password_hash = _hash_password(admin_password)
    target_month = _default_cashback_month(reference_date)

    try:
        if reset:
            _clear_business_data()

        if create_admin:
            now = _utc_now()
            db.session.add(AuthUser(
                username=username,
                password_hash=password_hash,
                role='admin',
                auth_enabled=True,
                created_at=now,
                updated_at=now,
            ))

        banks = {}
        for name, description in BANKS:
            bank = Bank(name=name, description=description)
            db.session.add(bank)
            banks[name] = bank

        card_users = [CardUser(name=name) for name in CARD_USERS]
        db.session.add_all(card_users)
        db.session.flush()

        cards = []
        for card_index, card_spec in enumerate(CARDS):
            bank_name, user_index, payment_system, card_type, digits, active, maximum = card_spec
            card = BankCard(
                payment_system=payment_system,
                card_type=card_type,
                last_four_digits=digits,
                bank_id=banks[bank_name].id,
                user_id=card_users[user_index].id,
                created_at=target_month - timedelta(days=90 + card_index * 17),
                is_active=active,
                max_cashback_categories=maximum,
            )
            db.session.add(card)
            cards.append(card)
        db.session.flush()

        for month_offset in range(-2, 10):
            period_start = _month_start(target_month, month_offset)
            period_end = _month_start(period_start, 1)
            for card_index, card in enumerate(cards):
                selected_standard = set()
                if card.is_active:
                    selected_standard = {
                        (card_index + selection_index) % 6
                        for selection_index in range(card.max_cashback_categories)
                    }
                for category_index, template in enumerate(CATEGORY_TEMPLATES):
                    name, percent, category_type, maximum, minimum, description = template
                    selected = (
                        card.is_active
                        and (
                            category_type == 'stackable_bonus'
                            or category_index in selected_standard
                        )
                    )
                    db.session.add(CashbackCategory(
                        name=name,
                        start_date=period_start,
                        end_date=period_end,
                        is_selected=selected,
                        cashback_percent=percent + (card_index % 3),
                        description=f'Синтетические данные DEV. {description}',
                        category_type=category_type,
                        is_selection_locked=selected and month_offset <= 0,
                        max_cashback_amount=maximum,
                        min_purchase_amount=minimum,
                        card_id=card.id,
                    ))

        db.session.commit()
    except Exception:
        db.session.rollback()
        raise

    counts = _existing_counts()
    counts['target_month'] = target_month.date().isoformat()
    return counts

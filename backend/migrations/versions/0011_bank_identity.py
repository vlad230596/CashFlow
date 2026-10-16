"""Add stable bank integration keys without coupling identity to icons.

Revision ID: 0011_bank_identity
Revises: 0010_canonical_categories
"""

import re

import sqlalchemy as sa
from alembic import op

revision = "0011_bank_identity"
down_revision = "0010_canonical_categories"
branch_labels = None
depends_on = None

# Freeze migration aliases instead of importing a changing runtime registry.
ALIASES = {
    "tbank": ("Т-Банк", "Тинькофф", "Тинькофф Банк", "T-Bank"),
    "alfa": ("Альфа", "Альфа-Банк", "Alfa Bank"),
    "vtb": ("ВТБ", "VTB"),
    "sber": ("Сбер", "Сбербанк", "Сбер Банк", "Sber"),
    "yandex": (
        "Яндекс",
        "Яндекс Банк",
        "Яндекс-Банк",
        "Яндекс Пэй",
        "Яндекс Pay",
        "Yandex Bank",
        "Yandex Pay",
    ),
    "ozon": ("Озон", "Озон Банк", "Ozon", "Ozon Банк", "Ozon Bank"),
}


def upgrade():
    op.add_column('bank', sa.Column('bank_key', sa.String(length=24), nullable=True))
    op.create_index('ix_bank_bank_key', 'bank', ['bank_key'], unique=True)
    table = sa.table(
        "bank",
        sa.column("id", sa.Integer()),
        sa.column("name", sa.String()),
        sa.column("bank_key", sa.String()),
    )
    if op.get_context().as_sql:
        name = sa.func.lower(table.c.name)
        if op.get_context().dialect.name == 'postgresql':
            name = sa.func.regexp_replace(name, '[^a-zа-яё0-9]', '', 'g')
        else:
            for character in (' ', '-', '.', '_'):
                name = sa.func.replace(name, character, '')
        for key, names in ALIASES.items():
            values = {re.sub(r'[^a-zа-яё0-9]', '', item.lower()) for item in names}
            if op.get_context().dialect.name == 'sqlite':
                # SQLite lower() folds ASCII only; include the frozen aliases'
                # Cyrillic casing as well when emitting a standalone SQL file.
                for alias in names:
                    for candidate in (alias, alias.upper()):
                        letters = re.sub(r'[^a-zA-Zа-яА-ЯёЁ0-9]', '', candidate)
                        values.add(''.join(letter.lower() if letter.isascii() else letter
                                           for letter in letters))
            first = (sa.select(sa.func.min(table.c.id))
                     .where(name.in_(sorted(values))).scalar_subquery())
            op.execute(table.update().where(table.c.id == first).values(bank_key=key))
        return
    connection = op.get_bind()
    used = set()
    aliases = {
        re.sub(r"[^a-zа-яё0-9]", "", alias.lower()): key
        for key, names in ALIASES.items()
        for alias in names
    }
    for row in connection.execute(sa.select(table.c.id, table.c.name).order_by(table.c.id)):
        key = aliases.get(re.sub(r"[^a-zа-яё0-9]", "", row.name.lower()))
        # Multiple old aliases for one bank are ambiguous; keep only the first
        # configured identity. Never invent integration identity from an icon.
        if key and key not in used:
            connection.execute(table.update().where(table.c.id == row.id).values(bank_key=key))
            used.add(key)


def downgrade():
    op.drop_index('ix_bank_bank_key', table_name='bank')
    with op.batch_alter_table("bank") as batch:
        batch.drop_column("bank_key")

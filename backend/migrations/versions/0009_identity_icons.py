"""Add editable bank and card-user icons.

Revision ID: 0009_identity_icons
Revises: 0008_subscriptions
"""

import sqlalchemy as sa
from alembic import op

revision = '0009_identity_icons'
down_revision = '0008_subscriptions'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        'bank',
        sa.Column('icon_key', sa.String(length=24), nullable=True),
    )
    op.add_column(
        'card_user',
        sa.Column('icon_key', sa.String(length=24), nullable=True),
    )
    op.execute("""
        UPDATE bank
        SET icon_key = CASE
            WHEN lower(name) LIKE '%т-банк%' OR lower(name) LIKE '%тинькофф%' THEN 'tbank'
            WHEN lower(name) LIKE '%альфа%' THEN 'alfa'
            WHEN lower(name) LIKE '%втб%' THEN 'vtb'
            WHEN lower(name) LIKE '%сбер%' THEN 'sber'
            WHEN lower(name) LIKE '%яндекс%' THEN 'yandex'
            WHEN lower(name) LIKE '%ozon%' OR lower(name) LIKE '%озон%' THEN 'ozon'
            ELSE 'generic'
        END
    """)
    op.execute("""
        UPDATE card_user
        SET icon_key = CASE
            WHEN lower(name) LIKE '%анна%' THEN 'girl'
            WHEN lower(name) LIKE '%михаил%' THEN 'boy'
            WHEN lower(name) LIKE '%семейн%' THEN 'family'
            ELSE 'person'
        END
    """)
    with op.batch_alter_table('bank') as batch:
        batch.alter_column(
            'icon_key',
            existing_type=sa.String(length=24),
            nullable=False,
            server_default='generic',
        )
    with op.batch_alter_table('card_user') as batch:
        batch.alter_column(
            'icon_key',
            existing_type=sa.String(length=24),
            nullable=False,
            server_default='boy',
        )


def downgrade():
    with op.batch_alter_table('card_user') as batch:
        batch.drop_column('icon_key')
    with op.batch_alter_table('bank') as batch:
        batch.drop_column('icon_key')

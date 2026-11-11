"""Add the ZenMoney balance integration: encrypted token, account snapshot, card links.

Revision ID: 0014_zenmoney_balances
Revises: 0013_promo_items
"""

import sqlalchemy as sa
from alembic import op

revision = '0014_zenmoney_balances'
down_revision = '0013_promo_items'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'zenmoney_integration',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('token_ciphertext', sa.Text(), nullable=True),
        sa.Column('token_set_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('token_set_by_id', sa.Integer(), nullable=True),
        sa.Column('server_timestamp', sa.BigInteger(), nullable=True),
        sa.Column('last_attempt_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_success_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_error_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('last_error_kind', sa.String(length=32), nullable=True),
        sa.Column('last_error_message', sa.String(length=200), nullable=True),
        sa.Column('refresh_started_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['token_set_by_id'], ['auth_user.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table(
        'zenmoney_account',
        sa.Column('id', sa.String(length=64), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('account_type', sa.String(length=16), nullable=False),
        sa.Column('company_id', sa.Integer(), nullable=True),
        sa.Column('company_title', sa.String(length=200), nullable=True),
        sa.Column('instrument_id', sa.Integer(), nullable=True),
        sa.Column('currency', sa.String(length=8), nullable=True),
        sa.Column('sync_ids_json', sa.Text(), nullable=False),
        sa.Column('balance', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('credit_limit', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('archived', sa.Boolean(), nullable=False),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('missing_since', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table(
        'card_zenmoney_link',
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('account_id', sa.String(length=64), nullable=True),
        sa.Column('source', sa.String(length=8), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_by_id', sa.Integer(), nullable=True),
        sa.CheckConstraint(
            "source IN ('auto', 'manual')",
            name='ck_card_zenmoney_link_source',
        ),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['updated_by_id'], ['auth_user.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('card_id'),
    )


def downgrade():
    op.drop_table('card_zenmoney_link')
    op.drop_table('zenmoney_account')
    op.drop_table('zenmoney_integration')

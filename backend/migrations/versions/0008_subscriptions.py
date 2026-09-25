"""Add subscriptions, payment history, and active periods.

Revision ID: 0008_subscriptions
Revises: 0007_seed_mcc_catalog
"""

import sqlalchemy as sa
from alembic import op

revision = '0008_subscriptions'
down_revision = '0007_seed_mcc_catalog'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'subscription',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('auth_user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('kind', sa.String(length=16), nullable=False),
        sa.Column('expected_amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('billing_interval_count', sa.Integer(), nullable=False),
        sa.Column('billing_interval_unit', sa.String(length=8), nullable=False),
        sa.Column('next_payment_date', sa.Date(), nullable=False),
        sa.Column('reminder_days_json', sa.Text(), nullable=False),
        sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint('expected_amount > 0', name='ck_subscription_amount'),
        sa.CheckConstraint(
            "billing_interval_count > 0",
            name='ck_subscription_interval_count',
        ),
        sa.CheckConstraint(
            "billing_interval_unit IN ('day', 'week', 'month', 'year')",
            name='ck_subscription_interval_unit',
        ),
        sa.CheckConstraint(
            "kind IN ('subscription', 'trial')",
            name='ck_subscription_kind',
        ),
        sa.ForeignKeyConstraint(['auth_user_id'], ['auth_user.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_subscription_owner_archived',
        'subscription',
        ['auth_user_id', 'archived_at'],
    )
    op.create_index(
        'ix_subscription_owner_next_payment',
        'subscription',
        ['auth_user_id', 'next_payment_date'],
    )
    op.create_table(
        'subscription_active_period',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('subscription_id', sa.Integer(), nullable=False),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('ended_at', sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            'ended_at IS NULL OR ended_at >= started_at',
            name='ck_subscription_active_period_order',
        ),
        sa.ForeignKeyConstraint(
            ['subscription_id'],
            ['subscription.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_subscription_active_period_subscription_started',
        'subscription_active_period',
        ['subscription_id', 'started_at'],
    )
    op.create_table(
        'subscription_payment',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('subscription_id', sa.Integer(), nullable=False),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('paid_at', sa.Date(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint('amount > 0', name='ck_subscription_payment_amount'),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id']),
        sa.ForeignKeyConstraint(
            ['subscription_id'],
            ['subscription.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'subscription_id',
            'paid_at',
            name='uq_subscription_payment_subscription_paid',
        ),
    )
    op.create_index(
        'ix_subscription_payment_subscription_paid',
        'subscription_payment',
        ['subscription_id', 'paid_at'],
    )


def downgrade():
    op.drop_index(
        'ix_subscription_payment_subscription_paid',
        table_name='subscription_payment',
    )
    op.drop_table('subscription_payment')
    op.drop_index(
        'ix_subscription_active_period_subscription_started',
        table_name='subscription_active_period',
    )
    op.drop_table('subscription_active_period')
    op.drop_index('ix_subscription_owner_next_payment', table_name='subscription')
    op.drop_index('ix_subscription_owner_archived', table_name='subscription')
    op.drop_table('subscription')

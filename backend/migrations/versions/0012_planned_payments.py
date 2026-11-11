"""Add planned payments (recurring anchored and one-off) and their records.

Revision ID: 0012_planned_payments
Revises: 0011_bank_identity
"""

import sqlalchemy as sa
from alembic import op

revision = '0012_planned_payments'
down_revision = '0011_bank_identity'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'planned_payment',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('auth_user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=200), nullable=False),
        sa.Column('kind', sa.String(length=16), nullable=False),
        sa.Column('expected_amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=True),
        sa.Column('note', sa.Text(), nullable=True),
        sa.Column('interval_count', sa.Integer(), nullable=True),
        sa.Column('interval_unit', sa.String(length=8), nullable=True),
        sa.Column('anchor_date', sa.Date(), nullable=False),
        sa.Column('next_due_date', sa.Date(), nullable=False),
        sa.Column('reminder_days_json', sa.Text(), nullable=False),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "kind IN ('recurring', 'one_off')",
            name='ck_planned_payment_kind',
        ),
        sa.CheckConstraint(
            "(kind = 'one_off' AND interval_count IS NULL AND interval_unit IS NULL)"
            " OR (kind = 'recurring' AND interval_count > 0"
            " AND interval_unit IN ('day', 'week', 'month', 'year'))",
            name='ck_planned_payment_interval',
        ),
        sa.CheckConstraint('expected_amount > 0', name='ck_planned_payment_amount'),
        sa.CheckConstraint(
            'anchor_date <= next_due_date',
            name='ck_planned_payment_anchor_order',
        ),
        sa.ForeignKeyConstraint(['auth_user_id'], ['auth_user.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_planned_payment_owner_archived',
        'planned_payment',
        ['auth_user_id', 'archived_at'],
    )
    op.create_index(
        'ix_planned_payment_owner_next_due',
        'planned_payment',
        ['auth_user_id', 'next_due_date'],
    )
    op.create_table(
        'planned_payment_record',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('payment_id', sa.Integer(), nullable=False),
        sa.Column('due_date', sa.Date(), nullable=False),
        sa.Column('paid_at', sa.Date(), nullable=False),
        sa.Column('amount', sa.Numeric(precision=18, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint('amount > 0', name='ck_planned_payment_record_amount'),
        sa.ForeignKeyConstraint(
            ['payment_id'],
            ['planned_payment.id'],
            ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'payment_id',
            'due_date',
            name='uq_planned_payment_record_payment_due',
        ),
    )
    op.create_index(
        'ix_planned_payment_record_payment_paid',
        'planned_payment_record',
        ['payment_id', 'paid_at'],
    )


def downgrade():
    op.drop_index(
        'ix_planned_payment_record_payment_paid',
        table_name='planned_payment_record',
    )
    op.drop_table('planned_payment_record')
    op.drop_index('ix_planned_payment_owner_next_due', table_name='planned_payment')
    op.drop_index('ix_planned_payment_owner_archived', table_name='planned_payment')
    op.drop_table('planned_payment')

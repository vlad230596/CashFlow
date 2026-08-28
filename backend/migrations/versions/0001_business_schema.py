"""Create the CashFlow business schema.

Revision ID: 0001_business_schema
Revises:
"""

import sqlalchemy as sa
from alembic import op

revision = '0001_business_schema'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'bank',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=50), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('name'),
    )
    op.create_table(
        'card_user',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table(
        'bank_card',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('payment_system', sa.String(length=20), nullable=False),
        sa.Column('card_type', sa.String(length=10), nullable=False),
        sa.Column('last_four_digits', sa.String(length=4), nullable=False),
        sa.Column('bank_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=True),
        sa.Column('max_cashback_categories', sa.Integer(), server_default='4', nullable=True),
        sa.ForeignKeyConstraint(['bank_id'], ['bank.id']),
        sa.ForeignKeyConstraint(['user_id'], ['card_user.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_table(
        'cashback_category',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=50), nullable=False),
        sa.Column('start_date', sa.DateTime(), nullable=False),
        sa.Column('end_date', sa.DateTime(), nullable=False),
        sa.Column('is_selected', sa.Boolean(), nullable=True),
        sa.Column('cashback_percent', sa.Float(), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column(
            'category_type',
            sa.String(length=32),
            server_default='standard',
            nullable=False,
        ),
        sa.Column(
            'is_selection_locked',
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
        ),
        sa.Column('max_cashback_amount', sa.Float(), nullable=True),
        sa.Column('min_purchase_amount', sa.Float(), nullable=True),
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['card_id'], ['bank_card.id']),
        sa.PrimaryKeyConstraint('id'),
    )


def downgrade():
    op.drop_table('cashback_category')
    op.drop_table('bank_card')
    op.drop_table('card_user')
    op.drop_table('bank')

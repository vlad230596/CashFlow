"""Add promo codes, offers and expiring points (the promo section).

Revision ID: 0013_promo_items
Revises: 0012_planned_payments
"""

import sqlalchemy as sa
from alembic import op

revision = '0013_promo_items'
down_revision = '0012_planned_payments'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'promo_item',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('auth_user_id', sa.Integer(), nullable=False),
        sa.Column('client_id', sa.String(length=64), nullable=True),
        sa.Column('kind', sa.String(length=16), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('merchant', sa.String(length=200), nullable=True),
        sa.Column('promo_code', sa.String(length=100), nullable=True),
        sa.Column('discount', sa.String(length=100), nullable=True),
        sa.Column('points_amount', sa.Numeric(precision=18, scale=2), nullable=True),
        sa.Column('points_unit', sa.String(length=40), nullable=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('source_text', sa.Text(), nullable=True),
        sa.Column('starts_at', sa.Date(), nullable=True),
        sa.Column('expires_at', sa.Date(), nullable=True),
        sa.Column('reminder_days_json', sa.Text(), nullable=False),
        sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('promo', 'points')", name='ck_promo_item_kind'),
        sa.CheckConstraint(
            'points_amount IS NULL OR points_amount >= 0',
            name='ck_promo_item_points_amount',
        ),
        sa.CheckConstraint(
            'starts_at IS NULL OR expires_at IS NULL OR starts_at <= expires_at',
            name='ck_promo_item_period',
        ),
        sa.ForeignKeyConstraint(['auth_user_id'], ['auth_user.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('auth_user_id', 'client_id', name='uq_promo_item_owner_client'),
    )
    op.create_index(
        'ix_promo_item_owner_expires',
        'promo_item',
        ['auth_user_id', 'expires_at'],
    )


def downgrade():
    op.drop_index('ix_promo_item_owner_expires', table_name='promo_item')
    op.drop_table('promo_item')

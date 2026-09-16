"""Separate desired cashback selection from bank confirmation."""

import sqlalchemy as sa
from alembic import op

revision = '0004_bank_confirmation'
down_revision = '0003_mcc_rule_history'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('cashback_category', sa.Column(
        'is_bank_confirmed', sa.Boolean(), nullable=False, server_default=sa.false(),
    ))


def downgrade():
    op.drop_column('cashback_category', 'is_bank_confirmed')

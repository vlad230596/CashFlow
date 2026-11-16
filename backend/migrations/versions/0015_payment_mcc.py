"""Add an optional MCC code to planned payments.

Revision ID: 0015_payment_mcc
Revises: 0014_zenmoney_balances
"""

import sqlalchemy as sa
from alembic import op

revision = '0015_payment_mcc'
down_revision = '0014_zenmoney_balances'
branch_labels = None
depends_on = None


def upgrade():
    # No foreign key to mcc_code: like /api/mcc/{code}/bank-rules, a payment may
    # name a four-digit code that the reference catalogue does not list yet.
    with op.batch_alter_table('planned_payment') as batch:
        batch.add_column(sa.Column('mcc_code', sa.String(length=4), nullable=True))


def downgrade():
    with op.batch_alter_table('planned_payment') as batch:
        batch.drop_column('mcc_code')

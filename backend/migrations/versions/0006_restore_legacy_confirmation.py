"""Restore the pre-confirmation meaning of existing selected categories.

Revision ID: 0006_restore_legacy_confirmation
Revises: 0005_partner_offers
"""

from alembic import op

revision = '0006_restore_legacy_confirmation'
down_revision = '0005_partner_offers'
branch_labels = None
depends_on = None


def upgrade():
    # Before 0004 every selected category was considered active. Adding the
    # confirmation column with a false default accidentally hid all legacy
    # selections. Do this only when no bank-confirmed import has happened yet;
    # otherwise it would revive stale overlapping categories after recovery.
    op.execute(
        'UPDATE cashback_category SET is_bank_confirmed = true '
        'WHERE is_selected = true AND is_bank_confirmed = false '
        'AND NOT EXISTS ('
        'SELECT 1 FROM cashback_category confirmed '
        'WHERE confirmed.is_bank_confirmed = true'
        ')'
    )


def downgrade():
    # Confirmation may have changed through real imports after upgrade. It is
    # not safe to infer which rows were modified by this compatibility step.
    pass

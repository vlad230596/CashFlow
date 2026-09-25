"""Seed the MCC reference catalogue from a pinned mcc-codes.ru CSV snapshot.

Revision ID: 0007_seed_mcc_catalog
Revises: 0006_restore_legacy_confirmation
"""

import sqlalchemy as sa
from alembic import op

from mcc_catalog import load_bundled_mcc_catalog, upsert_mcc_catalog

revision = "0007_seed_mcc_catalog"
down_revision = "0006_restore_legacy_confirmation"
branch_labels = None
depends_on = None


mcc_code = sa.table(
    "mcc_code",
    sa.column("code", sa.String(length=4)),
    sa.column("title", sa.String(length=255)),
    sa.column("description", sa.Text()),
    sa.column("reference_source", sa.Text()),
)


def upgrade():
    rows = load_bundled_mcc_catalog()
    upsert_mcc_catalog(op.get_bind(), mcc_code, rows)


def downgrade():
    # Reference data can be used by rules created after this migration. Keep it
    # intact rather than deleting or blanking records during a schema rollback.
    pass

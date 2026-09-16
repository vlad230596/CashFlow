"""Add persistent partner offers, snapshots, and personal preferences.

Revision ID: 0005_partner_offers
Revises: 0004_bank_confirmation
"""

import sqlalchemy as sa
from alembic import op

revision = "0005_partner_offers"
down_revision = "0004_bank_confirmation"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "partner_merchant",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("canonical_key", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=255), nullable=False),
        sa.Column("domain", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("canonical_key"),
    )
    op.create_table(
        "partner_offer_asset",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("mime_type", sa.String(length=127), nullable=False),
        sa.Column("storage_path", sa.Text(), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("content_hash"),
    )
    op.create_table(
        "partner_merchant_alias",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("merchant_id", sa.Integer(), nullable=False),
        sa.Column("bank_id", sa.Integer(), nullable=False),
        sa.Column("source_key", sa.String(length=255), nullable=False),
        sa.Column("source_name", sa.String(length=255), nullable=True),
        sa.ForeignKeyConstraint(["bank_id"], ["bank.id"]),
        sa.ForeignKeyConstraint(["merchant_id"], ["partner_merchant.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "bank_id",
            "source_key",
            name="uq_partner_merchant_alias_bank_source",
        ),
    )
    op.create_table(
        "partner_offer",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("bank_id", sa.Integer(), nullable=False),
        sa.Column("card_user_id", sa.Integer(), nullable=False),
        sa.Column("merchant_id", sa.Integer(), nullable=True),
        sa.Column("source_key", sa.String(length=255), nullable=False),
        sa.Column("source_external_id", sa.String(length=255), nullable=True),
        sa.Column("current_snapshot_id", sa.Integer(), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_available", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("unavailable_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["bank_id"], ["bank.id"]),
        sa.ForeignKeyConstraint(["card_user_id"], ["card_user.id"]),
        sa.ForeignKeyConstraint(["merchant_id"], ["partner_merchant.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "bank_id",
            "card_user_id",
            "source_key",
            name="uq_partner_offer_profile_source",
        ),
    )
    op.create_index(
        "ix_partner_offer_bank_available",
        "partner_offer",
        ["bank_id", "is_available"],
    )
    op.create_index(
        "ix_partner_offer_profile_available",
        "partner_offer",
        ["card_user_id", "is_available"],
    )
    op.create_table(
        "partner_offer_snapshot",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("offer_id", sa.Integer(), nullable=False),
        sa.Column("collected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("details_collected_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("benefit_kind", sa.String(length=16), nullable=False),
        sa.Column("rate_value", sa.Numeric(12, 4), nullable=True),
        sa.Column("rate_qualifier", sa.String(length=16), nullable=False),
        sa.Column("rate_label", sa.String(length=255), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("validity_label", sa.String(length=255), nullable=True),
        sa.Column(
            "validity_precision", sa.String(length=16), server_default="unknown", nullable=False
        ),
        sa.Column("preview_text", sa.Text(), nullable=True),
        sa.Column("conditions", sa.Text(), nullable=True),
        sa.Column("steps_json", sa.Text(), server_default="[]", nullable=False),
        sa.Column("links_json", sa.Text(), server_default="[]", nullable=False),
        sa.Column("requirements_json", sa.Text(), server_default="[]", nullable=False),
        sa.Column("details_status", sa.String(length=16), nullable=False),
        sa.Column("details_error", sa.Text(), nullable=True),
        sa.Column("source_url", sa.Text(), nullable=True),
        sa.Column("icon_url", sa.Text(), nullable=True),
        sa.Column("artwork_url", sa.Text(), nullable=True),
        sa.Column("raw_json", sa.Text(), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "benefit_kind IN ('cashback', 'discount', 'other')",
            name="ck_partner_offer_snapshot_benefit_kind",
        ),
        sa.CheckConstraint(
            "details_status IN ('complete', 'preview_only', 'error')",
            name="ck_partner_offer_snapshot_details_status",
        ),
        sa.CheckConstraint(
            "rate_qualifier IN ('exact', 'up_to', 'from', 'unknown')",
            name="ck_partner_offer_snapshot_rate_qualifier",
        ),
        sa.ForeignKeyConstraint(["offer_id"], ["partner_offer.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "offer_id",
            "content_hash",
            name="uq_partner_offer_snapshot_content",
        ),
    )
    op.create_index(
        "ix_partner_offer_snapshot_ends_at",
        "partner_offer_snapshot",
        ["ends_at"],
    )
    op.create_table(
        "partner_offer_limit",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("snapshot_id", sa.Integer(), nullable=False),
        sa.Column("limit_type", sa.String(length=32), nullable=False),
        sa.Column("value", sa.Numeric(14, 4), nullable=True),
        sa.Column("unit", sa.String(length=16), nullable=False),
        sa.Column("scope", sa.String(length=16), nullable=False),
        sa.Column("original_text", sa.Text(), nullable=False),
        sa.CheckConstraint(
            "scope IN ('purchase', 'month', 'campaign', 'unknown')",
            name="ck_partner_offer_limit_scope",
        ),
        sa.CheckConstraint(
            "unit IN ('RUB', 'bonus', 'points', 'unknown')",
            name="ck_partner_offer_limit_unit",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["partner_offer_snapshot.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "partner_offer_preference",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("auth_user_id", sa.Integer(), nullable=False),
        sa.Column("offer_id", sa.Integer(), nullable=False),
        sa.Column("rating", sa.String(length=16), server_default="undecided", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "rating IN ('interesting', 'undecided', 'hidden')",
            name="ck_partner_offer_preference_rating",
        ),
        sa.ForeignKeyConstraint(["auth_user_id"], ["auth_user.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["offer_id"], ["partner_offer.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "auth_user_id",
            "offer_id",
            name="uq_partner_offer_preference_user_offer",
        ),
    )
    op.create_index(
        "ix_partner_offer_preference_user_rating",
        "partner_offer_preference",
        ["auth_user_id", "rating"],
    )
    op.create_table(
        "partner_offer_hide_rule",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("auth_user_id", sa.Integer(), nullable=False),
        sa.Column("scope", sa.String(length=32), nullable=False),
        sa.Column("offer_id", sa.Integer(), nullable=True),
        sa.Column("merchant_id", sa.Integer(), nullable=True),
        sa.Column("bank_id", sa.Integer(), nullable=True),
        sa.Column("campaign_key", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "scope IN ('offer', 'campaign', 'merchant_bank', 'merchant_all_banks')",
            name="ck_partner_offer_hide_rule_scope",
        ),
        sa.ForeignKeyConstraint(["auth_user_id"], ["auth_user.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["bank_id"], ["bank.id"]),
        sa.ForeignKeyConstraint(["merchant_id"], ["partner_merchant.id"]),
        sa.ForeignKeyConstraint(["offer_id"], ["partner_offer.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_partner_offer_hide_rule_user_active",
        "partner_offer_hide_rule",
        ["auth_user_id", "revoked_at"],
    )
    op.create_table(
        "partner_offer_import_run",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("bank_id", sa.Integer(), nullable=False),
        sa.Column("card_user_id", sa.Integer(), nullable=False),
        sa.Column("imported_by_id", sa.Integer(), nullable=False),
        sa.Column("collected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("imported_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("preview_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("details_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("completeness", sa.String(length=16), nullable=False),
        sa.Column("errors_json", sa.Text(), server_default="[]", nullable=False),
        sa.Column("collector_version", sa.String(length=64), nullable=True),
        sa.Column("source_hash", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "completeness IN ('complete', 'partial', 'unknown')",
            name="ck_partner_offer_import_run_completeness",
        ),
        sa.ForeignKeyConstraint(["bank_id"], ["bank.id"]),
        sa.ForeignKeyConstraint(["card_user_id"], ["card_user.id"]),
        sa.ForeignKeyConstraint(["imported_by_id"], ["auth_user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_partner_offer_import_run_profile_collected",
        "partner_offer_import_run",
        ["card_user_id", "collected_at"],
    )


def downgrade():
    op.drop_index(
        "ix_partner_offer_import_run_profile_collected",
        table_name="partner_offer_import_run",
    )
    op.drop_table("partner_offer_import_run")
    op.drop_index(
        "ix_partner_offer_hide_rule_user_active",
        table_name="partner_offer_hide_rule",
    )
    op.drop_table("partner_offer_hide_rule")
    op.drop_index(
        "ix_partner_offer_preference_user_rating",
        table_name="partner_offer_preference",
    )
    op.drop_table("partner_offer_preference")
    op.drop_table("partner_offer_limit")
    op.drop_index("ix_partner_offer_snapshot_ends_at", table_name="partner_offer_snapshot")
    op.drop_table("partner_offer_snapshot")
    op.drop_index("ix_partner_offer_profile_available", table_name="partner_offer")
    op.drop_index("ix_partner_offer_bank_available", table_name="partner_offer")
    op.drop_table("partner_offer")
    op.drop_table("partner_merchant_alias")
    op.drop_table("partner_offer_asset")
    op.drop_table("partner_merchant")

"""Add the historical MCC rule knowledge base.

Revision ID: 0003_mcc_rule_history
Revises: 0002_authentication
"""

import sqlalchemy as sa
from alembic import op

revision = '0003_mcc_rule_history'
down_revision = '0002_authentication'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'mcc_code',
        sa.Column('code', sa.String(length=4), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('reference_source', sa.Text(), nullable=True),
        sa.CheckConstraint("length(code) = 4", name='ck_mcc_code_length'),
        sa.PrimaryKeyConstraint('code'),
    )
    op.create_table(
        'bank_cashback_program',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('bank_id', sa.Integer(), nullable=False),
        sa.Column('source_key', sa.String(length=128), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('product_scope', sa.String(length=255), nullable=True),
        sa.ForeignKeyConstraint(['bank_id'], ['bank.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('bank_id', 'source_key', name='uq_program_bank_source_key'),
    )
    op.create_table(
        'rule_source_snapshot',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('source_type', sa.String(length=32), nullable=False),
        sa.Column('source_url', sa.Text(), nullable=True),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('published_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('content_hash', sa.String(length=64), nullable=False),
        sa.Column('raw_content', sa.Text(), nullable=False),
        sa.Column('parser_name', sa.String(length=128), nullable=True),
        sa.Column('parser_version', sa.String(length=64), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('content_hash'),
    )
    op.create_table(
        'bank_category',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('program_id', sa.Integer(), nullable=False),
        sa.Column('source_external_id', sa.String(length=255), nullable=True),
        sa.Column('source_key', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['program_id'], ['bank_cashback_program.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('program_id', 'source_key', name='uq_category_program_source_key'),
    )
    op.create_table(
        'bank_rule_revision',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('program_id', sa.Integer(), nullable=False),
        sa.Column('valid_from', sa.DateTime(timezone=True), nullable=False),
        sa.Column('valid_to', sa.DateTime(timezone=True), nullable=True),
        sa.Column('validity_confidence', sa.String(length=16), nullable=False),
        sa.Column('recorded_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('published_recorded_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('superseded_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('source_snapshot_id', sa.Integer(), nullable=False),
        sa.Column('completeness', sa.String(length=16), nullable=False),
        sa.Column('status', sa.String(length=16), nullable=False),
        sa.Column('normalized_hash', sa.String(length=64), nullable=False),
        sa.ForeignKeyConstraint(['program_id'], ['bank_cashback_program.id']),
        sa.ForeignKeyConstraint(['source_snapshot_id'], ['rule_source_snapshot.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('program_id', 'normalized_hash', name='uq_revision_program_hash'),
    )
    op.create_index(
        'ix_bank_rule_revision_period',
        'bank_rule_revision',
        ['program_id', 'valid_from', 'valid_to'],
    )
    op.create_table(
        'bank_category_revision',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('rule_revision_id', sa.Integer(), nullable=False),
        sa.Column('bank_category_id', sa.Integer(), nullable=False),
        sa.Column('original_name', sa.String(length=255), nullable=False),
        sa.Column('original_description', sa.Text(), nullable=True),
        sa.Column('source_payload', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['bank_category_id'], ['bank_category.id']),
        sa.ForeignKeyConstraint(['rule_revision_id'], ['bank_rule_revision.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'rule_revision_id',
            'bank_category_id',
            name='uq_category_revision_rule_category',
        ),
    )
    op.create_table(
        'bank_category_mcc_rule',
        sa.Column('category_revision_id', sa.Integer(), nullable=False),
        sa.Column('mcc_code', sa.String(length=4), nullable=False),
        sa.Column('effect', sa.String(length=16), nullable=False),
        sa.CheckConstraint("effect IN ('include', 'exclude')", name='ck_category_mcc_effect'),
        sa.ForeignKeyConstraint(['category_revision_id'], ['bank_category_revision.id']),
        sa.ForeignKeyConstraint(['mcc_code'], ['mcc_code.code']),
        sa.PrimaryKeyConstraint('category_revision_id', 'mcc_code', 'effect'),
    )
    op.create_index('ix_bank_category_mcc_rule_mcc', 'bank_category_mcc_rule', ['mcc_code'])
    op.create_table(
        'bank_program_exclusion',
        sa.Column('rule_revision_id', sa.Integer(), nullable=False),
        sa.Column('mcc_code', sa.String(length=4), nullable=False),
        sa.Column('reason', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['mcc_code'], ['mcc_code.code']),
        sa.ForeignKeyConstraint(['rule_revision_id'], ['bank_rule_revision.id']),
        sa.PrimaryKeyConstraint('rule_revision_id', 'mcc_code'),
    )
    op.create_index('ix_bank_program_exclusion_mcc', 'bank_program_exclusion', ['mcc_code'])
    op.create_table(
        'bank_rule_condition',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('rule_revision_id', sa.Integer(), nullable=False),
        sa.Column('category_revision_id', sa.Integer(), nullable=True),
        sa.Column('kind', sa.String(length=32), nullable=False),
        sa.Column('operator', sa.String(length=32), nullable=True),
        sa.Column('value', sa.Text(), nullable=True),
        sa.Column('original_text', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['category_revision_id'], ['bank_category_revision.id']),
        sa.ForeignKeyConstraint(['rule_revision_id'], ['bank_rule_revision.id']),
        sa.PrimaryKeyConstraint('id'),
    )


def downgrade():
    op.drop_table('bank_rule_condition')
    op.drop_index('ix_bank_program_exclusion_mcc', table_name='bank_program_exclusion')
    op.drop_table('bank_program_exclusion')
    op.drop_index('ix_bank_category_mcc_rule_mcc', table_name='bank_category_mcc_rule')
    op.drop_table('bank_category_mcc_rule')
    op.drop_table('bank_category_revision')
    op.drop_index('ix_bank_rule_revision_period', table_name='bank_rule_revision')
    op.drop_table('bank_rule_revision')
    op.drop_table('bank_category')
    op.drop_table('rule_source_snapshot')
    op.drop_table('bank_cashback_program')
    op.drop_table('mcc_code')

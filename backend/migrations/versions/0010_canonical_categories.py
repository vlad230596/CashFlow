"""Add canonical cashback categories, bank-category links and typed MCC exclusions.

Revision ID: 0010_canonical_categories
Revises: 0009_identity_icons
"""

import json

import sqlalchemy as sa
from alembic import context, op

from canonical_categories import load_bundled_canonical_categories, upsert_canonical_categories

revision = '0010_canonical_categories'
down_revision = '0009_identity_icons'
branch_labels = None
depends_on = None

EXCLUSION_KINDS = "('always', 'unless_category', 'conditional')"
CATEGORY_KINDS = (
    "('mcc', 'all_purchases', 'payment_method', 'bank_service', 'partner', 'other')"
)

canonical_category = sa.table(
    'canonical_category',
    sa.column('key', sa.String(length=64)),
    sa.column('group_key', sa.String(length=64)),
    sa.column('group_title', sa.String(length=128)),
    sa.column('title', sa.String(length=128)),
    sa.column('aliases', sa.JSON()),
    sa.column('default_priority', sa.Integer()),
    sa.column('sort_order', sa.Integer()),
)
canonical_category_mcc = sa.table(
    'canonical_category_mcc',
    sa.column('canonical_key', sa.String(length=64)),
    sa.column('mcc_code', sa.String(length=4)),
)


def upgrade():
    op.create_table(
        'canonical_category',
        sa.Column('key', sa.String(length=64), nullable=False),
        sa.Column('group_key', sa.String(length=64), nullable=False),
        sa.Column('group_title', sa.String(length=128), nullable=False),
        sa.Column('title', sa.String(length=128), nullable=False),
        sa.Column('aliases', sa.JSON(), nullable=False),
        sa.Column('default_priority', sa.Integer(), nullable=False),
        sa.Column('sort_order', sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint('key'),
    )
    op.create_table(
        'canonical_category_mcc',
        sa.Column('canonical_key', sa.String(length=64), nullable=False),
        sa.Column('mcc_code', sa.String(length=4), nullable=False),
        sa.ForeignKeyConstraint(['canonical_key'], ['canonical_category.key']),
        sa.ForeignKeyConstraint(['mcc_code'], ['mcc_code.code']),
        sa.PrimaryKeyConstraint('canonical_key', 'mcc_code'),
    )
    op.create_index('ix_canonical_category_mcc_mcc', 'canonical_category_mcc', ['mcc_code'])
    op.create_table(
        'bank_category_canonical_link',
        sa.Column('category_revision_id', sa.Integer(), nullable=False),
        sa.Column('canonical_key', sa.String(length=64), nullable=False),
        sa.Column('relation', sa.String(length=16), nullable=False),
        sa.Column('coverage', sa.Float(), nullable=True),
        sa.Column('source', sa.String(length=16), nullable=False),
        sa.CheckConstraint(
            "relation IN ('exact', 'broader', 'narrower')",
            name='ck_canonical_link_relation',
        ),
        sa.CheckConstraint("source IN ('auto', 'manual')", name='ck_canonical_link_source'),
        sa.ForeignKeyConstraint(['category_revision_id'], ['bank_category_revision.id']),
        sa.ForeignKeyConstraint(['canonical_key'], ['canonical_category.key']),
        sa.PrimaryKeyConstraint('category_revision_id', 'canonical_key'),
    )
    op.create_index(
        'ix_bank_category_canonical_link_key',
        'bank_category_canonical_link',
        ['canonical_key'],
    )
    op.add_column('bank_program_exclusion', sa.Column(
        'kind',
        sa.String(length=24),
        nullable=False,
        server_default='always',
    ))
    op.add_column('bank_category_revision', sa.Column(
        'kind',
        sa.String(length=24),
        nullable=False,
        server_default='mcc',
    ))
    # SQLite cannot add constraints to an existing table without a rebuild, which offline
    # (--sql) generation cannot reflect. The application validates the values everywhere.
    if op.get_context().dialect.name != 'sqlite':
        op.create_check_constraint(
            'ck_program_exclusion_kind',
            'bank_program_exclusion',
            f'kind IN {EXCLUSION_KINDS}',
        )
        op.create_check_constraint(
            'ck_category_revision_kind',
            'bank_category_revision',
            f'kind IN {CATEGORY_KINDS}',
        )

    rows = load_bundled_canonical_categories()
    if context.is_offline_mode():
        # Offline SQL cannot render JSON literals; a JSON string converts on insert.
        offline_category = sa.table(
            'canonical_category',
            *[sa.column(column.name, column.type) for column in canonical_category.columns
              if column.name != 'aliases'],
            sa.column('aliases', sa.Text()),
        )
        op.bulk_insert(offline_category, [
            {
                **{key: row[key] for key in (
                    'key', 'group_key', 'group_title', 'title',
                    'default_priority', 'sort_order',
                )},
                'aliases': json.dumps(row['aliases'], ensure_ascii=False),
            }
            for row in rows
        ])
        op.bulk_insert(canonical_category_mcc, [
            {'canonical_key': row['key'], 'mcc_code': code}
            for row in rows
            for code in row['core_mcc']
        ])
        return
    upsert_canonical_categories(op.get_bind(), canonical_category, canonical_category_mcc, rows)


def downgrade():
    if op.get_context().dialect.name != 'sqlite':
        op.drop_constraint('ck_category_revision_kind', 'bank_category_revision', type_='check')
        op.drop_constraint('ck_program_exclusion_kind', 'bank_program_exclusion', type_='check')
    with op.batch_alter_table('bank_category_revision') as batch:
        batch.drop_column('kind')
    with op.batch_alter_table('bank_program_exclusion') as batch:
        batch.drop_column('kind')
    op.drop_index('ix_bank_category_canonical_link_key', table_name='bank_category_canonical_link')
    op.drop_table('bank_category_canonical_link')
    op.drop_index('ix_canonical_category_mcc_mcc', table_name='canonical_category_mcc')
    op.drop_table('canonical_category_mcc')
    op.drop_table('canonical_category')

"""Add authentication users, sessions, and shared login throttling.

Revision ID: 0002_authentication
Revises: 0001_business_schema
"""

import sqlalchemy as sa
from alembic import op

revision = '0002_authentication'
down_revision = '0001_business_schema'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'auth_user',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('username', sa.String(length=64), nullable=False),
        sa.Column('password_hash', sa.Text(), nullable=False),
        sa.Column('role', sa.String(length=16), server_default='viewer', nullable=False),
        sa.Column('auth_enabled', sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('username'),
    )
    op.create_table(
        'auth_login_attempt',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('key_digest', sa.String(length=64), nullable=False),
        sa.Column('failed_count', sa.Integer(), server_default='0', nullable=False),
        sa.Column('window_started_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('blocked_until', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('key_digest'),
    )
    op.create_table(
        'auth_session',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('token_digest', sa.String(length=64), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['auth_user.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token_digest'),
    )


def downgrade():
    op.drop_table('auth_session')
    op.drop_table('auth_login_attempt')
    op.drop_table('auth_user')

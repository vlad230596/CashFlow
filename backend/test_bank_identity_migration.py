import importlib.util
from pathlib import Path

import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations


def test_bank_key_migration_backfills_known_names_and_roundtrips():
    path = Path(__file__).parent / "migrations/versions/0011_bank_identity.py"
    spec = importlib.util.spec_from_file_location("bank_identity_migration", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    engine = sa.create_engine("sqlite://")
    metadata = sa.MetaData()
    table = sa.Table(
        "bank",
        metadata,
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(50), nullable=False),
        sa.Column("icon_key", sa.String(24), nullable=False),
    )
    metadata.create_all(engine)
    with engine.begin() as connection:
        connection.execute(
            table.insert(),
            [
                {"id": 1, "name": "Альфа-Банк", "icon_key": "generic"},
                {"id": 2, "name": "Custom", "icon_key": "tbank"},
                {"id": 3, "name": "Тинькофф", "icon_key": "generic"},
                {"id": 4, "name": "Т-Банк", "icon_key": "generic"},
            ],
        )
        operations = Operations(MigrationContext.configure(connection))
        with Operations.context(operations.migration_context):
            module.upgrade()
        result = connection.execute(sa.text("SELECT id, bank_key FROM bank ORDER BY id")).all()
        assert result == [(1, "alfa"), (2, None), (3, "tbank"), (4, None)]
        assert any(item['column_names'] == ['bank_key'] and item['unique']
                   for item in sa.inspect(connection).get_indexes('bank'))
        with Operations.context(operations.migration_context):
            module.downgrade()
        assert "bank_key" not in {
            item["name"] for item in sa.inspect(connection).get_columns("bank")
        }
        assert connection.execute(sa.text("SELECT COUNT(*) FROM bank")).scalar() == 4

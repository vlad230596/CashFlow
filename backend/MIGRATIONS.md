# Database migrations

Schema changes are managed by Alembic. Runtime startup never creates or alters tables.

On Windows, do not pass a relative SQLite URL through `CASHFLOW_DATABASE_URL`: Flask resolves
relative SQLite paths against its instance directory while standalone Alembic resolves them
against the current directory. Use the default `alembic.ini` local URL or a fully absolute URL
such as `sqlite:///D:/Projects/CashFlow/backend/instance/cards.db`.

For a new database:

```powershell
$env:CASHFLOW_DATABASE_URL = 'postgresql+psycopg://...'
uv run alembic upgrade head
```

The legacy SQLite database is a read-only migration source. First migrate an empty PostgreSQL
database to `head`, then copy and verify the business data:

```powershell
uv run python scripts/migrate_sqlite_to_postgres.py `
  --source instance/cards.db `
  --database-url $env:CASHFLOW_DATABASE_URL
```

The importer refuses non-PostgreSQL targets, a database not at migration head, or non-empty
business tables. It preserves IDs, resets PostgreSQL sequences, and verifies exact row counts.
The unused legacy SQLite tables `card_owner` and `carduser` are intentionally not migrated.

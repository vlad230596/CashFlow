# Database migrations

Schema changes are managed by Alembic. Runtime startup never creates or alters tables.

Current repository head: `0013_promo_items` (2026-11-11). It adds the personal
`promo_item` table (promo codes/offers and expiring points: optional `expires_at`, verbatim
`source_text`, `used_at`/`archived_at`; "expired" is derived, never stored) with a unique
`(auth_user_id, client_id)` so an item created offline can be retried idempotently.

Previous head `0012_planned_payments` (2026-11-11) adds the personal
`planned_payment` table (recurring payments anchored to `anchor_date`, one-off payments
completed by `completed_at`; optional card with `ON DELETE SET NULL`) and
`planned_payment_record` (one confirmation per due date). Like every revision it must be
applied by the explicit deployment migration.

Previous head `0011_bank_identity` (2026-10-14) adds a nullable, unique
`bank.bank_key` for supported integration identities. Known legacy names are backfilled
using exact normalized aliases; custom banks remain null. If several old rows name the
same integration, only the lowest ID receives the key. Icons never determine identity.
Changing a display name or icon preserves the key. This revision requires the normal
explicit deployment migration; creating the file does not migrate deployed databases.

On Windows, do not pass a relative SQLite URL through `CASHFLOW_DATABASE_URL`: Flask resolves
relative SQLite paths against its instance directory while standalone Alembic resolves them
against the current directory. Use the default `alembic.ini` local URL or a fully absolute URL
such as `sqlite:///D:/Projects/CashFlow/backend/instance/cards.db`.

For a new database:

```powershell
$env:CASHFLOW_DATABASE_URL = 'postgresql+psycopg://...'
uv run alembic upgrade head
```

The legacy SQLite database is a read-only, one-time migration source. It is not a
production replica and must not be used for current-data questions. The importer
is intentionally pinned to target revision `0002_authentication`: migrate an
empty PostgreSQL database to that revision, import and verify the business data,
then run `alembic upgrade head`:

```powershell
uv run python scripts/migrate_sqlite_to_postgres.py `
  --source instance/cards.db `
  --database-url $env:CASHFLOW_DATABASE_URL

uv run alembic upgrade head
```

The importer refuses non-PostgreSQL targets, a database not at its pinned
`0002_authentication` revision, or non-empty business tables. It preserves IDs,
resets PostgreSQL sequences, and verifies exact row counts.
The unused legacy SQLite tables `card_owner` and `carduser` are intentionally not migrated.

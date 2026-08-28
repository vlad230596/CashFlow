import argparse
import os
import sqlite3
from datetime import datetime
from pathlib import Path

from sqlalchemy import create_engine, text

TABLES = ('bank', 'card_user', 'bank_card', 'cashback_category')
DATE_COLUMNS = {
    'bank_card': {'created_at'},
    'cashback_category': {'start_date', 'end_date'},
}
BOOLEAN_COLUMNS = {
    'bank_card': {'is_active'},
    'cashback_category': {'is_selected', 'is_selection_locked'},
}


def parse_args():
    parser = argparse.ArgumentParser(
        description='Copy CashFlow business data from legacy SQLite to empty PostgreSQL.',
    )
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument(
        '--database-url',
        default=os.environ.get('CASHFLOW_DATABASE_URL'),
        help='Target PostgreSQL URL; defaults to CASHFLOW_DATABASE_URL.',
    )
    return parser.parse_args()


def normalize_row(table, row):
    result = dict(row)
    for column in DATE_COLUMNS.get(table, set()):
        value = result.get(column)
        if value:
            result[column] = datetime.fromisoformat(value)
    for column in BOOLEAN_COLUMNS.get(table, set()):
        value = result.get(column)
        if value is not None:
            result[column] = bool(value)
    return result


def main():
    args = parse_args()
    source = args.source.resolve()
    if not source.is_file():
        raise SystemExit(f'SQLite source does not exist: {source}')
    if not args.database_url:
        raise SystemExit('Target PostgreSQL URL is required.')

    engine = create_engine(args.database_url)
    if engine.dialect.name != 'postgresql':
        raise SystemExit('Target must be PostgreSQL.')

    source_connection = sqlite3.connect(f'file:{source.as_posix()}?mode=ro', uri=True)
    source_connection.row_factory = sqlite3.Row
    try:
        source_rows = {
            table: [
                normalize_row(table, row)
                for row in source_connection.execute(f'SELECT * FROM "{table}" ORDER BY id')
            ]
            for table in TABLES
        }
    finally:
        source_connection.close()

    with engine.begin() as target:
        revision = target.execute(text('SELECT version_num FROM alembic_version')).scalar_one()
        if revision != '0002_authentication':
            raise SystemExit(
                f'Target migration is {revision!r}; expected 0002_authentication.'
            )

        nonempty = {
            table: target.execute(text(f'SELECT COUNT(*) FROM "{table}"')).scalar_one()
            for table in TABLES
        }
        if any(nonempty.values()):
            raise SystemExit(f'Target business tables must be empty: {nonempty}')

        for table in TABLES:
            rows = source_rows[table]
            if not rows:
                continue
            columns = tuple(rows[0])
            column_sql = ', '.join(f'"{column}"' for column in columns)
            value_sql = ', '.join(f':{column}' for column in columns)
            target.execute(
                text(f'INSERT INTO "{table}" ({column_sql}) VALUES ({value_sql})'),
                rows,
            )
            target.execute(text(
                f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), "
                f'GREATEST((SELECT MAX(id) FROM "{table}"), 1), '
                f'EXISTS (SELECT 1 FROM "{table}"))'
            ))

        target_counts = {
            table: target.execute(text(f'SELECT COUNT(*) FROM "{table}"')).scalar_one()
            for table in TABLES
        }
        source_counts = {table: len(rows) for table, rows in source_rows.items()}
        if target_counts != source_counts:
            raise RuntimeError(
                f'Migration count verification failed: source={source_counts}, '
                f'target={target_counts}'
            )

    print(f'CashFlow data migration completed and verified: {source_counts}')


if __name__ == '__main__':
    main()

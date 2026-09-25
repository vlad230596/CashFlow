import csv
import hashlib
import io
import re
from pathlib import Path

import sqlalchemy as sa

MCC_CATALOG_SOURCE_URL = "https://mcc-codes.ru/code/export/csv"
MCC_CATALOG_SHA256 = "a9276fc10e942dc8b52c7a48c78f9662216482d48c462920283333ef5a86c1df"
MCC_CATALOG_ROW_COUNT = 1077
MCC_CATALOG_PATH = Path(__file__).with_name("data") / "mcc_codes.csv"
MCC_PATTERN = re.compile(r"^\d{4}$")
EXPECTED_COLUMNS = ["MCC", "Название", "Описание"]


def parse_mcc_catalog(payload: bytes, *, verify_snapshot: bool = False) -> list[dict[str, str]]:
    if verify_snapshot:
        digest = hashlib.sha256(payload).hexdigest()
        if digest != MCC_CATALOG_SHA256:
            raise ValueError(
                f"Unexpected MCC catalogue SHA-256: {digest}; expected {MCC_CATALOG_SHA256}"
            )

    try:
        text = payload.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise ValueError("MCC catalogue must be UTF-8 encoded") from error

    reader = csv.DictReader(io.StringIO(text, newline=""))
    if reader.fieldnames != EXPECTED_COLUMNS:
        raise ValueError(
            f"Unexpected MCC catalogue columns: {reader.fieldnames!r}; "
            f"expected {EXPECTED_COLUMNS!r}"
        )

    rows = []
    seen_codes = set()
    for line_number, source_row in enumerate(reader, start=2):
        code = (source_row["MCC"] or "").strip()
        title = (source_row["Название"] or "").strip()
        description = (source_row["Описание"] or "").strip()
        if not MCC_PATTERN.fullmatch(code):
            raise ValueError(f"Invalid MCC at CSV line {line_number}: {code!r}")
        if not title:
            raise ValueError(f"Missing MCC title at CSV line {line_number}")
        if code in seen_codes:
            raise ValueError(f"Duplicate MCC at CSV line {line_number}: {code}")
        seen_codes.add(code)
        rows.append(
            {
                "code": code,
                "title": title,
                "description": description or None,
                "reference_source": MCC_CATALOG_SOURCE_URL,
            }
        )

    if verify_snapshot and len(rows) != MCC_CATALOG_ROW_COUNT:
        raise ValueError(
            f"Unexpected MCC catalogue row count: {len(rows)}; expected {MCC_CATALOG_ROW_COUNT}"
        )
    return rows


def load_bundled_mcc_catalog() -> list[dict[str, str]]:
    return parse_mcc_catalog(MCC_CATALOG_PATH.read_bytes(), verify_snapshot=True)


def upsert_mcc_catalog(connection, mcc_table, rows: list[dict[str, str]]) -> tuple[int, int]:
    existing_codes = set()
    codes = [row["code"] for row in rows]
    for start in range(0, len(codes), 500):
        chunk = codes[start : start + 500]
        existing_codes.update(
            connection.execute(
                sa.select(mcc_table.c.code).where(mcc_table.c.code.in_(chunk))
            ).scalars()
        )

    new_rows = [row for row in rows if row["code"] not in existing_codes]
    existing_rows = [row for row in rows if row["code"] in existing_codes]
    if new_rows:
        connection.execute(sa.insert(mcc_table), new_rows)
    if existing_rows:
        update_statement = (
            sa.update(mcc_table)
            .where(mcc_table.c.code == sa.bindparam("catalog_code"))
            .values(
                title=sa.bindparam("catalog_title"),
                description=sa.bindparam("catalog_description"),
                reference_source=sa.bindparam("catalog_reference_source"),
            )
        )
        connection.execute(
            update_statement,
            [
                {
                    "catalog_code": row["code"],
                    "catalog_title": row["title"],
                    "catalog_description": row["description"],
                    "catalog_reference_source": row["reference_source"],
                }
                for row in existing_rows
            ],
        )
    return len(new_rows), len(existing_rows)

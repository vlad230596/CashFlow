import pytest
import sqlalchemy as sa

from mcc_catalog import (
    MCC_CATALOG_ROW_COUNT,
    MCC_CATALOG_SOURCE_URL,
    load_bundled_mcc_catalog,
    parse_mcc_catalog,
    upsert_mcc_catalog,
)


def test_bundled_catalogue_is_valid_and_keeps_leading_zeroes():
    rows = load_bundled_mcc_catalog()

    assert len(rows) == MCC_CATALOG_ROW_COUNT
    assert len({row["code"] for row in rows}) == MCC_CATALOG_ROW_COUNT
    assert next(row for row in rows if row["code"] == "0742")["title"] == "Ветеринарные услуги"
    assert next(row for row in rows if row["code"] == "5411")["title"]
    assert all(row["reference_source"] == MCC_CATALOG_SOURCE_URL for row in rows)


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        (b"MCC,wrong\n0742,title\n", "Unexpected MCC catalogue columns"),
        ("MCC,Название,Описание\n742,Ветеринария,\n".encode(), "Invalid MCC"),
        (
            "MCC,Название,Описание\n0742,Ветеринария,\n0742,Повтор,\n".encode(),
            "Duplicate MCC",
        ),
    ],
)
def test_catalogue_validation_rejects_malformed_data(payload, message):
    with pytest.raises(ValueError, match=message):
        parse_mcc_catalog(payload)


def test_upsert_inserts_new_rows_and_enriches_existing_rows():
    engine = sa.create_engine("sqlite://")
    metadata = sa.MetaData()
    table = sa.Table(
        "mcc_code",
        metadata,
        sa.Column("code", sa.String(4), primary_key=True),
        sa.Column("title", sa.String(255)),
        sa.Column("description", sa.Text()),
        sa.Column("reference_source", sa.Text()),
    )
    metadata.create_all(engine)
    with engine.begin() as connection:
        connection.execute(sa.insert(table), {"code": "0742"})
        created, updated = upsert_mcc_catalog(
            connection,
            table,
            [
                {
                    "code": "0742",
                    "title": "Ветеринарные услуги",
                    "description": "Описание",
                    "reference_source": MCC_CATALOG_SOURCE_URL,
                },
                {
                    "code": "5411",
                    "title": "Супермаркеты",
                    "description": None,
                    "reference_source": MCC_CATALOG_SOURCE_URL,
                },
            ],
        )
        stored = connection.execute(sa.select(table).order_by(table.c.code)).mappings().all()

    assert (created, updated) == (1, 1)
    assert stored[0]["title"] == "Ветеринарные услуги"
    assert stored[0]["reference_source"] == MCC_CATALOG_SOURCE_URL
    assert stored[1]["code"] == "5411"

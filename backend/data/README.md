# MCC catalogue snapshot

`mcc_codes.csv` was downloaded from
<https://mcc-codes.ru/code/export/csv> on 2026-09-25.

- Source response `Last-Modified`: `Thu, 24 Sep 2026 04:00:01 GMT`
- SHA-256: `a9276fc10e942dc8b52c7a48c78f9662216482d48c462920283333ef5a86c1df`
- Parsed rows: `1077`

The snapshot is used once by Alembic migration `0007_seed_mcc_catalog`. It does not configure
periodic synchronization with the source website. Every imported row records the export URL in
`mcc_code.reference_source`.

# Canonical categories

`canonical_categories.json` defines the 43 unified cashback categories in 10 groups that CashFlow
uses for search and comparison, with search aliases, a default need priority and a core MCC set.
Alembic migration `0010_canonical_categories` loads it into `canonical_category` and
`canonical_category_mcc`. Bank categories are linked to canonical ones by MCC overlap
(`canonical_categories.compute_canonical_links`), or by hand through `canonicalKeys` in a snapshot.

# Bank MCC rules, October 2026

- `bank_mcc_2026-10.json` is a manual transcription of six bank documents collected on 2026-10-05:
  Ozon Bank (PDF), Alfa-Bank «Альфа Выгодно» (scanned PDF), VTB «Мультибонус» rules (PDF),
  T-Bank category and exclusion lists (PDF), Yandex Pay promotion rules
  (<https://yandex.ru/legal/card_and_pay_points/ru/>, edition of 2026-09-29) and the SberSpasibo
  summary (PDF). Ranges are kept as written; known contradictions in the documents are recorded
  as conditions rather than resolved silently.
- `bank_mcc_2026-10.csv` is the same data flattened to one row per bank, group and MCC.
- `bank_mcc_rules/2026-10/<bank>.json` are `bank_mcc_rules_snapshot` v1 documents built from the
  transcription by `scripts/build_bank_mcc_snapshots.py`. `bankId` is a bank key (`ozon`, `alfa`,
  `vtb`, `tbank`, `yandex`, `sber`) resolved through `BANK_IMPORT_NAMES`, so the same files work in
  every environment.

Import into a database with `flask --app main import-bank-mcc-rules` (all bundled files, published,
idempotent; `--draft` keeps drafts, `--create-missing-banks` is for empty local databases), or
upload one file per bank through «Ещё → Настройки MCC → Новый импорт» and publish after review.

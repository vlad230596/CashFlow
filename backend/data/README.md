# MCC catalogue snapshot

`mcc_codes.csv` was downloaded from
<https://mcc-codes.ru/code/export/csv> on 2026-09-25.

- Source response `Last-Modified`: `Thu, 24 Sep 2026 04:00:01 GMT`
- SHA-256: `a9276fc10e942dc8b52c7a48c78f9662216482d48c462920283333ef5a86c1df`
- Parsed rows: `1077`

The snapshot is used once by Alembic migration `0007_seed_mcc_catalog`. It does not configure
periodic synchronization with the source website. Every imported row records the export URL in
`mcc_code.reference_source`.

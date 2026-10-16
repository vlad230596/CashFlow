# Offline MCC contract, schema 3

`GET /api/mcc/offline-snapshot?schema=3&as_of=2026-10-15` returns a complete,
authenticated snapshot. Omitting `schema` retains the schema 2 compatibility
response. `GET /api/mcc/offline-manifest?as_of=...` returns only schema, date and
version fields; it does not build the rule index. These are read-only endpoints.

An explicit `as_of` has the same parsing and period semantics as the existing
individual MCC endpoints: a date denotes midnight UTC; an ISO instant retains
its instant. Moscow wall time determines whether a personal cashback offer is
inside its half-open period `[start, end)`. Schema 3 defaults to the current
Moscow calendar date when `as_of` is omitted. Clients should pass the chosen date.

## Entities and joins

The response contains the following fields. JSON object IDs are decimal strings;
entity IDs and category-ID arrays contain integers.

| Field | Contents |
| --- | --- |
| `schema_version` | Integer `3` |
| `as_of`, `generated_at` | ISO UTC instants |
| `content_version` | Opaque account/date/content identity |
| `rules_version` | Opaque reference/rules identity |
| `bindings_version` | Opaque offer-binding identity; includes its rules dependency |
| `catalogue` | Ordered `{code, title}` reference rows |
| `mcc_details` | Code → full existing MCC detail JSON |
| `banks` | Bank ID → existing bank JSON |
| `revisions` | Ordered existing published revision payloads, once per program |
| `canonical_categories` | Canonical key → existing canonical summary JSON |
| `canonical_mcc` | MCC → ordered canonical keys; missing means empty |
| `mcc_defaults` | Revision ID → default index entry |
| `mcc_index` | MCC → revision ID → index entry overriding that default |
| `offer_bindings` | Offer ID → `{bank_id, active, category_ids_by_revision}` |

An index entry is `{status, category_ids, earning_category_ids, exclusion_index}`.
`exclusion_index` is null or a zero-based position in that revision's `exclusions`.
`category_ids` identifies matched categories, including their existing canonical
links. `earning_category_ids` is the server decision, including all-purchases
eligibility and exclusion precedence. The client joins references and never
re-evaluates bank rules. A missing per-code entry uses the revision's
`mcc_defaults`. This also explains a valid four-digit code absent from the
catalogue: its MCC detail is `{code}`, with empty canonical categories.

To recreate the existing MCC lookup response, iterate `revisions` in response
order. Select categories by `category_ids`, preserving revision category order,
and project their `id`, `name`, `kind`, and `canonical`. Join the indexed exclusion.
Select active offers for that bank whose category bindings for that revision
intersect `earning_category_ids`; sort their IDs numerically. Read the remaining
program/completeness fields directly from the revision.

To recreate an offer's MCC details at the requested explicit date, take the first
revision with nonempty category bindings for that offer, then the first matching
category in its existing category order. Join included/excluded MCC titles from
`mcc_details` and preserve the revision's source and exclusions. No category
binding means the existing individual endpoint's not-published result. Inactive
offers can still have rule details, but never appear in lookup earning offers.

There is no expanded per-code response matrix, per-offer copied rule document,
generic tree codec, or arbitrary `$ref` vocabulary in schema 3. Schema 2 retains
its existing experimental codec for old clients.

## Conditional requests and invalidation

Both endpoints return `ETag: W/"mcc-v3-<content_version>"`,
`Cache-Control: private, max-age=0, must-revalidate`, and `Vary: Authorization`.
Send the exact ETag in `If-None-Match`. A matching authenticated request returns
304 with no body, before revision serialization, rule-index building or offer
binding building. `ETag` is exposed and `If-None-Match` allowed by CORS.

The weak validator intentionally excludes `generated_at`. It includes account,
exact requested instant, rule and binding versions. Another account cannot
revalidate a first account's response. A 304 confirms the stored document's
semantic content; clients retain that document and track their validation time.

Source fingerprints read reference fields, canonical mappings, banks/programs,
selected revision metadata and normalized hashes, source metadata, category
identities, and projected offer identity/name/period rows. Existing imported
revision children are immutable. There is no full MCC-by-program evaluation on
the unchanged path. Reference changes, imported/published revision selection,
bank presentation, offer creation/removal/name/card/period, and date boundaries
invalidate the appropriate identity. Bindings include their rules dependency.
Selection flags/percentage changes that cannot affect MCC eligibility do not
invalidate this document.

The process keeps at most four immutable rule-content versions behind a lock.
Dynamic offers are bound separately; changing an offer reuses unchanged rule
entities and the index. This is a bounded acceleration cache, not a database.

## Verification

`test_mcc_snapshot_v3.py` checks all 1105 bundled reference MCCs against the
existing independent API evaluator, plus synthetic exclusions, conditional and
category-only rules, all-purchases defaults, multiple programs, historical
offers, missing bindings, date boundaries, account separation, and invalidation.
It verifies that 304 bypasses expensive builders and an offer change reuses the
rule-content cache. The shared synthetic
`contracts/mcc-offline-v3.fixture.json` contains the snapshot and individual API
goldens for Dart joins; a backend test verifies that fixture against current API
output. These checks use isolated synthetic databases, never production data.

"""Read-only research: synthetic in-memory DB, no deployed or local data access.
Run from root: backend/.venv/Scripts/python.exe docs/research/mcc-offline-cache/benchmark.py
"""
import base64
import gzip
import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
os.environ['CASHFLOW_DATABASE_URL'] = 'sqlite://'
os.environ['CASHFLOW_ENVIRONMENT'] = 'test'
sys.path.insert(0, str(ROOT / 'backend'))
import main as m
from canonical_categories import load_bundled_canonical_categories, upsert_canonical_categories
from mcc_catalog import load_bundled_mcc_catalog, upsert_mcc_catalog
from mcc_snapshot import compact_snapshot


def timed(function, repeats=3):
    durations = []
    for _ in range(repeats):
        started = time.perf_counter()
        value = function()
        durations.append((time.perf_counter() - started) * 1000)
    return value, round(statistics.median(durations), 3)


def measure(document):
    text, serialize_ms = timed(lambda: json.dumps(document, ensure_ascii=False, separators=(',', ':')))
    raw = text.encode('utf-8')
    packed, gzip_ms = timed(lambda: gzip.compress(raw, compresslevel=6, mtime=0))
    _, parse_ms = timed(lambda: json.loads(text))
    return {'utf8_bytes': len(raw), 'utf16_code_units': len(text.encode('utf-16-le')) // 2,
            'gzip6_bytes': len(packed), 'gzip_base64_chars': len(base64.b64encode(packed)),
            'json_serialize_ms': serialize_ms, 'json_parse_ms': parse_ms, 'gzip_ms': gzip_ms}


with m.app.app_context():
    m.db.create_all()
    conn = m.db.session.connection()
    upsert_mcc_catalog(conn, m.MccCode.__table__, load_bundled_mcc_catalog())
    upsert_canonical_categories(conn, m.CanonicalCategory.__table__, m.CanonicalCategoryMcc.__table__,
                                load_bundled_canonical_categories())
    owner = m.CardUser(name='Synthetic benchmark owner')
    m.db.session.add(owner)
    m.db.session.flush()
    for path in sorted((ROOT / 'backend/data/bank_mcc_rules/2026-10').glob('*.json')):
        document = json.loads(path.read_text(encoding='utf-8'))
        key = document['bankId']
        bank = m.Bank(name=m.BANK_IMPORT_NAMES[key], bank_key=key, icon_key=key)
        m.db.session.add(bank)
        m.db.session.flush()
        document['bankId'] = bank.id
        revision, _ = m._import_mcc_snapshot(document)
        m._publish_mcc_revision(revision)
        for copy in range(6):
            card = m.BankCard(bank_id=bank.id, user_id=owner.id, payment_system='Mir',
                             card_type='physical', last_four_digits=f'{copy:04}')
            m.db.session.add(card)
            m.db.session.flush()
            for index in range(copy, 112, 6):
                category = document['categories'][index % len(document['categories'])]
                m.db.session.add(m.CashbackCategory(card_id=card.id, name=category['name'],
                    cashback_percent=5, start_date=datetime(2026, 10, 1), end_date=datetime(2026, 11, 1),
                    is_selected=True, is_bank_confirmed=True))
    m.db.session.commit()
    as_of = datetime(2026, 10, 14, 9, tzinfo=timezone.utc)
    original = m.compact_snapshot
    m.compact_snapshot = lambda value: value
    expanded, expanded_build_ms = timed(lambda: m._build_mcc_offline_snapshot(as_of.isoformat()))
    m.compact_snapshot = original
    compact, compact_extra_ms = timed(lambda: compact_snapshot(expanded))
    published = list(m._published_payloads(as_of))
    active = m._active_offers_by_bank(as_of)

    def normalized_document():
        local_published = list(m._published_payloads(as_of))
        local_active = m._active_offers_by_bank(as_of)
        return {'schema_version': 'research-normalized', 'as_of': as_of.isoformat(),
                'catalogue': [item.to_dict() for item in m.MccCode.query.order_by(m.MccCode.code)],
                'canonical_categories': [m._canonical_category_to_dict(item) for item in m.CanonicalCategory.query.all()],
                'canonical_mcc': [{'key': row.canonical_key, 'mcc': row.mcc_code} for row in m.CanonicalCategoryMcc.query.all()],
                'bank_rules': [{'bank': bank.to_dict(), 'revision': payload} for bank, payload in local_published],
                'offers': [{'id': offer.id, 'bank_id': bank_id, 'card_id': offer.card_id, 'name': offer.name,
                    'start_date': offer.start_date.isoformat(), 'end_date': offer.end_date.isoformat(),
                    'type': offer.category_type, 'percent': offer.cashback_percent,
                    'is_selected': offer.is_selected, 'is_bank_confirmed': offer.is_bank_confirmed}
                    for bank_id, offers in local_active.items() for offer in offers]}
    normalized, normalized_build_ms = timed(normalized_document)
    indexed = {**normalized, 'mcc_index': {
        code: [{'revision_id': bank['revision_id'], 'status': bank['status'],
                'category_ids': [category['id'] for category in bank['categories']],
                'offer_ids': bank['offer_ids']} for bank in lookup['banks']]
        for code, lookup in expanded['lookups'].items()}}
    revisions = {payload['id']: (bank, payload) for bank, payload in published}
    def from_index(code):
        output = []
        for entry in indexed['mcc_index'][code]:
            bank, revision = revisions[entry['revision_id']]
            categories = {item['id']: item for item in revision['categories']}
            output.append({'bank': bank.to_dict(), 'revision_id': revision['id'],
                'program': revision['program'], 'completeness': revision['completeness'],
                'status': entry['status'],
                'exclusion': next((item for item in revision['exclusions'] if item['mcc'] == code), None),
                'categories': [{key: categories[category_id][key] for key in ('id','name','kind','canonical')}
                               for category_id in entry['category_ids']],
                'offer_ids': entry['offer_ids']})
        return output

    def evaluate(code):
        result = []
        for bank, payload in published:
            evaluation = m._evaluate_mcc_in_revision(payload, code)
            result.append({'bank': bank.to_dict(), **evaluation,
                           'offer_ids': m._offers_earning_mcc(active.get(bank.id, []), payload, evaluation, code)})
        return result
    started = time.perf_counter()
    for code, lookup in expanded['lookups'].items():
        assert evaluate(code) == lookup['banks'], code
        assert from_index(code) == lookup['banks'], code
    parity_ms = (time.perf_counter() - started) * 1000
    _, lookup_ms = timed(lambda: evaluate('5411'), repeats=20)
    result = {
        'scope': 'synthetic in-memory SQLite; bundled reference/rules; 112 offers per bank across six cards',
        'mcc_count': len(expanded['catalogue']), 'program_count': len(published),
        'offers_count': sum(len(offers) for offers in active.values()),
        'expanded': measure(expanded), 'compact_schema2': measure(compact),
        'normalized_revisions_prototype': measure(normalized),
        'normalized_with_precomputed_index': measure(indexed),
        'server_expanded_build_ms': expanded_build_ms, 'compact_extra_ms': compact_extra_ms,
        'normalized_assembly_ms': normalized_build_ms,
        'python_lookup_5411_median_ms': lookup_ms, 'all_code_verdict_parity_ms': round(parity_ms, 3),
        'parity': 'all MCC bank verdicts and offer_ids match current API at the same as_of',
        'limitations': 'Python timings only; normalized evaluator prototype is not implemented/tested in Dart; no browser/Android/network profiling',
    }
    output = Path(__file__).with_name('results.json')
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))



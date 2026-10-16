import 'package:cashflow/models/mcc_rule_model.dart';
import 'package:cashflow/services/mcc_snapshot_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = MccRuleRevisionModel(
      id: 1,
      bankId: 1,
      programKey: 'cashback',
      programName: 'Cashback',
      validFrom: DateTime(2026, 10),
      validityConfidence: 'exact',
      completeness: 'exact_mcc',
      status: 'published',
      recordedAt: DateTime(2026, 10),
      sourceType: 'public_page',
      globalExcludedMcc: [],
      conditions: [],
      categories: [
        const MccBankCategoryModel(
            id: 1,
            sourceKey: 'shops',
            name: 'Shops',
            includedMcc: ['5411'],
            excludedMcc: [],
            conditions: [],
            completeness: 'exact_mcc'),
      ]);
  Map<String, dynamic> document() => {
        'schemaVersion': 1,
        'kind': 'bank_mcc_rules_snapshot',
        'bankId': 1,
        'programKey': 'cashback',
        'programName': 'Cashback',
        'validity': {'from': '2026-10-01', 'confidence': 'exact'},
        'completeness': 'exact_mcc',
        'source': {'type': 'public_page'},
        'categories': [
          {
            'sourceKey': 'shops',
            'name': 'Shops',
            'includedMcc': ['5411'],
            'excludedMcc': []
          }
        ],
      };
  test('unchanged snapshot remains unchanged', () {
    expect(
        analyzeMccSnapshot(document(), base, 1, null)
            .count(MccChangeKind.changed),
        0);
  });
  test('condition-only changes are visible', () {
    final input = document();
    (input['categories'] as List).single['conditions'] = [
      {'kind': 'minimum_purchase', 'originalText': 'От 500 рублей'}
    ];
    final result = analyzeMccSnapshot(input, base, 1, null);
    expect(result.count(MccChangeKind.changed), 1);
  });
  test('canonical-only changes are visible', () {
    final input = document();
    (input['categories'] as List).single['canonicalKeys'] = ['groceries'];
    expect(
        analyzeMccSnapshot(input, base, 1, null).count(MccChangeKind.changed),
        1);
  });
  test('program exclusion and condition changes are visible', () {
    final input = document()..['globalExcludedMcc'] = ['4829'];
    input['conditions'] = [
      {'kind': 'limit', 'originalText': 'До 1000 рублей'}
    ];
    final result = analyzeMccSnapshot(input, base, 1, null);
    expect(result.changes.last.sourceKey, '__program__');
    expect(result.count(MccChangeKind.changed), 1);
  });
  test('server preview replaces local diff with authoritative changes', () {
    final result = analysisFromMccPreview({
      'normalized_document': document(),
      'diff': {
        'categories': [
          {
            'source_key': 'shops',
            'status': 'changed',
            'changed_fields': ['conditions']
          }
        ],
        'changed_fields': ['exclusions']
      },
    }, base, 1, null);
    expect(result.count(MccChangeKind.changed), 2);
    expect(result.changes.first.name, 'Shops');
    expect(result.changes.first.details, 'conditions');
    expect(result.changes.last.sourceKey, '__program__');
  });
}

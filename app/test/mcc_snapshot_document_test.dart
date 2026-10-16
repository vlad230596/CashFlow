@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'package:cashflow/services/mcc_snapshot_document.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture() => jsonDecode(
        File('../contracts/mcc-offline-v3.fixture.json').readAsStringSync())
    as Map<String, dynamic>;

void main() {
  test('schema 3 entity joins exactly match Python API golden responses', () {
    final fixture = _fixture();
    final snapshot = fixture['snapshot'] as Map<String, dynamic>;
    expect(MccSnapshotDocument.isValid(snapshot), isTrue);
    final reader = MccSnapshotDocument(snapshot);
    for (final item in (fixture['lookups'] as Map<String, dynamic>).entries) {
      expect(reader.hasDocument('lookups', item.key), isTrue);
      expect(reader.document('lookups', item.key), item.value,
          reason: 'MCC ${item.key}');
    }
    for (final item
        in (fixture['offer_rules'] as Map<String, dynamic>).entries) {
      expect(reader.hasDocument('offer_rules', item.key), isTrue);
      expect(reader.document('offer_rules', item.key), item.value,
          reason: 'offer ${item.key}');
    }
    expect(reader.hasDocument('lookups', 'invalid'), isFalse);
    expect(reader.hasDocument('offer_rules', '9999'), isFalse);
  });

  test(
      'schema 3 rejects dangling category, exclusion, bank and canonical references',
      () {
    for (final corrupt in <void Function(Map<String, dynamic>)>[
      (snapshot) => (snapshot['banks'] as Map).clear(),
      (snapshot) => (snapshot['canonical_categories'] as Map).clear(),
      (snapshot) {
        final index = ((snapshot['mcc_index'] as Map).values.first as Map)
            .values
            .first as Map;
        index['category_ids'] = [999999];
      },
      (snapshot) {
        final index = ((snapshot['mcc_index'] as Map).values.first as Map)
            .values
            .first as Map;
        index['exclusion_index'] = 999999;
      },
      (snapshot) => ((snapshot['offer_bindings'] as Map).values.first
          as Map)['bank_id'] = 999999,
    ]) {
      final snapshot = _fixture()['snapshot'] as Map<String, dynamic>;
      corrupt(snapshot);
      expect(MccSnapshotDocument.isValid(snapshot), isFalse);
    }
  });

  test('schema 2 shared references remain readable and recursive refs rejected',
      () {
    final bank = <String, dynamic>{
      'bank': {'id': 1, 'name': 'Synthetic'},
      'status': 'excluded',
      'completeness': 'exact_mcc',
      'program': {'name': 'Synthetic'},
      'exclusion': null,
      'categories': [],
      'offer_ids': []
    };
    final snapshot = jsonDecode(jsonEncode(<String, dynamic>{
      'schema_version': 2,
      'catalogue': [
        {'code': '0001'}
      ],
      'mcc_details': {
        '0001': {'code': '0001'}
      },
      'canonical': {},
      'lookup_refs': {
        '0001': ['0']
      },
      'lookup_payloads': {
        '0': {r'$ref': 'bank'}
      },
      'offer_rule_refs': {'17': null},
      'offer_rule_payloads': {},
      'shared_payloads': {'bank': bank}
    })) as Map<String, dynamic>;
    expect(MccSnapshotDocument.isValid(snapshot), isTrue);
    final reader = MccSnapshotDocument(snapshot);
    expect(reader.document('lookups', '0001')!['banks'], [bank]);
    expect(reader.hasDocument('offer_rules', '17'), isTrue);
    expect(reader.document('offer_rules', '17'), isNull);
    (snapshot['shared_payloads'] as Map)['bank'] = {r'$ref': 'bank'};
    expect(MccSnapshotDocument.isValid(snapshot), isFalse);
  });
}

@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:cashflow/services/mcc_cache_storage_web.dart';
import 'package:cashflow/services/mcc_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('IndexedDB persists after reopen, isolates keys, and abort rolls back',
      () async {
    final name = 'cashflow-mcc-test-${DateTime.now().microsecondsSinceEpoch}';
    final first = IndexedDbMccStorage(databaseName: name);
    await first.write('account:1:date', 'valid');
    await first.write('account:2:date', 'other account');
    final reopened = IndexedDbMccStorage(databaseName: name);
    expect(await reopened.read('account:1:date'), 'valid');
    expect(await reopened.keys(), {'account:1:date', 'account:2:date'});
    final aborted = IndexedDbMccStorage(
        databaseName: name,
        beforeCommit: (transaction) {
          transaction.abort();
        });
    await expectLater(
        aborted.write('account:1:date', 'must roll back'), throwsStateError);
    expect(await reopened.read('account:1:date'), 'valid');
    expect(await reopened.read('account:2:date'), 'other account');
    await first.remove('account:1:date');
    await first.remove('account:2:date');
    expect(await reopened.keys(), isEmpty);
  });

  test('IndexedDB preserves complete base and next-day overlay after restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final name = 'cashflow-repository-${DateTime.now().microsecondsSinceEpoch}';
    final storage = IndexedDbMccStorage(databaseName: name);
    final cache = MccCacheStore(storage: storage);
    Map<String, dynamic> lookup(String code, int offer) => {
          'mcc': {'code': code, 'title': 'MCC $code'},
          'banks': [
            {
              'bank': {'id': 2, 'name': 'Bank'},
              'program': {'name': 'Rewards'},
              'status': 'category',
              'offer_ids': [offer]
            }
          ]
        };
    final base = <String, dynamic>{
      'schema_version': 1,
      '_complete': true,
      'as_of': '2026-10-14T12:00:00+03:00',
      'generated_at': '2026-10-14T09:00:00Z',
      'catalogue': [
        for (final code in ['5411', '5812'])
          {'code': code, 'title': 'MCC $code'}
      ],
      'lookups': {
        for (final code in ['5411', '5812']) code: lookup(code, 5)
      },
      'offer_rules': <String, dynamic>{}
    };
    final key = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    expect(await cache.write(key, base), isTrue);
    await cache.saveLatest('https://one.test', 7, base, snapshotKey: key);
    final updated = Completer<void>();
    final online = MccRepository(
        cache: cache,
        get: (path, _) async {
          if (path.contains('/5411/')) {
            return http.Response(json.encode(lookup('5411', 9)), 200);
          }
          throw http.ClientException('offline');
        },
        onChanged: () {
          if (!updated.isCompleted) updated.complete();
        })
      ..activate('https://one.test', 7, DateTime(2026, 10, 15), 1);
    final previous = await online.document('lookups', '5411');
    expect(previous!['_offer_links_current'], isFalse);
    await updated.future;
    online.dispose();

    final reopened = MccRepository(
        cache: MccCacheStore(storage: IndexedDbMccStorage(databaseName: name)),
        get: (_, __) async => throw http.ClientException('offline'),
        onChanged: () {})
      ..activate('https://one.test', 7, DateTime(2026, 10, 15), 2);
    final fresh = await reopened.document('lookups', '5411');
    expect((fresh!['banks'] as List).single['offer_ids'], [9]);
    final unseen = await reopened.document('lookups', '5812');
    expect(unseen!['mcc']['title'], 'MCC 5812');
    expect(unseen['_offer_links_current'], isFalse);
    expect((unseen['banks'] as List).single['offer_ids'], isEmpty);
    reopened.dispose();
    for (final key in await storage.keys()) {
      await storage.remove(key);
    }
  });
}

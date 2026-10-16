import 'dart:async';
import 'dart:convert';

import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:cashflow/services/mcc_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> snapshot({String day = '2026-10-14', int offer = 5}) => {
      'schema_version': 1,
      'as_of': '${day}T12:00:00+03:00',
      'generated_at': '${day}T09:00:00Z',
      '_complete': true,
      '_etag': '"base"',
      'catalogue': [
        {'code': '5411', 'title': 'Groceries'},
        {'code': '5812', 'title': 'Restaurants'}
      ],
      'lookups': {
        for (final code in ['5411', '5812']) code: lookup(code, offer)
      },
      'offer_rules': <String, dynamic>{},
    };
Map<String, dynamic> lookup(String code, int offer) => {
      'mcc': {
        'code': code,
        'title': code == '5411' ? 'Groceries' : 'Restaurants'
      },
      'banks': [
        {
          'bank': {'id': 2, 'name': 'Bank'},
          'program': {'name': 'Rewards'},
          'status': 'category',
          'offer_ids': [offer]
        }
      ],
    };
Future<void> seed(MccCacheStore store,
    {int account = 7, String day = '2026-10-14', int offer = 5}) async {
  final key = store.key('https://one.test', account, DateTime.parse(day));
  final base = snapshot(day: day, offer: offer);
  expect(await store.write(key, base), isTrue);
  await store.saveLatest('https://one.test', account, base, snapshotKey: key);
}

MccRepository repository(MccCacheStore cache, MccGet get,
        {void Function()? changed}) =>
    MccRepository(
        cache: cache,
        get: get,
        onChanged: changed ?? () {},
        requestTimeout: const Duration(seconds: 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'cached search returns immediately, deduplicates background refresh, and suppresses loops',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    final network = Completer<http.Response>();
    final updated = Completer<void>();
    var calls = 0;
    final repo = repository(cache, (_, __) {
      calls++;
      return network.future;
    }, changed: () {
      if (!updated.isCompleted) updated.complete();
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    final first = await repo
        .document('lookups', '5411')
        .timeout(const Duration(milliseconds: 100));
    final second = await repo.document('lookups', '5411');
    expect(first!['_cached'], isTrue);
    expect(second!['banks'], first['banks']);
    expect(calls, 1);
    network.complete(http.Response(json.encode(lookup('5411', 9)), 200));
    await updated.future;
    final refreshed = await repo.document('lookups', '5411');
    expect((refreshed!['banks'] as List).single['offer_ids'], [9]);
    expect(calls, 1);
    repo.dispose();
  });

  test(
      'new-day individual success preserves complete older base across restart',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    final updated = Completer<void>();
    final repo = repository(cache, (path, _) async {
      if (path.contains('/5411/')) {
        return http.Response(json.encode(lookup('5411', 9)), 200);
      }
      throw http.ClientException('offline');
    }, changed: () {
      if (!updated.isCompleted) updated.complete();
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 15), 1);
    final previous = await repo.document('lookups', '5411');
    expect((previous!['banks'] as List).single['offer_ids'], isEmpty);
    expect(previous['_offer_links_current'], isFalse);
    await updated.future;
    repo.dispose();
    final restarted = repository(
        cache, (_, __) async => throw http.ClientException('offline'))
      ..activate('https://one.test', 7, DateTime(2026, 10, 15), 2);
    final overlay = await restarted.document('lookups', '5411');
    expect((overlay!['banks'] as List).single['offer_ids'], [9]);
    expect(overlay['_offer_links_current'], isTrue);
    final unseen = await restarted.document('lookups', '5812');
    expect(unseen!['mcc']['title'], 'Restaurants');
    expect((unseen['banks'] as List).single['offer_ids'], isEmpty);
    expect(unseen['_as_of'], '2026-10-14T12:00:00+03:00');
    restarted.dispose();
  });

  test(
      'known negative offer answer survives restart; uncached offline answer throws',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    final repo = repository(cache, (_, __) async => http.Response('{}', 404))
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    expect(await repo.document('offer_rules', '9'), isNull);
    repo.dispose();
    final restarted = repository(
        cache, (_, __) async => throw http.ClientException('offline'))
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 2);
    expect(await restarted.document('offer_rules', '9'), isNull);
    await expectLater(restarted.document('offer_rules', '10'),
        throwsA(isA<http.ClientException>()));
    restarted.dispose();
  });

  test('late same-day lookup cannot overwrite a newer full snapshot', () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    final old = Completer<http.Response>();
    final repo = repository(
        cache,
        (path, _) async => path.startsWith('mcc/offline-snapshot')
            ? http.Response(json.encode(snapshot(offer: 9)), 200,
                headers: {'etag': '"new"'})
            : old.future)
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    final pending = repo.document('lookups', '5411');
    final rejected = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await repo.refreshSnapshot(force: true);
    old.complete(http.Response(json.encode(lookup('5411', 2)), 200));
    await rejected;
    expect(
        ((await repo.document('lookups', '5411'))!['banks'] as List)
            .single['offer_ids'],
        [9]);
    repo.dispose();
  });

  test('late response from previous account cannot change new account cache',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache, account: 8, offer: 8);
    final old = Completer<http.Response>();
    final repo = repository(cache, (_, __) => old.future)
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    final pending = repo.document('lookups', '5411');
    final rejected = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    repo.activate('https://one.test', 8, DateTime(2026, 10, 14), 2);
    await repo.load();
    old.complete(http.Response(json.encode(lookup('5411', 7)), 200));
    await rejected;
    expect(
        ((await repo.document('lookups', '5411'))!['banks'] as List)
            .single['offer_ids'],
        [8]);
    repo.dispose();
  });

  test(
      'a delayed snapshot preserves individual answers accepted after its request started',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    final bulk = Completer<http.Response>();
    final started = Completer<void>();
    final answerAccepted = Completer<void>();
    final repo = repository(cache, (path, _) async {
      if (path.startsWith('mcc/offline-snapshot')) {
        started.complete();
        return bulk.future;
      }
      return http.Response(json.encode(lookup('5411', 9)), 200);
    }, changed: () {
      if (!answerAccepted.isCompleted) answerAccepted.complete();
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    final refreshing = repo.refreshSnapshot(force: true);
    await started.future;
    await repo.document('lookups', '5411');
    await answerAccepted.future;
    bulk.complete(http.Response(json.encode(snapshot(offer: 5)), 200,
        headers: {'etag': '"old-response"'}));
    await refreshing;
    expect(
        ((await repo.document('lookups', '5411'))!['banks'] as List)
            .single['offer_ids'],
        [9]);
    repo.dispose();
  });

  test(
      'invalidation removes ETag and marks bindings stale until full refresh succeeds',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    final network = Completer<http.Response>();
    final started = Completer<void>();
    final ready = Completer<void>();
    var changes = 0;
    final repo = repository(cache, (path, headers) async {
      if (path.startsWith('mcc/offline-snapshot')) {
        expect(headers.containsKey('If-None-Match'), isFalse);
        started.complete();
        return network.future;
      }
      throw http.ClientException('offline');
    }, changed: () {
      if (++changes == 2) ready.complete();
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    await repo.load();
    repo.invalidateBindings();
    await started.future;
    final stale = await repo.document('lookups', '5411');
    expect(stale!['_offer_links_current'], isFalse);
    network.complete(http.Response(json.encode(snapshot()), 200,
        headers: {'etag': '"base"'}));
    await ready.future;
    final current = await repo.document('lookups', '5411');
    expect(current!['_offer_links_current'], isTrue);
    expect((current['banks'] as List).single['offer_ids'], [5]);
    repo.dispose();
  });

  test(
      '304 revalidation retains immutable base and emits no redundant revision',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    var changes = 0;
    final repo = repository(cache, (_, headers) async {
      expect(headers['If-None-Match'], '"base"');
      return http.Response('', 304);
    }, changed: () {
      changes++;
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 1);
    await repo.refreshSnapshot();
    expect(repo.offlineReady, isTrue);
    expect(changes, 0);
    repo.dispose();
  });

  test('restart with persisted dirty bindings does not reuse the base ETag',
      () async {
    final cache = MccCacheStore(storage: MemoryMccStorage());
    await seed(cache);
    final key = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    expect(
        await cache.writeOverlay(key, {
          '_mcc_overlay': 1,
          'lookups': <String, dynamic>{},
          'offer_rules': <String, dynamic>{},
          'bindings_invalidated': true,
          'binding_epoch': 4,
        }),
        isTrue);
    var snapshotRequests = 0;
    final repo = repository(cache, (path, headers) async {
      if (path.startsWith('mcc/offline-snapshot')) {
        snapshotRequests++;
        expect(headers.containsKey('If-None-Match'), isFalse);
        return http.Response(json.encode(snapshot()), 200,
            headers: {'etag': '"base"'});
      }
      throw http.ClientException('offline');
    })
      ..activate('https://one.test', 7, DateTime(2026, 10, 14), 2);
    await repo.load();
    await repo.refreshSnapshot(force: true);
    expect(snapshotRequests, 1);
    final restored = await repo.document('lookups', '5411');
    expect(restored!['_offer_links_current'], isTrue);
    expect((restored['banks'] as List).single['offer_ids'], [5]);
    repo.dispose();
  });
}

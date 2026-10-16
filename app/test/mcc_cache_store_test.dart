import 'dart:convert';
import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _snapshot([String label = 'synthetic']) => {
      'schema_version': 1,
      'catalogue': [],
      'lookups': {},
      'offer_rules': {},
      'label': label,
    };

class _FailingStorage extends MemoryMccStorage {
  bool fail = false;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('Synthetic quota failure');
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('retains three snapshots per scope and isolates account/environment',
      () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage);
    for (var day = 1; day <= 5; day++) {
      final key = cache.key('https://one.test', 7, DateTime(2026, 10, day));
      expect(await cache.write(key, _snapshot()), isTrue);
      await cache.saveLatest('https://one.test', 7, _snapshot(),
          snapshotKey: key);
    }
    expect(
        await cache
            .read(cache.key('https://one.test', 7, DateTime(2026, 10, 2))),
        isNull);
    expect(
        await cache
            .read(cache.key('https://one.test', 7, DateTime(2026, 10, 3))),
        isNotNull);
    expect(await cache.read(cache.latestKey('https://one.test', 7)), isNotNull);
    expect(await cache.read(cache.latestKey('https://two.test', 7)), isNull);
    expect(await cache.read(cache.latestKey('https://one.test', 8)), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('failed replacement leaves all previous snapshots and latest pointer',
      () async {
    final storage = _FailingStorage();
    final cache = MccCacheStore(storage: storage, maxSnapshotsPerScope: 1);
    final old = cache.key('https://one.test', 7, DateTime(2026, 10, 13));
    final next = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    await cache.write(old, _snapshot('old'));
    await cache.saveLatest('https://one.test', 7, _snapshot(),
        snapshotKey: old);
    final before = Map<String, String>.from(storage.values);
    storage.fail = true;
    expect(await cache.write(next, _snapshot('next')), isFalse);
    expect(await cache.write(old, _snapshot('replacement')), isFalse);
    expect(storage.values, before);
    expect((await cache.read(cache.latestKey('https://one.test', 7)))!['label'],
        'old');
  });

  test('global byte limit prunes only after successful commit', () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage, maxBytes: 1200);
    final first = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    final second = cache.key('https://two.test', 8, DateTime(2026, 10, 14));
    final snapshot = {..._snapshot(), 'padding': List.filled(700, 'a').join()};
    expect(await cache.write(first, snapshot), isTrue);
    expect(await cache.write(second, snapshot), isTrue);
    expect(await cache.read(first), isNull);
    expect(await cache.read(second), isNotNull);
    expect(
        await cache.write(
            second, {...snapshot, 'padding': List.filled(1201, 'a').join()}),
        isFalse);
    expect(await cache.read(second), isNotNull);
  });

  test('successful reads update retention order across scopes', () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage, maxBytes: 1200);
    final first = cache.key('https://one.test', 1, DateTime(2026, 10, 14));
    final second = cache.key('https://one.test', 2, DateTime(2026, 10, 14));
    final third = cache.key('https://one.test', 3, DateTime(2026, 10, 14));
    final snapshot = {..._snapshot(), 'padding': List.filled(400, 'a').join()};
    await cache.write(first, snapshot);
    await cache.write(second, snapshot);
    expect(await cache.read(first), isNotNull);
    await cache.write(third, snapshot);
    expect(await cache.read(first), isNotNull);
    expect(await cache.read(second), isNull);
    expect(await cache.read(third), isNotNull);
  });

  test('legacy preferences migrate only after successful dedicated write',
      () async {
    final storage = _FailingStorage()..fail = true;
    final cache = MccCacheStore(storage: storage);
    final key = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    final pointer = cache.latestKey('https://one.test', 7);
    SharedPreferences.setMockInitialValues({
      key: jsonEncode(_snapshot()),
      pointer: jsonEncode({'snapshot_key': key})
    });
    expect(await cache.read(pointer), isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isTrue);
    expect(storage.values, isEmpty);
    storage.fail = false;
    expect(await cache.read(pointer), isNotNull);
    expect(storage.values.containsKey(key), isTrue);
    expect(storage.values.containsKey(pointer), isTrue);
    expect(prefs.containsKey(key), isFalse);
    expect(prefs.containsKey(pointer), isFalse);
    expect(await MccCacheStore(storage: storage).read(pointer), isNotNull);
  });

  test('dated overlay never replaces complete base or crosses day/account',
      () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage);
    final base = cache.key('https://one.test', 7, DateTime(2026, 10, 13));
    final today = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    await cache.write(base, _snapshot('complete previous day'));
    final overlay = {
      '_mcc_overlay': 1,
      'lookups': {
        '5814': {
          'status': 200,
          'document': {
            'mcc': {'code': '5814'}
          }
        }
      },
      'offer_rules': {}
    };
    expect(await cache.writeOverlay(today, overlay), isTrue);
    expect((await cache.read(base))!['label'], 'complete previous day');
    expect(await cache.readOverlay(today), overlay);
    expect(await cache.read(today), isNull);
    expect(await cache.readOverlay(base), isNull);
    expect(
        await cache.readOverlay(
            cache.key('https://one.test', 8, DateTime(2026, 10, 14))),
        isNull);
  });

  test('malformed cache and cross-scope pointers are rejected', () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage);
    final key = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    await storage.write(
        key, '{"schema_version":1,"catalogue":[{"code":1234}]}');
    expect(await cache.read(key), isNull);
    await storage.write(
        '$key:overlay',
        jsonEncode({
          '_mcc_overlay': 1,
          'lookups': {
            '5814': {'status': 200, 'document': 'broken'}
          },
          'offer_rules': {},
        }));
    expect(await cache.readOverlay(key), isNull);
    expect(await cache.write(key, {'schema_version': 9}), isFalse);
    await storage.write(cache.latestKey('https://two.test', 8),
        jsonEncode({'snapshot_key': key}));
    expect(await cache.read(cache.latestKey('https://two.test', 8)), isNull);
    await expectLater(
        cache.saveLatest('https://two.test', 8, _snapshot(), snapshotKey: key),
        throwsArgumentError);
  });

  test('small budget cannot evict full previous-day base for a partial overlay',
      () async {
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage, maxBytes: 500);
    final previous = cache.key('https://one.test', 7, DateTime(2026, 10, 13));
    final today = cache.key('https://one.test', 7, DateTime(2026, 10, 14));
    final snapshot = {..._snapshot(), 'padding': List.filled(180, 'x').join()};
    expect(await cache.write(previous, snapshot), isTrue);
    await cache.saveLatest('https://one.test', 7, snapshot,
        snapshotKey: previous);
    final overlay = {
      '_mcc_overlay': 1,
      'lookups': <String, dynamic>{},
      'offer_rules': <String, dynamic>{},
      'padding': List.filled(250, 'y').join()
    };
    expect(await cache.writeOverlay(today, overlay), isFalse);
    expect(await cache.read(previous), snapshot);
    expect(await cache.read(cache.latestKey('https://one.test', 7)), snapshot);
    expect(await cache.readOverlay(today), isNull);
  });
}

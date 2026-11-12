import 'dart:async';
import 'dart:convert';

import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:cashflow/services/partner_offer_cache_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'data:v1:https%3A%2F%2Fcashflow.test:7:partnerOffers';

class _FailingStorage extends MemoryMccStorage {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('disk full');
}

class _RecordingStorage extends MemoryMccStorage {
  int reads = 0;
  @override
  Future<String?> read(String key) {
    reads++;
    return super.read(key);
  }
}

String _offers(String title) => json.encode([
      {
        'id': 1,
        'bank_id': 2,
        'card_user_id': 3,
        'preference': 'undecided',
        'first_seen_at': '2026-10-01T00:00:00Z',
        'last_seen_at': '2026-10-01T00:00:00Z',
        'snapshot': {'title': title, 'collected_at': '2026-10-01T00:00:00Z'},
      }
    ]);

void main() {
  test('moves the preference copy once and then deletes it', () async {
    SharedPreferences.setMockInitialValues({_key: '[1]', 'other': 'kept'});
    final storage = MemoryMccStorage();
    final store = PartnerOfferCacheStore(storage: storage);

    expect(await store.read(_key), '[1]');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(_key), isFalse);
    expect(prefs.getString('other'), 'kept');
    expect(storage.values[_key], '[1]');
    expect(await store.read(_key), '[1]');
  });

  test('keeps the preference copy when the dedicated write fails', () async {
    SharedPreferences.setMockInitialValues({_key: '[1]'});
    final store = PartnerOfferCacheStore(storage: _FailingStorage());

    expect(await store.read(_key), '[1]');
    expect((await SharedPreferences.getInstance()).getString(_key), '[1]');
  });

  test('a newer save supersedes an unread preference copy', () async {
    SharedPreferences.setMockInitialValues({_key: '[1]'});
    final storage = MemoryMccStorage();
    await PartnerOfferCacheStore(storage: storage).write(_key, '[2]');

    expect(storage.values[_key], '[2]');
    expect((await SharedPreferences.getInstance()).containsKey(_key), isFalse);
  });

  test('a failed save never writes the catalogue to preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await PartnerOfferCacheStore(storage: _FailingStorage()).write(_key, '[2]');

    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('startup reads cached offers only after the first frame', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'synthetic-token',
      'cashflowAuthIdentity':
          json.encode({'id': 7, 'username': 'reader', 'role': 'viewer'}),
    });
    SharedPreferences.setMockInitialValues({});
    final storage = _RecordingStorage()..values[_key] = _offers('Cached shop');
    final firstFrame = Completer<void>();
    // A slow network: the background refresh is still running when the
    // first frame is drawn, and must not keep the cache from showing.
    final network = Completer<http.Response>();
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
      partnerOfferCache: PartnerOfferCacheStore(storage: storage),
      httpClient: MockClient((_) => network.future),
      afterFirstFrame: () => firstFrame.future,
    );
    try {
      await provider.initialize();
      expect(provider.authReady, isTrue);
      await pumpEventQueue();
      expect(storage.reads, 0);
      expect(provider.partnerOffers, isEmpty);

      firstFrame.complete();
      await pumpEventQueue();
      expect(storage.reads, greaterThan(0));
      expect(provider.partnerOffers.single.name, 'Cached shop');
    } finally {
      network.complete(http.Response('Unavailable', 503));
      await pumpEventQueue();
      provider.dispose();
    }
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/partner_offer_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/api_client.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cashback default day follows Moscow near UTC midnight', () {
    final provider = DataProvider(
        mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
        businessClock:
            BusinessClock(now: () => DateTime.utc(2026, 10, 14, 22)));
    expect(provider.cashbackEffectiveDate, DateTime(2026, 10, 15));
    provider.dispose();
  });

  test('late response from old token is rejected before domain mutation',
      () async {
    var token = 'old';
    final completed = Completer<http.Response>();
    final started = Completer<void>();
    final client = AuthenticatedApiClient(MockClient((_) {
      started.complete();
      return completed.future;
    }), () => token, (_) async {}, (_, __) async {});
    final response = client.get(Uri.parse('https://cashflow.test/api/cards'));
    final rejected = expectLater(response, throwsStateError);
    await started.future;
    token = 'new';
    completed.complete(http.Response('[{"id":1}]', 200));
    await rejected;
    client.close();
  });
  test('restart offline can search a never requested MCC and category rules',
      () async {
    SharedPreferences.setMockInitialValues({});
    final cache = MccCacheStore(storage: MemoryMccStorage());
    final day = DateTime(2026, 10, 14);
    final snapshot = {
      'schema_version': 1,
      'as_of': '2026-10-14T12:00:00+03:00',
      'generated_at': '2026-10-14T09:30:00Z',
      'catalogue': [
        {'code': '5411', 'title': 'Supermarkets'}
      ],
      'lookups': {
        '5411': {
          'mcc': {'code': '5411', 'title': 'Supermarkets'},
          'banks': [
            {
              'bank': {'id': 2, 'name': 'Bank'},
              'program': {'name': 'Rewards'},
              'status': 'category_only',
              'categories': [
                {'name': 'Groceries', 'kind': 'mcc'}
              ],
              'offer_ids': [5]
            }
          ]
        }
      },
      'offer_rules': {
        '5': {
          'program': {'name': 'Program'},
          'category': {
            'name': 'Groceries',
            'included': [
              {'code': '5411'}
            ]
          },
          'valid_from': '2026-10-01T00:00:00Z',
          'exclusions': [],
        }
      },
    };
    final online = DataProvider(
        apiBaseUrl: 'https://one.test',
        mccCacheStore: cache,
        httpClient: MockClient((request) async =>
            request.url.path.endsWith('offline-snapshot')
                ? http.Response(json.encode(snapshot), 200)
                : http.Response('{}', 503)))
      ..currentAuthUser =
          const AuthIdentity(id: 7, username: 'a', role: 'editor');
    await online.setCashbackEffectiveDate(day);
    await online.refreshMccSnapshot();
    online.dispose();
    DataProvider offline(String url, int account) => DataProvider(
        apiBaseUrl: url,
        mccCacheStore: cache,
        httpClient:
            MockClient((_) async => throw http.ClientException('offline')))
      ..currentAuthUser =
          AuthIdentity(id: account, username: 'a', role: 'editor');
    final restarted = offline('https://one.test', 7);
    await restarted.loadLocalData();
    expect((await restarted.fetchMccCatalog()).single.title, 'Supermarkets');
    final result = await restarted.lookupMcc('5411');
    expect(result.isFromCache, isTrue);
    expect(result.banks.single.status, 'category_only');
    expect(result.banks.single.categories.single.name, 'Groceries');
    expect(result.banks.single.offerIds, [5]);
    expect(result.snapshotUpdatedAt, DateTime.utc(2026, 10, 14, 9, 30));
    expect(
        (await restarted.fetchOfferMccRules(5))!.included.single.code, '5411');
    final otherEnvironment = offline('https://two.test', 7);
    await otherEnvironment.loadLocalData();
    expect(await otherEnvironment.fetchMccCatalog(), isEmpty);
    await expectLater(otherEnvironment.lookupMcc('5411'), throwsException);
    final otherAccount = offline('https://one.test', 8);
    await otherAccount.loadLocalData();
    await expectLater(otherAccount.lookupMcc('5411'), throwsException);
    await restarted.setCashbackEffectiveDate(DateTime(2026, 10, 15));
    final nextDay = await restarted.lookupMcc('5411');
    expect(nextDay.isFromCache, isTrue);
    expect(nextDay.banks.single.offerIds, isEmpty);
    expect(nextDay.snapshotAsOf, DateTime.parse('2026-10-14T12:00:00+03:00'));
    restarted.dispose();
    otherEnvironment.dispose();
    otherAccount.dispose();
  });

  test('card update preserves server fields and delete persists across restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final card = {
      'id': 1,
      'bank_id': 2,
      'user_id': 3,
      'payment_system': 'Mir',
      'card_type': 'Debit',
      'last_four_digits': '1234',
      'max_cashback_categories': 7,
      'is_active': false
    };
    final provider = DataProvider(
        mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
        httpClient: MockClient((request) async => request.method == 'DELETE'
            ? http.Response('', 204)
            : http.Response(json.encode(card), 200)))
      ..cards = [CardModel.fromJson(card)];
    await provider.updateCard(1, 'Mir', 'Debit', '1234', 2, 3);
    expect(provider.cards.single.maxCashbackCategories, 7);
    expect(provider.cards.single.isActive, isFalse);
    final restart =
        DataProvider(mccCacheStore: MccCacheStore(storage: MemoryMccStorage()));
    await restart.loadLocalData();
    expect(restart.cards.single.maxCashbackCategories, 7);
    await provider.deleteCard(1);
    await restart.loadLocalData();
    expect(restart.cards, isEmpty);
    provider.dispose();
    restart.dispose();
  });

  test(
      'compact nested snapshot survives restart without inflating stored rules',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = MemoryMccStorage();
    final cache = MccCacheStore(storage: storage);
    final snapshot = {
      'schema_version': 2,
      'as_of': '2026-10-14T12:00:00+03:00',
      'generated_at': '2026-10-14T09:30:00Z',
      'catalogue': [
        {'code': '5411', 'title': 'Groceries'}
      ],
      'mcc_details': {
        '5411': {'code': '5411', 'title': 'Groceries'}
      },
      'canonical': {},
      'shared_payloads': {
        'bank': {'id': 2, 'name': 'Bank'},
        'program': {'name': 'Rewards'},
        'codes': [
          {'code': '5411', 'title': 'Groceries'}
        ],
      },
      'lookup_refs': {
        '5411': ['1']
      },
      'lookup_payloads': {
        '1': {
          'bank': {r'$ref': 'bank'},
          'program': {r'$ref': 'program'},
          'status': 'category',
          'offer_ids': [5],
        }
      },
      'offer_rule_refs': {'5': '1', '6': '1'},
      'offer_rule_payloads': {
        '1': {
          'program': {r'$ref': 'program'},
          'category': {
            'name': 'Groceries',
            'included': {r'$ref': 'codes'}
          },
          'exclusions': [],
          'valid_from': '2026-10-01T00:00:00Z',
        }
      },
    };
    final online = DataProvider(
        apiBaseUrl: 'https://compact.test',
        mccCacheStore: cache,
        httpClient:
            MockClient((_) async => http.Response(json.encode(snapshot), 200)))
      ..currentAuthUser =
          const AuthIdentity(id: 7, username: 'a', role: 'editor');
    await online.setCashbackEffectiveDate(DateTime(2026, 10, 14));
    await online.refreshMccSnapshot();
    online.dispose();
    final offline = DataProvider(
        apiBaseUrl: 'https://compact.test',
        mccCacheStore: cache,
        httpClient:
            MockClient((_) async => throw http.ClientException('offline')))
      ..currentAuthUser =
          const AuthIdentity(id: 7, username: 'a', role: 'editor');
    await offline.loadLocalData();
    final lookup = await offline.lookupMcc('5411');
    expect(lookup.banks.single.bankName, 'Bank');
    expect(lookup.banks.single.offerIds, [5]);
    expect(lookup.isFromCache, isTrue);
    expect((await offline.fetchOfferMccRules(6))!.included.single.title,
        'Groceries');
    final datedKey =
        storage.values.keys.singleWhere((key) => key.endsWith(':2026-10-14'));
    final stored =
        json.decode(storage.values[datedKey]!) as Map<String, dynamic>;
    expect(stored.containsKey('lookups'), isFalse);
    expect(stored['offer_rule_payloads'], hasLength(1));
    offline.dispose();
  });

  test('old preference failure cannot roll back newer preference', () async {
    SharedPreferences.setMockInitialValues({});
    final first = Completer<http.Response>();
    var requestCount = 0;
    final provider = DataProvider(
        mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
        httpClient: MockClient((_) async =>
            ++requestCount == 1 ? first.future : http.Response('{}', 200)))
      ..partnerOffers = [
        PartnerOffer.fromJson({
          'id': 1,
          'bank_id': 2,
          'card_user_id': 3,
          'preference': 'undecided',
          'first_seen_at': '2026-10-01T00:00:00Z',
          'last_seen_at': '2026-10-01T00:00:00Z',
          'snapshot': {'title': 'Shop', 'collected_at': '2026-10-01T00:00:00Z'},
        })
      ];
    final old = provider.updatePartnerOfferPreference(1, 'interesting');
    final oldFailure = expectLater(old, throwsException);
    await provider.updatePartnerOfferPreference(1, 'hidden');
    first.complete(http.Response('{}', 500));
    await oldFailure;
    expect(provider.partnerOffers.single.preference, 'hidden');
    provider.dispose();
  });

  test('main refresh completes while the independent MCC download is pending',
      () async {
    SharedPreferences.setMockInitialValues({});
    final snapshot = Completer<http.Response>();
    final snapshotStarted = Completer<void>();
    final provider = DataProvider(
      mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/mcc/offline-snapshot')) {
          snapshotStarted.complete();
          return snapshot.future;
        }
        if (request.url.path.endsWith('/partner-offers')) {
          return http.Response('{"items":[],"total":0}', 200);
        }
        return http.Response('[]', 200);
      }),
    );
    expect(await provider.fetchAllData().timeout(const Duration(seconds: 1)),
        isTrue);
    await snapshotStarted.future;
    expect(provider.primaryDataPhase, PrimaryDataPhase.ready);
    snapshot.complete(http.Response('{}', 503));
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
  });
}

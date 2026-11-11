import 'dart:convert';

import 'package:cashflow/models/card_balance_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/screens/settings/card_balances_settings_screen.dart';
import 'package:cashflow/screens/widgets/benefit_states_view.dart';
import 'package:cashflow/screens/widgets/card_balance_label.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/utils/cashflow_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

const _cacheKey = 'data:v1:https%3A%2F%2Fcashflow.test:7:cardBalances';

Map<String, dynamic> _payload({
  String status = 'ok',
  String fetchedAt = '2026-11-11T09:00:00+00:00',
}) =>
    {
      'integration': {
        'status': status,
        'configured': status != 'not_configured',
        'last_success_at': fetchedAt,
        'last_attempt_at': fetchedAt,
        'last_error': null,
        'refreshing': false,
        'refresh_outcome': 'not_due',
      },
      'balances': status == 'not_configured' || status == 'no_token'
          ? []
          : [
              {
                'card_id': 1,
                'account_id': 'acc-1',
                'account_title': 'Tinkoff Black',
                'account_type': 'ccard',
                'balance': '15234.50',
                'credit_limit': '0.00',
                'available': '15234.50',
                'currency': 'RUB',
                'fetched_at': fetchedAt,
                'link_source': 'auto',
              },
              {
                'card_id': 2,
                'account_id': 'acc-2',
                'account_title': 'Platinum',
                'account_type': 'ccard',
                'balance': '-20000.00',
                'credit_limit': '100000.00',
                'available': '80000.00',
                'currency': 'RUB',
                'fetched_at': fetchedAt,
                'link_source': 'manual',
              },
            ],
    };

http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(json.encode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

DataProvider _provider(
  Future<http.Response> Function(http.Request request) handler, {
  String role = 'viewer',
}) =>
    DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      reminderNotificationService: FakeReminders(),
      businessClock: BusinessClock(now: () => DateTime.utc(2026, 11, 11, 9)),
      httpClient: MockClient(handler),
    )..currentAuthUser = AuthIdentity(id: 7, username: 'tester', role: role);

CardBalanceView _view({
  required Duration age,
  bool credit = false,
  bool offline = false,
  bool notUpdating = false,
}) =>
    CardBalanceView(
      balance: CardBalance(
        cardId: 1,
        accountId: 'acc-1',
        accountType: 'ccard',
        balance: credit ? -20000 : 15234.5,
        creditLimit: credit ? 100000 : 0,
        available: credit ? 80000 : 15234.5,
        currency: 'RUB',
        fetchedAt: DateTime.now().subtract(age),
      ),
      offline: offline,
      notUpdating: notUpdating,
    );

BenefitItemData _item({CardBalanceView? balance}) => BenefitItemData(
      category: CashbackCategoryModel(
        id: 1,
        name: 'Аптеки',
        startDate: DateTime(2026, 11),
        endDate: DateTime(2026, 12),
        isSelected: true,
        isBankConfirmed: true,
        cashbackPercent: 5,
        cardId: 1,
      ),
      cardLabel: 'Т-Банк •1111',
      bankName: 'Т-Банк',
      lastFourDigits: '1111',
      balance: balance,
    );

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(body: child),
    );

Widget _benefit({
  List<BenefitItemData> items = const [],
  List<BenefitMerchantSearchResult> merchants = const [],
}) =>
    _app(BenefitStatesView(
      phase: PrimaryDataPhase.ready,
      hasUsableSnapshot: true,
      items: items,
      merchantResults: merchants,
      onRefresh: () async {},
    ));

DateTime _yesterdayNoon() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 1, 12);
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('formatting', () {
    final now = DateTime(2026, 11, 11, 15, 30);

    test('freshness is relative and names yesterday', () {
      expect(freshnessLabel(now.subtract(const Duration(seconds: 20)), now),
          'обновлено только что');
      expect(freshnessLabel(now.subtract(const Duration(minutes: 12)), now),
          'обновлено 12 мин назад');
      expect(freshnessLabel(DateTime(2026, 11, 11, 9, 5), now),
          'обновлено сегодня в 09:05');
      expect(freshnessLabel(DateTime(2026, 11, 10, 18, 40), now),
          'обновлено вчера в 18:40');
      expect(freshnessLabel(DateTime(2026, 11, 2, 8, 0), now),
          'обновлено 02.11 в 08:00');
      expect(freshnessLabel(DateTime(2025, 12, 31, 8, 0), now),
          'обновлено 31.12.2025 в 08:00');
    });

    test('money groups thousands and keeps kopecks only when present', () {
      expect(moneyLabel(15234.5, 'RUB'), '15 234,50 ₽');
      expect(moneyLabel(80000, 'RUB'), '80 000 ₽');
      expect(moneyLabel(-20000, null), '−20 000 ₽');
      expect(moneyLabel(12.3, 'USD'), '12,30 \$');
    });

    test('a view is stale after six hours, offline, or when not updating', () {
      final now = DateTime.now();
      expect(_view(age: const Duration(hours: 5)).isStale(now), isFalse);
      expect(_view(age: const Duration(hours: 7)).isStale(now), isTrue);
      expect(
        _view(age: const Duration(minutes: 1), offline: true).isStale(now),
        isTrue,
      );
      expect(
        _view(age: const Duration(minutes: 1), notUpdating: true).isStale(now),
        isTrue,
      );
    });
  });

  group('model and cache', () {
    test('snapshot keeps fetched_at through a JSON round trip', () {
      final snapshot = CardBalancesSnapshot.fromJson(_payload());
      final restored = CardBalancesSnapshot.fromJson(
          json.decode(json.encode(snapshot.toJson())) as Map<String, dynamic>);
      final credit = restored.forCard(2)!;
      expect(credit.fetchedAt, DateTime.utc(2026, 11, 11, 9));
      expect(credit.isCredit, isTrue);
      expect(credit.available, 80000);
      expect(restored.forCard(1)!.balance, 15234.5);
      expect(restored.forCard(3), isNull);
      expect(restored.status, CardBalanceStatus.ok);
    });

    test('balances without a timestamp are dropped', () {
      final payload = _payload();
      (payload['balances'] as List).add({
        'card_id': 3,
        'account_id': 'acc-3',
        'balance': '1.00',
      });
      expect(CardBalancesSnapshot.fromJson(payload).forCard(3), isNull);
    });

    test('provider caches balances per account and marks a cached copy',
        () async {
      final provider = _provider((request) async {
        expect(request.url.path, '/api/card-balances');
        return _json(_payload(), 200);
      });
      expect(await provider.fetchCardBalances(), isTrue);
      final view = provider.cardBalanceView(1)!;
      expect(view.offline, isFalse);
      expect(view.balance.fetchedAt, DateTime.utc(2026, 11, 11, 9));
      final cached =
          (await SharedPreferences.getInstance()).getString(_cacheKey);
      expect(cached, contains('2026-11-11T09:00:00.000Z'));

      final offline = _provider((request) async => throw http.ClientException(
            'offline',
          ));
      await offline.loadCardBalancesCache();
      expect(offline.cardBalanceView(1)!.offline, isTrue);
      expect(await offline.fetchCardBalances(), isFalse);
      final kept = offline.cardBalanceView(1)!;
      expect(kept.offline, isTrue);
      expect(kept.balance.balance, 15234.5);
      expect(kept.balance.fetchedAt, DateTime.utc(2026, 11, 11, 9));
    });

    test('editors force the server refresh, viewers read', () async {
      final paths = <String>[];
      Future<http.Response> handler(http.Request request) async {
        paths.add('${request.method} ${request.url.path}');
        return _json(_payload(), 200);
      }

      await _provider(handler).fetchCardBalances(force: true);
      await _provider(handler, role: 'editor').fetchCardBalances(force: true);
      expect(paths, [
        'GET /api/card-balances',
        'POST /api/card-balances/refresh',
      ]);
    });

    test('no integration or an unmapped card shows nothing', () async {
      final provider = _provider(
          (request) async => _json(_payload(status: 'no_token'), 200));
      await provider.fetchCardBalances();
      expect(provider.cardBalanceView(1), isNull);

      final old = _provider((request) async => _json({'error': 'nope'}, 404));
      expect(await old.fetchCardBalances(), isFalse);
      expect(old.cardBalanceView(1), isNull);

      final mapped = _provider((request) async => _json(_payload(), 200));
      await mapped.fetchCardBalances();
      expect(mapped.cardBalanceView(99), isNull);
    });

    test('a server that cannot refresh marks balances as not updating',
        () async {
      final provider =
          _provider((request) async => _json(_payload(status: 'error'), 200));
      await provider.fetchCardBalances();
      expect(provider.cardBalanceView(1)!.notUpdating, isTrue);
    });
  });

  group('widgets', () {
    testWidgets('label shows amount and freshness together', (tester) async {
      await tester.pumpWidget(_app(CardBalanceLabel(
        view: _view(age: const Duration(minutes: 12)),
      )));
      expect(
        find.text('на карте 15 234,50 ₽ · обновлено 12 мин назад',
            findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('card-balance-stale-1')), findsNothing);
    });

    testWidgets('credit card shows what is available with the limit',
        (tester) async {
      await tester.pumpWidget(_app(CardBalanceLabel(
        view: _view(age: const Duration(minutes: 3), credit: true),
      )));
      expect(
        find.textContaining('доступно 80 000 ₽ с кредитным лимитом',
            findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('old or cached balances are muted with a history icon',
        (tester) async {
      await tester.pumpWidget(_app(Column(children: [
        CardBalanceLabel(view: _view(age: const Duration(hours: 8))),
      ])));
      expect(
          find.byKey(const ValueKey('card-balance-stale-1')), findsOneWidget);
      final icon = tester
          .widget<Icon>(find.byKey(const ValueKey('card-balance-stale-1')));
      expect(icon.icon, Icons.history);

      await tester.pumpWidget(_app(CardBalanceLabel(
        view: _view(age: const Duration(minutes: 2), offline: true),
      )));
      expect(
          find.byKey(const ValueKey('card-balance-stale-1')), findsOneWidget);
      expect(find.textContaining('сохранённая копия', findRichText: true),
          findsOneWidget);
    });

    testWidgets('search results show the balance under the card',
        (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_benefit(
        items: [_item(balance: _view(age: const Duration(minutes: 12)))],
      ));
      await tester.enterText(find.byKey(const Key('benefit-search')), 'апт');
      await tester.pump();
      expect(find.byKey(const ValueKey('card-balance-1')), findsOneWidget);
      expect(find.textContaining('обновлено 12 мин назад', findRichText: true),
          findsOneWidget);

      await tester.tap(find.text('5%'));
      await tester.pump();
      expect(find.byKey(const Key('benefit-compact-detail')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-balance-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unmapped card shows no balance at all', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_benefit(items: [_item()]));
      await tester.enterText(find.byKey(const Key('benefit-search')), 'апт');
      await tester.pump();
      expect(find.byKey(const ValueKey('card-balance-1')), findsNothing);
      expect(
          find.textContaining('обновлено', findRichText: true), findsNothing);
    });

    testWidgets('best card and alternatives show balances, stale muted',
        (tester) async {
      await _phone(tester);
      final merchant = BenefitMerchantSearchResult(
        name: 'Аптека у дома',
        description: '3 операции',
        initials: 'АД',
        purchaseResult: BenefitPurchaseResult(
          title: 'Покупка в аптеке',
          merchantName: 'Аптека у дома',
          subtitle: 'MCC 5912',
          evidence: const [],
          best: BenefitPurchaseOption(
            bankMark: 'Т',
            cardLabel: 'Т-Банк • 1111',
            cardSubtitle: 'Общая карта',
            rate: '5%',
            categoryName: 'Аптеки',
            categorySubtitle: 'Выбрано',
            balance: _view(age: const Duration(minutes: 12)),
          ),
          alternatives: [
            BenefitPurchaseOption(
              bankMark: 'A',
              cardLabel: 'Альфа • 2222',
              cardSubtitle: 'Карта Анны',
              rate: '3%',
              categoryName: 'Все покупки',
              categorySubtitle: 'Выбрано',
              balance: CardBalanceView(
                balance: CardBalance(
                  cardId: 2,
                  accountId: 'acc-2',
                  balance: 500,
                  currency: 'RUB',
                  fetchedAt: _yesterdayNoon(),
                ),
              ),
            ),
            const BenefitPurchaseOption(
              bankMark: 'В',
              cardLabel: 'ВТБ • 3333',
              cardSubtitle: 'Без счёта',
              rate: '1%',
              categoryName: 'Все покупки',
              categorySubtitle: 'Выбрано',
            ),
          ],
          risk: 'Точный MCC заранее неизвестен.',
        ),
      );
      await tester
          .pumpWidget(_benefit(items: [_item()], merchants: [merchant]));
      await tester.tap(find.text('Аптека у дома'));
      await tester.pump();

      expect(find.byKey(const Key('benefit-compact-purchase-result')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('card-balance-1')), findsOneWidget);
      expect(
        find.textContaining('15 234,50 ₽ · обновлено 12 мин назад',
            findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('card-balance-stale-1')), findsNothing);
      expect(find.byKey(const ValueKey('card-balance-2')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('card-balance-stale-2')), findsOneWidget);
      expect(find.textContaining('обновлено вчера в', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('card-balance-3')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('mapping screen lists suggestions and the admin token action',
      (tester) async {
    await _phone(tester);
    final requests = <String>[];
    final provider = _provider((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/api/admin/zenmoney') {
        return _json({
          'status': 'token_invalid',
          'configured': true,
          'token_set': true,
          'last_error': {'kind': 'token_invalid', 'message': 'HTTP 401'},
        }, 200);
      }
      return _json({
        'integration': {
          'status': 'token_invalid',
          'last_success_at': '2026-11-10T15:40:00+00:00',
        },
        'accounts': [
          {
            'id': 'acc-a',
            'title': 'Карта A',
            'type': 'ccard',
            'company_title': 'Альфа-Банк',
            'currency': 'RUB',
            'sync_ids': ['4444'],
            'balance': '1.00',
            'credit_limit': '0.00',
            'available': '1.00',
            'archived': false,
            'missing': false,
            'fetched_at': '2026-11-10T15:40:00+00:00',
          },
        ],
        'cards': [
          {
            'card_id': 4,
            'link': null,
            'suggestions': [
              {'account_id': 'acc-a', 'bank_match': null},
              {'account_id': 'acc-b', 'bank_match': null},
            ],
            'ambiguous': true,
          },
        ],
      }, 200);
    }, role: 'admin');
    provider.cards = [
      CardModel(
        id: 4,
        paymentSystem: 'Мир',
        cardType: 'virtual',
        lastFourDigits: '4444',
      ),
    ];
    await tester.pumpWidget(ChangeNotifierProvider<DataProvider>.value(
      value: provider,
      child: const MaterialApp(home: CardBalancesSettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(requests, contains('GET /api/card-balances/mapping'));
    expect(requests, contains('GET /api/admin/zenmoney'));
    expect(find.textContaining('ZenMoney не принимает токен'), findsOneWidget);
    expect(find.text('Заменить токен'), findsOneWidget);
    expect(find.text('Подходит несколько счетов — выберите'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

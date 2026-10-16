import 'dart:convert';

import 'package:cashflow/models/partner_offer_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/partner_offers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'support/mcc_test_cache.dart';

void main() {
  testWidgets('hides expired cached offers and labels unknown deadlines',
      (tester) async {
    final expired = _offerJson(name: 'Просроченное');
    (expired['snapshot'] as Map<String, dynamic>)['ends_at'] =
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final unknown = _offerJson(id: 2, name: 'Без срока');
    (unknown['snapshot'] as Map<String, dynamic>)['ends_at'] = null;
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    )..partnerOffers = [
        PartnerOffer.fromJson(expired),
        PartnerOffer.fromJson(unknown),
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: PartnerOffersScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Просроченное'), findsNothing);
    expect(find.text('Без срока'), findsWidgets);
    expect(find.text('Срок неизвестен'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('upcoming filter shows future cached offers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final upcoming = _offerJson(id: 2, name: 'Будущее предложение');
    (upcoming['snapshot'] as Map<String, dynamic>)['starts_at'] =
        DateTime.now().add(const Duration(days: 2)).toIso8601String();
    final provider = DataProvider(
        mccCacheStore: isolatedMccCache(),
        apiBaseUrl: 'https://cashflow.test',
        httpClient: MockClient((_) async => http.Response('{}', 404)))
      ..partnerOffers = [
        PartnerOffer.fromJson(_offerJson()),
        PartnerOffer.fromJson(upcoming)
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: PartnerOffersScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Будущее предложение'), findsNothing);
    await tester.tap(find.byTooltip('Фильтр по сроку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скоро начнутся').last);
    await tester.pumpAndSettle();
    expect(find.text('Будущее предложение'), findsWidgets);
    expect(find.text('Магазин А'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('groups offers by bank category and filters from the breakdown',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic> grouped(int id, String name, List<String> groups,
        [String rate = 'до 10%']) {
      final json = _offerJson(id: id, name: name);
      (json['snapshot'] as Map<String, dynamic>)
        ..['groups'] = groups
        ..['rate_label'] = rate;
      return json;
    }

    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    )..partnerOffers = [
        PartnerOffer.fromJson(grouped(1, 'Пиццерия', ['Еда'], 'до 7%')),
        PartnerOffer.fromJson(grouped(2, 'Кеды', ['Одежда'], 'до 25%')),
        PartnerOffer.fromJson(grouped(3, 'Суши', ['Еда'], 'до 12%')),
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: PartnerOffersScreen())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('offer-grouped-view')));
    await tester.pumpAndSettle();
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('2 · до 12%'), findsOneWidget);
    expect(find.text('Одежда'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('offer-groups-filter')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('offer-groups-search')), 'оде');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Еда'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Одежда'));
    await tester.tap(find.text('Показать'));
    await tester.pumpAndSettle();
    expect(find.text('Кеды'), findsOneWidget);
    expect(find.text('Пиццерия'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  test('parses the normalized API representation without changing units', () {
    final offer = PartnerOffer.fromJson(
      _offerJson(endsAt: '2026-09-30T00:00:00+03:00'),
    );

    expect(offer.name, 'Магазин А');
    expect(offer.rateLabel, 'до 10%');
    expect(offer.limits.single.unit, 'bonus');
    expect(offer.limits.single.scope, 'month');
    expect(offer.endsAt, DateTime.parse('2026-09-30T00:00:00+03:00'));
  });

  testWidgets('shows compact offers, filters banks, and opens full conditions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var requestedDetails = false;
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/partner-offers/1') {
          requestedDetails = true;
          return http.Response(
            json.encode(_offerJson(details: true)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 404);
      }),
    )..partnerOffers = [
        PartnerOffer.fromJson(_offerJson()),
        PartnerOffer.fromJson(_offerJson(
          id: 2,
          bankId: 2,
          bankName: 'Сбер',
          name: 'Магазин Б',
        )),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: PartnerOffersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Магазин А'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Магазин Б'), findsOneWidget);
    expect(find.text('до 10%'), findsNWidgets(2));
    expect(find.textContaining('1200 бонусов'), findsNWidgets(2));
    expect(find.textContaining('Осталось'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'Магазин Б');
    await tester.pumpAndSettle();
    expect(find.text('Магазин А'), findsNothing);
    expect(find.widgetWithText(Card, 'Магазин Б'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Сбер'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Сбер'));
    await tester.pumpAndSettle();
    expect(find.text('Магазин А'), findsNothing);
    expect(find.text('Магазин Б'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Все (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Все (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Действия с предложением').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подробнее').last);
    await tester.pumpAndSettle();
    expect(requestedDetails, isTrue);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('подарочные сертификаты'),
    );
  });

  testWidgets('uses persistent master-detail layout on expanded width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((request) async => http.Response(
            json.encode(_offerJson(details: true)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    )..partnerOffers = [PartnerOffer.fromJson(_offerJson())];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: PartnerOffersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Открыто'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps compact layout usable with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((request) async => http.Response('{}', 404)),
    )..partnerOffers = [PartnerOffer.fromJson(_offerJson())];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 812),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(body: PartnerOffersScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Магазин А'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _offerJson({
  int id = 1,
  int bankId = 1,
  String bankName = 'Альфа-Банк',
  String name = 'Магазин А',
  bool details = false,
  String? endsAt,
}) =>
    {
      'id': id,
      'bank_id': bankId,
      'bank_name': bankName,
      'card_user_id': 7,
      'preference': 'undecided',
      'is_available': true,
      'first_seen_at': '2026-09-16T08:00:00Z',
      'last_seen_at': '2026-09-16T08:00:00Z',
      'snapshot': {
        'id': id,
        'title': name,
        'description': 'Покупки онлайн',
        'rate_label': 'до 10%',
        'collected_at': '2026-09-16T08:00:00Z',
        'starts_at': '2026-09-01T00:00:00Z',
        'ends_at': endsAt ??
            DateTime.now()
                .add(const Duration(days: 15))
                .toUtc()
                .toIso8601String(),
        'validity_label': 'До 30 сентября',
        'icon_url': null,
        'limits': [
          {
            'type': 'max_cashback',
            'value': 1200,
            'unit': 'bonus',
            'scope': 'month',
            'original_text': '1200 бонусов / месяц',
          }
        ],
        if (details) ...{
          'conditions': 'Кешбэк не начисляется за подарочные сертификаты.',
          'requirements': ['Только для новых клиентов'],
          'steps': ['Оплатите картой'],
          'links': [],
        },
      },
    };

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/mcc_lookup_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:cashflow/screens/cashback_category_detail_screen.dart';
import 'package:cashflow/screens/cashback_screen.dart';
import 'package:cashflow/screens/settings/mcc_rules_settings_screen.dart';
import 'package:cashflow/screens/widgets/benefit_states_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  group('benefit MCC search', () {
    testWidgets('back while IME is visible preserves the typed MCC result',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(_benefitApp(
        lookup: (code) async => _lookup(code, []),
      ));
      await tester.enterText(find.byKey(const Key('benefit-search')), '5814');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);

      // Exercise the Flutter callback with explicit IME metrics. Real Android
      // IME ordering is covered separately by tests/android/run-back.mjs.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '5814');
      expect(tester.testTextInput.isVisible, isFalse);

      tester.view.resetViewInsets();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-mcc-result')), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets(
        'cached MCC catalogue remains searchable when card refresh fails',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final provider = _CatalogueOnlyProvider()
        ..primaryDataPhase = PrimaryDataPhase.failed
        ..mccCatalog = [
          const MccCodeModel(code: '5814', title: 'Фастфуд'),
        ];
      addTearDown(provider.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<DataProvider>.value(
          value: provider,
          child: const MaterialApp(home: Scaffold(body: CashbackScreen()))));
      await tester.enterText(find.byKey(const Key('benefit-search')), 'фаст');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Фастфуд'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);
      expect(find.text('Фастфуд'), findsOneWidget);
    });
    testWidgets('background revision replaces a result without clearing search',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      var calls = 0;
      var revision = 0;
      final updated = Completer<MccLookupModel>();
      Future<MccLookupModel> lookup(String code) {
        calls++;
        return revision == 0
            ? Future.value(_lookup(code, [
                _bank(1, 'ВТБ', 'excluded', reason: 'Сохранённое исключение'),
              ]))
            : updated.future;
      }

      await tester.pumpWidget(_benefitApp(lookup: lookup));
      await tester.enterText(find.byKey(const Key('benefit-search')), '5814');
      await tester.pumpAndSettle();
      expect(find.textContaining('Сохранённое исключение'), findsOneWidget);
      revision = 1;
      await tester.pumpWidget(_benefitApp(lookup: lookup, revision: revision));
      await tester.pump();
      expect(find.textContaining('Сохранённое исключение'), findsOneWidget);
      expect(find.byKey(const Key('benefit-mcc-loading')), findsNothing);
      updated.complete(_lookup('5814', [
        _bank(1, 'ВТБ', 'category', categories: ['Кафе'], offerIds: [10]),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Входит в «Кафе»'), findsOneWidget);
      expect(find.textContaining('Сохранённое исключение'), findsNothing);
      expect(calls, 2);
      expect(find.widgetWithText(TextField, '5814'), findsOneWidget);
    });

    testWidgets('stale links do not claim that a category is unselected',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_benefitApp(
          lookup: (code) async => MccLookupModel.fromJson({
                'mcc': {'code': code, 'title': 'Фастфуд'},
                '_cached': true,
                '_offer_links_current': false,
                'banks': [
                  _bank(1, 'ВТБ', 'category',
                      categories: ['Кафе'], offerIds: [10]),
                ],
              })));
      await tester.enterText(find.byKey(const Key('benefit-search')), '5814');
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Сохранённые правила доступны.'), findsOneWidget);
      expect(find.text('Входит в «Кафе»'), findsOneWidget);
      expect(find.textContaining('у вас не выбрана'), findsNothing);
      expect(find.text('Повышенный кешбэк'), findsNothing);
    });

    testWidgets('context change discards an older account result',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      final old = Completer<MccLookupModel>();
      await tester.pumpWidget(
          _benefitApp(contextIdentity: 'old', lookup: (_) => old.future));
      await tester.enterText(find.byKey(const Key('benefit-search')), '5814');
      await tester.pump();
      await tester.pumpWidget(_benefitApp(
          contextIdentity: 'new',
          lookup: (code) async => _lookup(code, [
                _bank(7, 'Новый банк', 'not_in_categories'),
              ])));
      old.complete(_lookup('5814', [
        _bank(8, 'Старый банк', 'not_in_categories'),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Новый банк'), findsOneWidget);
      expect(find.text('Старый банк'), findsNothing);
    });
    testWidgets('a typed code lists offers that earn and every bank verdict',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_benefitApp(
        lookup: (code) async => _lookup(code, [
          _bank(1, 'ВТБ', 'category',
              categories: ['Кафе и рестораны'], offerIds: [10]),
          _bank(2, 'Яндекс', 'excluded', reason: 'Не начисляется'),
        ]),
      ));

      await tester.enterText(find.byKey(const Key('benefit-search')), '5814');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);
      expect(find.text('Фастфуд'), findsOneWidget);
      expect(find.text('Повышенный кешбэк'), findsOneWidget);
      expect(find.text('Кафе и рестораны'), findsOneWidget);
      expect(find.text('Входит в «Кафе и рестораны»'), findsOneWidget);
      expect(
        find.text('В исключениях — кешбэк не начисляется · Не начисляется'),
        findsOneWidget,
      );
      expect(find.text('Правила MCC банка не загружены'), findsOneWidget);

      await tester.tap(find.text('Кафе и рестораны'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-compact-detail')), findsOneWidget);

      await tester.tap(find.text('К результатам'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a code outside every category says so and shows all banks',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      await tester.pumpWidget(_benefitApp(
        lookup: (code) async => _lookup(code, [
          _bank(1, 'ВТБ', 'not_in_categories'),
          // An offer outside the plan does not count as chosen.
          _bank(2, 'Яндекс', 'category', categories: ['Отели'], offerIds: [99]),
        ]),
      ));

      await tester.enterText(find.byKey(const Key('benefit-search')), '7011');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('benefit-mcc-no-category')), findsOneWidget);
      expect(
          find.text('Не входит в категории — базовый кешбэк'), findsOneWidget);
      expect(find.text('Входит в «Отели» — у вас не выбрана'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a word finds reference codes that open the check',
        (tester) async {
      await _setViewport(tester, const Size(390, 844));
      String? looked;
      await tester.pumpWidget(_benefitApp(
        lookup: (code) async {
          looked = code;
          return _lookup(code, const []);
        },
      ));

      await tester.enterText(find.byKey(const Key('benefit-search')), 'фастф');
      await tester.pumpAndSettle();
      expect(find.text('MCC-КОДЫ'), findsOneWidget);

      await tester.tap(find.text('Фастфуд'));
      await tester.pumpAndSettle();

      expect(looked, '5814');
      expect(find.byKey(const Key('benefit-mcc-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('category detail lists and filters the bank MCC codes',
      (tester) async {
    await _setViewport(tester, const Size(390, 1600));
    final provider = _provider((request) {
      if (request.url.path == '/api/cashback/17/mcc-rules') {
        return _json(_offerRules);
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: CashbackCategoryDetailScreen(
            category: CashbackCategoryModel(
              id: 17,
              name: 'Кафе и рестораны',
              startDate: DateTime(2026, 10),
              endDate: DateTime(2026, 10, 31),
              isSelected: true,
              cashbackPercent: 5,
              cardId: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MCC-коды'), findsOneWidget);
    expect(find.text('Рестораны'), findsOneWidget);
    expect(find.text('Фастфуд'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('offer-mcc-filter')), '6011');
    await tester.pumpAndSettle();

    expect(find.text('Фастфуд'), findsNothing);
    expect(find.text('Выдача наличных'), findsOneWidget);
    expect(find.textContaining('Кешбэк не начисляется'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MCC rules page searches codes by number and meaning',
      (tester) async {
    await _setViewport(tester, const Size(400, 900));
    final provider = _provider((request) {
      if (request.url.path == '/api/admin/mcc-rule-revisions') {
        return _json([_revision]);
      }
      if (request.url.path == '/api/mcc') {
        return _json(_catalog);
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MccRulesSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mcc-rules-search')), 'фаст');
    await tester.pumpAndSettle();
    expect(find.text('Кафе и рестораны'), findsOneWidget);
    expect(find.text('Включён 5814 — Фастфуд'), findsOneWidget);
    expect(find.text('Такси'), findsNothing);

    await tester.enterText(find.byKey(const Key('mcc-rules-search')), '6011');
    await tester.pumpAndSettle();
    expect(find.text('Исключения программы · 1'), findsOneWidget);
    expect(find.text('Выдача наличных'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mcc-rules-search')), '7011');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mcc-rules-search-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

http.Response _json(Object value) => http.Response.bytes(
      utf8.encode(json.encode(value)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _CatalogueOnlyProvider extends DataProvider {
  _CatalogueOnlyProvider()
      : super(
            mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
            httpClient: MockClient((_) async => http.Response('{}', 503)));

  @override
  Future<MccLookupModel> lookupMcc(String code) async =>
      _lookup(code, const []);
}

DataProvider _provider(http.Response Function(http.Request) respond) =>
    DataProvider(
      mccCacheStore: MccCacheStore(storage: MemoryMccStorage()),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((request) async => respond(request)),
      secureStorage: const FlutterSecureStorage(),
    )
      ..currentAuthUser = AuthIdentity(id: 1, username: 't', role: 'admin')
      ..banks = [BankModel(id: 1, name: 'ВТБ')]
      ..users = [UserModel(id: 2, name: 'Анна')]
      ..cards = [
        CardModel(id: 3, bankId: 1, userId: 2, lastFourDigits: '1234'),
      ];

Widget _benefitApp({
  required Future<MccLookupModel> Function(String code) lookup,
  int revision = 0,
  String? contextIdentity,
}) =>
    MaterialApp(
      home: Scaffold(
        body: BenefitStatesView(
          phase: PrimaryDataPhase.ready,
          hasUsableSnapshot: true,
          items: [
            for (final (id, bankId, bank, name) in const [
              (10, 1, 'ВТБ', 'Кафе и рестораны'),
              (11, 2, 'Яндекс', 'Такси'),
              (12, 3, 'Озон', 'Аптеки'),
            ])
              BenefitItemData(
                category: CashbackCategoryModel(
                  id: id,
                  name: name,
                  startDate: DateTime(2026, 10),
                  endDate: DateTime(2026, 11),
                  isSelected: true,
                  isBankConfirmed: true,
                  cashbackPercent: 5,
                  cardId: id,
                ),
                cardLabel: '$bank •$id$id',
                bankId: bankId,
                bankName: bank,
                lastFourDigits: '00$id',
              ),
          ],
          mccResults: const [
            BenefitMccSearchResult(
              code: '5814',
              name: 'Фастфуд',
              description: 'Где начислят кешбэк',
            ),
          ],
          onLookupMcc: lookup,
          mccDataRevision: revision,
          mccContextIdentity: contextIdentity,
          onRefresh: () async {},
        ),
      ),
    );

MccLookupModel _lookup(String code, List<Map<String, dynamic>> banks) =>
    MccLookupModel.fromJson({
      'mcc': {'code': code, 'title': code == '5814' ? 'Фастфуд' : 'Отели'},
      'banks': banks,
    });

Map<String, dynamic> _bank(
  int id,
  String name,
  String status, {
  List<String> categories = const [],
  List<int> offerIds = const [],
  String? reason,
}) =>
    {
      'bank': {'id': id, 'name': name, 'icon_key': 'generic'},
      'program': {'name': 'Программа'},
      'status': status,
      'completeness': 'exact_mcc',
      'exclusion': reason == null
          ? null
          : {'mcc': '0000', 'kind': 'always', 'reason': reason},
      'categories': [
        for (final category in categories) {'name': category, 'kind': 'mcc'},
      ],
      'offer_ids': offerIds,
    };

const _offerRules = {
  'program': {'name': 'Кешбэк ВТБ'},
  'valid_from': '2026-10-01T00:00:00+00:00',
  'valid_to': null,
  'category': {
    'name': 'Кафе и рестораны',
    'kind': 'mcc',
    'completeness': 'exact_mcc',
    'included': [
      {'code': '5811', 'title': 'Кейтеринг'},
      {'code': '5812', 'title': 'Рестораны'},
      {'code': '5813', 'title': 'Бары'},
      {'code': '5814', 'title': 'Фастфуд'},
    ],
    'excluded': [],
  },
  'exclusions': [
    {
      'mcc': '6011',
      'kind': 'always',
      'reason': null,
      'title': 'Выдача наличных',
    },
    {
      'mcc': '4900',
      'kind': 'unless_category',
      'reason': null,
      'title': 'Коммунальные услуги',
    },
    {'mcc': '4511', 'kind': 'conditional', 'reason': null, 'title': 'Авиа'},
  ],
};

const _catalog = [
  {'code': '5812', 'title': 'Рестораны'},
  {'code': '5814', 'title': 'Фастфуд'},
  {'code': '4121', 'title': 'Такси'},
  {'code': '6011', 'title': 'Выдача наличных'},
  {'code': '7011', 'title': 'Отели'},
];

final _revision = {
  'id': 5,
  'bank_id': 1,
  'program': {'source_key': 'main', 'name': 'Кешбэк ВТБ'},
  'valid_from': '2026-10-01T00:00:00+00:00',
  'valid_to': null,
  'validity_confidence': 'exact',
  'completeness': 'exact_mcc',
  'status': 'published',
  'recorded_at': '2026-10-01T00:00:00+00:00',
  'source': {'type': 'manual_verified'},
  'global_excluded_mcc': ['6011'],
  'exclusions': [
    {'mcc': '6011', 'kind': 'always', 'reason': null},
  ],
  'conditions': [],
  'categories': [
    {
      'id': 1,
      'source_key': 'cafe',
      'name': 'Кафе и рестораны',
      'included_mcc': ['5812', '5814'],
      'excluded_mcc': [],
    },
    {
      'id': 2,
      'source_key': 'taxi',
      'name': 'Такси',
      'included_mcc': ['4121'],
      'excluded_mcc': [],
    },
  ],
};

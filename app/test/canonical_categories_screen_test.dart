import 'dart:convert';

import 'package:cashflow/models/canonical_category_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/settings/canonical_categories_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/mcc_test_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fuel = CanonicalCategoryModel(
    key: 'fuel',
    title: 'АЗС',
    groupKey: 'auto',
    groupTitle: 'Авто',
    aliases: ['заправки', 'топливо'],
    defaultPriority: 50,
  );
  const pharmacy = CanonicalCategoryModel(
    key: 'pharmacy',
    title: 'Аптеки',
    groupKey: 'health_beauty',
    groupTitle: 'Здоровье и красота',
    aliases: ['лекарства'],
    defaultPriority: 40,
  );

  late List<http.Request> requests;

  DataProvider provider({String role = 'admin'}) {
    requests = [];
    return DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test:8443',
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final aliases = (json.decode(request.body) as Map)['aliases'] as List;
        return http.Response(
          json.encode({
            ...CanonicalCategoryModel.toJson(fuel),
            'aliases': aliases,
            'core_mcc': ['5541'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )
      ..currentAuthUser =
          AuthIdentity(id: 1, username: 'family-admin', role: role)
      ..canonicalCategories = [pharmacy, fuel];
  }

  Future<void> pump(WidgetTester tester, DataProvider value) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: value,
        child: const MaterialApp(home: CanonicalCategoriesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists categories by group with their synonyms', (tester) async {
    await pump(tester, provider());

    expect(find.text('Авто'), findsOneWidget);
    expect(find.text('АЗС'), findsOneWidget);
    expect(find.text('заправки, топливо'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('canonical-categories-search')), 'топл');
    await tester.pump();
    expect(find.text('АЗС'), findsOneWidget);
    expect(find.text('Аптеки'), findsNothing);

    await tester.enterText(
        find.byKey(const Key('canonical-categories-search')), 'бензин');
    await tester.pump();
    expect(find.byKey(const Key('canonical-categories-empty')), findsOneWidget);
  });

  testWidgets('an editor adds and removes synonyms and saves them',
      (tester) async {
    final value = provider();
    await pump(tester, value);

    await tester.tap(find.byKey(const Key('canonical-category-fuel')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('canonical-alias-input')), '  бензин ');
    await tester.tap(find.byKey(const Key('canonical-alias-add')));
    await tester.pump();
    expect(find.byKey(const Key('canonical-alias-бензин')), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byKey(const Key('canonical-alias-топливо')),
      matching: find.byTooltip('Удалить'),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('canonical-category-save')));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/canonical-categories/fuel');
    expect(json.decode(requests.single.body), {
      'aliases': ['заправки', 'бензин'],
    });
    expect(value.canonicalCategories.last.aliases, ['заправки', 'бензин']);
    expect(find.text('Синонимы сохранены'), findsOneWidget);
  });

  testWidgets('a viewer sees synonyms without editing controls',
      (tester) async {
    await pump(tester, provider(role: 'viewer'));

    await tester.tap(find.byKey(const Key('canonical-category-fuel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('canonical-alias-заправки')), findsOneWidget);
    expect(find.byKey(const Key('canonical-alias-input')), findsNothing);
    expect(find.byKey(const Key('canonical-category-save')), findsNothing);
  });
}

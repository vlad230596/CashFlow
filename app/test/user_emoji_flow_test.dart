import 'dart:convert';

import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/cashback_screen.dart';
import 'package:cashflow/screens/settings/user_edit_screen.dart';
import 'package:cashflow/utils/identity_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/mcc_test_cache.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'selected emoji is saved, cached and immediately used by the main screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <http.Request>[];
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/users/7');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['icon_key'], 'emoji:🦊');
        return http.Response(jsonEncode({'id': 7, ...payload}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    )
      ..users = [UserModel(id: 7, name: 'Тест', iconKey: 'girl')]
      ..banks = [BankModel(id: 1, name: 'Тестовый банк', iconKey: 'generic')]
      ..cards = [CardModel(id: 1, bankId: 1, userId: 7, lastFourDigits: '1234')]
      ..primaryDataPhase = PrimaryDataPhase.ready;
    final now = DateTime.now();
    provider.activeCashbackCategories = [
      CashbackCategoryModel(
        id: 1,
        name: 'Аптеки',
        cardId: 1,
        cashbackPercent: 5,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 30)),
        isSelected: true,
        isBankConfirmed: true,
      )
    ];
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: const CashbackScreen(),
                    floatingActionButton: FloatingActionButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserEditScreen(
                                existingUser: provider.users.single),
                          )),
                      child: const Icon(Icons.edit),
                    ),
                  ))),
    ));
    await settle(tester);
    expect(
        tester
            .widgetList<UserIconBadge>(find.byType(UserIconBadge))
            .every((badge) => badge.iconKey == 'girl'),
        isTrue);
    expect(find.byType(PersonMarkerBadge), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('choose-user-emoji')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('emoji-search')), 'лиса');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('emoji:🦊')));
    await settle(tester);
    expect(requests, isEmpty);
    await tester.tap(find.text('Сохранить'));
    await settle(tester);
    expect(requests, hasLength(1));
    expect(provider.users.single.iconKey, 'emoji:🦊');
    expect(find.byType(UserEditScreen), findsNothing);
    expect(find.byType(UserIconBadge), findsWidgets);
    expect(
        tester
            .widgetList<UserIconBadge>(find.byType(UserIconBadge))
            .every((badge) => badge.iconKey == 'emoji:🦊'),
        isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect((jsonDecode(prefs.getString('users')!) as List).single['icon_key'],
        'emoji:🦊');
    expect(tester.takeException(), isNull);
  });
}

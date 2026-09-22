import 'dart:convert';

import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/admin/admin_hub_screen.dart';
import 'package:cashflow/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DataProvider provider({String role = 'admin'}) {
    return DataProvider(
      apiBaseUrl: 'https://cashflow.test:8443',
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    )
      ..currentAuthUser =
          AuthIdentity(id: 1, username: 'family-admin', role: role)
      ..banks = [
        BankModel(id: 1, name: 'Альфа-Банк', description: 'Основной'),
      ]
      ..users = [UserModel(id: 1, name: 'Влад')]
      ..cards = [CardModel(id: 1, lastFourDigits: '4127')];
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child,
    DataProvider value, {
    Size size = const Size(375, 812),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: value,
        child: MaterialApp(theme: ThemeData(useMaterial3: true), home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin hub shows real counters in compact layout',
      (tester) async {
    await pump(tester, const AdminHubScreen(), provider());

    expect(find.text('Управление'), findsOneWidget);
    expect(find.text('Банки'), findsOneWidget);
    expect(find.text('Участники'), findsOneWidget);
    expect(find.text('Карты'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Правила MCC'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Правила MCC'), findsOneWidget);
    expect(find.text('Выберите банк'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin hub uses navigation rail at expanded width',
      (tester) async {
    await pump(
      tester,
      const AdminHubScreen(),
      provider(),
      size: const Size(1100, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Обзор'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin hub supports large text without overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await pump(tester, const AdminHubScreen(), provider());

    await tester.scrollUntilVisible(
      find.text('Правила MCC'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Правила MCC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-admin deep link has a safe exit', (tester) async {
    var returned = false;
    await pump(
      tester,
      AdminHubScreen(onReturnToBenefit: () => returned = true),
      provider(role: 'viewer'),
    );

    expect(find.text('Недостаточно прав'), findsOneWidget);
    await tester.tap(find.text('Вернуться в Выгоду'));
    expect(returned, isTrue);
  });

  testWidgets('login maps backend authentication failures', (tester) async {
    final loginProvider = DataProvider(
      apiBaseUrl: 'https://cashflow.test:8443',
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient(
        (_) async => http.Response(
          json.encode({'error': 'Invalid username or password'}),
          401,
        ),
      ),
    );
    await pump(tester, const LoginScreen(), loginProvider);

    await tester.enterText(find.byType(TextFormField).first, 'family-admin');
    await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Неверный логин или пароль'), findsOneWidget);
    expect(find.text('Доступ выдаёт администратор'), findsOneWidget);
    expect(find.text('cashflow.test:8443'), findsNothing);
  });

  testWidgets('login keeps server authority behind technical details',
      (tester) async {
    await pump(tester, const LoginScreen(), provider(role: 'viewer'));

    await tester.tap(find.text('Технические детали'));
    await tester.pumpAndSettle();

    expect(find.text('cashflow.test:8443'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

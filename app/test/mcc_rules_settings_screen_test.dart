import 'dart:convert';

import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/settings/mcc_rules_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DataProvider providerWithEmptyRules() {
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/admin/mcc-rule-revisions') {
        return http.Response('[]', 200);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/mcc-rules/auto-import')) {
        return http.Response(
          json.encode({
            'error': 'Automatic MCC source is not configured for this bank yet',
          }),
          501,
        );
      }
      return http.Response('{}', 404);
    });
    return DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      httpClient: client,
      secureStorage: const FlutterSecureStorage(),
    )..banks = [
        BankModel(id: 1, name: 'Тестовый банк', description: 'Только тест'),
      ];
  }

  Future<void> pumpScreen(WidgetTester tester, DataProvider provider) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MccRulesSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the unobtrusive advanced MCC management entry point',
      (tester) async {
    await pumpScreen(tester, providerWithEmptyRules());

    expect(find.text('Расширенные настройки'), findsOneWidget);
    expect(find.text('Тестовый банк'), findsOneWidget);
    expect(find.text('Подгрузить автоматически'), findsOneWidget);
    expect(find.text('Для этого банка правил пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a blank revision editor', (tester) async {
    await pumpScreen(tester, providerWithEmptyRules());

    await tester.tap(find.text('Создать с нуля'));
    await tester.pumpAndSettle();

    expect(find.text('Тестовый банк · MCC'), findsOneWidget);
    expect(find.text('Глобальные исключения MCC'), findsOneWidget);
    expect(find.text('Добавить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

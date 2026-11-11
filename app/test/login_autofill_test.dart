import 'dart:async';
import 'dart:convert';

import 'package:cashflow/main.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

void main() {
  // Regression: the login screen committed the autofill context after
  // login() resolved, i.e. after the whole initial refresh. By then the shell
  // was shown and the user could be typing into the Benefit search; on web
  // the commit closed that input connection and dropped typed characters.
  testWidgets('initial refresh ending does not close the search input',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final lastRefreshStep = Completer<http.Response>();
    final offer = {
      'id': 51,
      'name': 'Офлайн покупки',
      'card_id': 31,
      'cashback_percent': 5,
      'start_date': '2020-01-01T00:00:00',
      'end_date': '2099-12-31T23:59:59',
      'is_selected': true,
      'is_bank_confirmed': true,
      'canonical_keys': <String>[],
    };
    final bodies = <String, Object>{
      '/api/banks': [
        {'id': 11, 'name': 'Тестовый банк'}
      ],
      '/api/users': [
        {'id': 21, 'name': 'Тестовый участник'}
      ],
      '/api/cards': [
        {
          'id': 31,
          'bank_id': 11,
          'user_id': 21,
          'payment_system': 'МИР',
          'card_type': 'Дебетовая',
          'last_four_digits': '4242',
          'is_active': true,
        }
      ],
      '/api/active_cashback': [offer],
      '/api/cashback': [offer],
    };
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      mccCacheStore: isolatedMccCache(),
      reminderNotificationService: FakeReminders(),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/login') {
          return http.Response(
            json.encode({
              'user': {'id': 7, 'username': 'reader', 'role': 'viewer'},
              'access_token': 'synthetic-token',
              'expires_at': '2099-01-01T00:00:00Z',
            }),
            200,
          );
        }
        // The last step of the sequential refresh is held until the user
        // has started typing into the search field.
        if (path == '/api/partner-offers') return lastRefreshStep.future;
        final body = bodies[path];
        return body == null
            ? http.Response('{"error":"not found"}', 404)
            : _json(body);
      }),
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MyApp(),
    ));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'reader');
    await tester.enterText(fields.at(1), 'synthetic-password');
    await tester.tap(find.text('Войти'));

    final search = find.byKey(const Key('benefit-search'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (search.evaluate().isNotEmpty &&
          tester.widget<TextField>(search).enabled != false) {
        break;
      }
    }
    expect(tester.widget<TextField>(search).enabled, isNot(false));
    expect(lastRefreshStep.isCompleted, isFalse,
        reason: 'the refresh must still be running while the user types');
    // Native credentials are still committed when the login screen goes away.
    expect(
      tester.testTextInput.log
          .map((call) => call.method)
          .contains('TextInput.finishAutofillContext'),
      isTrue,
    );

    await tester.enterText(search, 'Офл');
    tester.testTextInput.log.clear();
    lastRefreshStep.complete(
      http.Response(json.encode({'items': [], 'total': 0}), 200),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final methods = tester.testTextInput.log.map((call) => call.method);
    expect(methods, isNot(contains('TextInput.finishAutofillContext')));
    expect(methods, isNot(contains('TextInput.clearClient')));
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.widget<TextField>(search).controller!.text, 'Офл');
  });
}

http.Response _json(Object body) => http.Response.bytes(
      utf8.encode(json.encode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

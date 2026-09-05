import 'dart:convert';

import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the production server as the default API URL', () {
    expect(
      DataProvider.defaultApiBaseUrl,
      'https://cash-flow-app.duckdns.org:8443',
    );
  });

  test('cashback category preserves description and stackable type', () {
    final category = CashbackCategoryModel.fromJson({
      'id': 7,
      'name': 'Аптеки в августе',
      'start_date': '2026-08-01T00:00:00',
      'end_date': '2026-09-01T00:00:00',
      'is_selected': true,
      'cashback_percent': 3,
      'card_id': 3,
      'description': 'Дополнительно к обычному кэшбэку',
      'category_type': 'stackable_bonus',
      'is_selection_locked': true,
      'max_cashback_amount': 2000,
      'min_purchase_amount': 5000,
    });

    expect(category.description, 'Дополнительно к обычному кэшбэку');
    expect(category.isStackableBonus, isTrue);
    expect(category.isSelectionLocked, isTrue);
    expect(category.maxCashbackAmount, 2000);
    expect(category.minPurchaseAmount, 5000);
    expect(
      CashbackCategoryModel.toJson(category)['category_type'],
      'stackable_bonus',
    );
    expect(
      CashbackCategoryModel.toJson(category)['is_selection_locked'],
      isTrue,
    );
    expect(
      CashbackCategoryModel.toJson(category)['max_cashback_amount'],
      2000,
    );
    expect(
      CashbackCategoryModel.toJson(category)['min_purchase_amount'],
      5000,
    );
  });

  test('task bonus category is not selectable', () {
    final category = CashbackCategoryModel.fromJson({
      'id': 8,
      'name': 'Награда за задание',
      'start_date': '2026-09-01T00:00:00',
      'end_date': '2026-10-01T00:00:00',
      'is_selected': false,
      'cashback_percent': 5,
      'card_id': 3,
      'category_type': 'task_bonus',
    });

    expect(category.isTaskBonus, isTrue);
    expect(category.isSelectable, isFalse);
    expect(
        CashbackCategoryModel.toJson(category)['category_type'], 'task_bonus');
  });

  test('filters effective active cashback categories by selected date',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider()
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Current',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 2,
          name: 'Expired',
          startDate: DateTime(2026, 3),
          endDate: DateTime(2026, 4),
          isSelected: true,
          cashbackPercent: 10,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 3,
          name: 'Not selected',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: false,
          cashbackPercent: 15,
          cardId: 1,
        ),
      ];

    await provider.setCashbackEffectiveDate(DateTime(2026, 4, 25));

    expect(
      provider.effectiveActiveCashbackCategories
          .map((category) => category.name),
      ['Current'],
    );
  });

  test('uses active cashback cache when full cashback cache is empty',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider()
      ..activeCashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Cached',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
      ];

    await provider.setCashbackEffectiveDate(DateTime(2026, 4, 25));

    expect(provider.effectiveActiveCashbackCategories.single.name, 'Cached');
  });

  test('restores a previously verified session while offline', () async {
    final expiration = DateTime.now().toUtc().add(const Duration(days: 30));
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'persisted-token',
      'cashflowAuthIdentity': json.encode({
        'id': 7,
        'username': 'admin',
        'role': 'admin',
      }),
      'cashflowSessionExpiresAt': expiration.toIso8601String(),
    });
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );

    await provider.initialize();

    expect(provider.isAuthenticated, isTrue);
    expect(provider.currentAuthUser?.username, 'admin');
  });

  test('clears a saved session only when the server rejects it', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'expired-token',
      'cashflowAuthIdentity': json.encode({
        'id': 7,
        'username': 'admin',
        'role': 'admin',
      }),
      'cashflowSessionExpiresAt':
          DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
    });
    SharedPreferences.setMockInitialValues({});
    final storage = const FlutterSecureStorage();
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      secureStorage: storage,
      httpClient: MockClient((_) async => http.Response('Unauthorized', 401)),
    );

    await provider.initialize();

    expect(provider.isAuthenticated, isFalse);
    expect(await storage.read(key: 'cashflowAccessToken'), isNull);
    expect(await storage.read(key: 'cashflowAuthIdentity'), isNull);
  });

  test('does not restore an expired cached session while offline', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'expired-token',
      'cashflowAuthIdentity': json.encode({
        'id': 7,
        'username': 'admin',
        'role': 'admin',
      }),
      'cashflowSessionExpiresAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((_) async {
        throw http.ClientException('offline');
      }),
    );

    await provider.initialize();

    expect(provider.isAuthenticated, isFalse);
  });

  test('stores identity and extended server expiration securely', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'persisted-token',
      'cashflowAuthIdentity': json.encode({
        'id': 7,
        'username': 'old-name',
        'role': 'viewer',
      }),
    });
    SharedPreferences.setMockInitialValues({});
    final storage = const FlutterSecureStorage();
    const extendedExpiration = '2027-09-05T12:00:00+00:00';
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      secureStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          expect(request.headers['Authorization'], 'Bearer persisted-token');
          return http.Response(
            json.encode({'id': 7, 'username': 'admin', 'role': 'admin'}),
            200,
            headers: {
              'X-CashFlow-Session-Expires-At': extendedExpiration,
            },
          );
        }
        return http.Response('[]', 200);
      }),
    );

    await provider.initialize();

    expect(provider.currentAuthUser?.username, 'admin');
    expect(
      await storage.read(key: 'cashflowSessionExpiresAt'),
      '2027-09-05T12:00:00.000Z',
    );
    expect(
      json.decode(await storage.read(key: 'cashflowAuthIdentity') as String),
      {'id': 7, 'username': 'admin', 'role': 'admin'},
    );
  });
}

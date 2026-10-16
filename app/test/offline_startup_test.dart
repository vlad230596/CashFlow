import 'dart:async';
import 'dart:convert';

import 'package:cashflow/providers/data_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mcc_test_cache.dart';

void main() {
  for (final status in [503, 401]) {
    test('cached startup does not await auth; delayed $status is respected',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'cashflowAccessToken': 'synthetic-token',
        'cashflowAuthIdentity': json.encode({
          'id': 7,
          'username': 'offline-reader',
          'role': 'viewer',
        }),
      });
      const scope = 'data:v1:https%3A%2F%2Fcashflow.test:7:';
      SharedPreferences.setMockInitialValues({
        '${scope}banks': json.encode([
          {'id': 11, 'name': 'Cached bank'}
        ]),
        '${scope}dataSnapshotUpdatedAt': '2026-10-15T07:00:00Z',
      });
      final validation = Completer<http.Response>();
      final requested = Completer<void>();
      final settled = Completer<void>();
      final provider = DataProvider(
        apiBaseUrl: 'https://cashflow.test',
        mccCacheStore: isolatedMccCache(),
        httpClient: MockClient((request) {
          if (request.url.path == '/api/auth/me') {
            requested.complete();
            return validation.future;
          }
          return Future.value(http.Response('Unavailable', 503));
        }),
      );
      provider.addListener(() {
        if (validation.isCompleted &&
            provider.authReady &&
            (!provider.isAuthenticated ||
                provider.primaryDataPhase == PrimaryDataPhase.failed) &&
            !settled.isCompleted) {
          settled.complete();
        }
      });
      try {
        await provider.initialize().timeout(const Duration(seconds: 1));
        await requested.future.timeout(const Duration(seconds: 1));
        expect(validation.isCompleted, isFalse);
        expect(provider.authReady, isTrue);
        expect(provider.isAuthenticated, isTrue);
        expect(provider.banks.single.name, 'Cached bank');

        validation.complete(http.Response('Unavailable', status));
        await settled.future.timeout(const Duration(seconds: 1));
        if (status == 401) {
          expect(provider.isAuthenticated, isFalse);
          expect(provider.banks, isEmpty);
          expect(
              await const FlutterSecureStorage()
                  .read(key: 'cashflowAccessToken'),
              isNull);
        } else {
          expect(provider.isAuthenticated, isTrue);
          expect(provider.banks.single.name, 'Cached bank');
        }
      } finally {
        if (!validation.isCompleted) {
          validation.complete(http.Response('Unavailable', 503));
        }
        provider.dispose();
      }
    });
  }
}

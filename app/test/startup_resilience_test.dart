import 'dart:async';
import 'dart:convert';

import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/services/app_log.dart';
import 'package:cashflow/services/mcc_cache_store.dart';
import 'package:cashflow/services/timeout_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingMccStorage extends MemoryMccStorage {
  int reads = 0;
  @override
  Future<String?> read(String key) {
    reads++;
    return super.read(key);
  }
}

class _MemoryLogStorage implements AppLogStorage {
  final List<String> appends = [];
  @override
  Future<void> append(String lines) async => appends.add(lines);
}

void main() {
  group('TimeoutClient', () {
    test('fails a request whose response never arrives', () async {
      final never = Completer<http.Response>();
      final reported = <Object?>[];
      final client = TimeoutClient(
        MockClient((_) => never.future),
        responseTimeout: const Duration(milliseconds: 50),
        onFinished: (_, status, __, error) => reported.add(error ?? status),
      );
      await expectLater(client.get(Uri.parse('https://cashflow.test/api/x')),
          throwsA(isA<TimeoutException>()));
      expect(reported.single, isA<TimeoutException>());
    });

    test('fails a body that stops arriving', () async {
      final body = StreamController<List<int>>();
      final client = TimeoutClient(
        MockClient.streaming((_, __) async {
          body.add(utf8.encode('[1,'));
          return http.StreamedResponse(body.stream, 200);
        }),
        bodyTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(client.get(Uri.parse('https://cashflow.test/api/x')),
          throwsA(isA<TimeoutException>()));
      await body.close();
    });

    test('passes a normal response through', () async {
      final client =
          TimeoutClient(MockClient((_) async => http.Response('ok', 200)));
      final response =
          await client.get(Uri.parse('https://cashflow.test/api/x'));
      expect(response.statusCode, 200);
      expect(response.body, 'ok');
    });
  });

  test('app log batches lines of one turn into a single append', () async {
    final storage = _MemoryLogStorage();
    final log = AppLog(storage: storage);
    log.event('first');
    log.event('second');
    await log.flush();
    expect(storage.appends, hasLength(1));
    expect(storage.appends.single, contains('first'));
    expect(storage.appends.single, contains('second'));
    expect(storage.appends.single, matches(RegExp(r'\+\d+ms second\n$')));
  });

  test('startup opens cached data before reading the MCC cache', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cashflowAccessToken': 'synthetic-token',
      'cashflowAuthIdentity':
          json.encode({'id': 7, 'username': 'reader', 'role': 'viewer'}),
    });
    const scope = 'data:v1:https%3A%2F%2Fcashflow.test:7:';
    SharedPreferences.setMockInitialValues({
      '${scope}banks': json.encode([
        {'id': 11, 'name': 'Cached bank'}
      ]),
    });
    final storage = _RecordingMccStorage();
    final firstFrame = Completer<void>();
    final provider = DataProvider(
      apiBaseUrl: 'https://cashflow.test',
      mccCacheStore: MccCacheStore(storage: storage),
      httpClient: MockClient((_) async => http.Response('Unavailable', 503)),
      afterFirstFrame: () => firstFrame.future,
    );
    try {
      await provider.initialize();
      expect(provider.authReady, isTrue);
      expect(provider.banks.single.name, 'Cached bank');
      await pumpEventQueue();
      expect(storage.reads, 0);

      firstFrame.complete();
      await pumpEventQueue();
      expect(storage.reads, greaterThan(0));
    } finally {
      provider.dispose();
    }
  });
}

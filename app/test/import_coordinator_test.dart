import 'dart:convert';
import 'package:cashflow/services/import_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('partial import retains committed category counts and refreshes',
      () async {
    var refreshed = false;
    final coordinator = ImportCoordinator(
      post: (path, body) async => path == 'cashback/import'
          ? http.Response(json.encode({'created': 4, 'updated': 2}), 200)
          : throw http.ClientException('offline'),
      refresh: () async {
        refreshed = true;
        return true;
      },
    );
    try {
      await coordinator.run('{}', 3);
      fail('Expected partial failure');
    } on PartialImportException catch (error) {
      expect(error.stage, ImportStage.partnerOffers);
      expect(error.result.created, 4);
      expect(error.result.updated, 2);
      expect(refreshed, isTrue);
    }
  });

  test('refresh failure retains both completed import stages', () async {
    final coordinator = ImportCoordinator(
      post: (path, body) async => http.Response(
          json.encode(path == 'cashback/import'
              ? {'created': 1}
              : {'created_offers': 2}),
          200),
      refresh: () async => false,
    );
    try {
      await coordinator.run('{}', 3);
      fail('Expected refresh failure');
    } on PartialImportException catch (error) {
      expect(error.stage, ImportStage.refresh);
      expect(error.result.created, 1);
      expect(error.result.createdPartnerOffers, 2);
    }
  });
}

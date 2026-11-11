import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/card_balance_model.dart';
import 'api_client.dart';

/// HTTP transport for `/api/card-balances` and `/api/admin/zenmoney`.
///
/// The ZenMoney token is only ever sent (admin), never received.
class CardBalanceApi {
  CardBalanceApi(this._client, this._uri);

  final http.Client _client;
  final Uri Function(String path) _uri;

  static const _json = {'Content-Type': 'application/json'};

  /// Balances; the server refreshes from ZenMoney first when its snapshot is
  /// older than ~15 minutes.
  Future<CardBalancesSnapshot> balances() async {
    final response = await _client.get(_uri('card-balances'));
    _expect(
        response, const {200}, 'card-balances', 'Не удалось загрузить балансы');
    return _snapshot(response);
  }

  /// Editor+: ask the server to read ZenMoney now (throttled server-side).
  Future<CardBalancesSnapshot> refresh() async {
    final response = await _client.post(_uri('card-balances/refresh'));
    _expect(response, const {200}, 'card-balances/refresh',
        'Не удалось обновить балансы');
    return _snapshot(response);
  }

  Future<CardBalanceMapping> mapping() async {
    final response = await _client.get(_uri('card-balances/mapping'));
    _expect(response, const {200}, 'card-balances/mapping',
        'Не удалось загрузить сопоставление');
    return CardBalanceMapping.fromJson(
        json.decode(response.body) as Map<String, dynamic>);
  }

  /// [accountId] null records an explicit "no account" for the card.
  Future<void> setLink(int cardId, String? accountId) async {
    final response = await _client.put(
      _uri('card-balances/mapping/$cardId'),
      headers: _json,
      body: json.encode({'account_id': accountId}),
    );
    _expect(response, const {200}, 'card-balances/mapping/$cardId',
        'Не удалось сохранить');
  }

  /// Forget the choice; automatic matching applies on the next refresh.
  Future<void> resetLink(int cardId) async {
    final response =
        await _client.delete(_uri('card-balances/mapping/$cardId'));
    _expect(response, const {204}, 'card-balances/mapping/$cardId',
        'Не удалось сбросить');
  }

  Future<ZenmoneySettings> settings() async {
    final response = await _client.get(_uri('admin/zenmoney'));
    _expect(response, const {200}, 'admin/zenmoney',
        'Не удалось загрузить настройки ZenMoney');
    return _settings(response);
  }

  Future<ZenmoneySettings> setToken(String token) async {
    final response = await _client.put(
      _uri('admin/zenmoney/token'),
      headers: _json,
      body: json.encode({'token': token}),
    );
    _expect(response, const {200}, 'admin/zenmoney/token',
        'Не удалось сохранить токен');
    return _settings(response);
  }

  Future<ZenmoneySettings> deleteToken() async {
    final response = await _client.delete(_uri('admin/zenmoney/token'));
    _expect(response, const {200}, 'admin/zenmoney/token',
        'Не удалось удалить токен');
    return _settings(response);
  }

  static CardBalancesSnapshot _snapshot(http.Response response) =>
      CardBalancesSnapshot.fromJson(
          json.decode(response.body) as Map<String, dynamic>);

  static ZenmoneySettings _settings(http.Response response) =>
      ZenmoneySettings.fromJson(
          json.decode(response.body) as Map<String, dynamic>);

  static void _expect(
    http.Response response,
    Set<int> statuses,
    String endpoint,
    String fallback,
  ) {
    if (statuses.contains(response.statusCode)) return;
    var message = fallback;
    try {
      final payload = json.decode(response.body);
      if (payload is Map<String, dynamic>) {
        final text = payload['message'] ?? payload['error'];
        if (text is String) message = text;
      }
    } catch (_) {
      // Keep the fallback for non-JSON bodies.
    }
    throw ApiException(endpoint, response.statusCode, message);
  }
}

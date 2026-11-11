import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/promo_model.dart';
import 'api_client.dart';

/// HTTP transport for `/api/promos`; state and caching stay in DataProvider.
class PromoApi {
  PromoApi(this._client, this._uri);

  final http.Client _client;
  final Uri Function(String path) _uri;

  static const _json = {'Content-Type': 'application/json'};

  Future<List<PromoModel>> list() async {
    final response = await _client.get(_uri('promos?status=all'));
    _expect(response, const {200}, 'promos', 'Не удалось загрузить промокоды');
    final payload = json.decode(response.body);
    final items = payload is List
        ? payload
        : (payload as Map<String, dynamic>)['items'] as List? ?? const [];
    return items
        .map((item) => PromoModel.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<PromoModel> detail(int id) async {
    final response = await _client.get(_uri('promos/$id'));
    _expect(response, const {200}, 'promos/$id', 'Не удалось загрузить промокод');
    return _decode(response);
  }

  /// 201 for a new item, 200 when [PromoModel.clientId] was already stored.
  Future<PromoModel> create(PromoModel item) async {
    final response = await _client.post(
      _uri('promos'),
      headers: _json,
      body: json.encode(item.toMutationJson()),
    );
    _expect(response, const {200, 201}, 'promos', 'Не удалось сохранить');
    return _decode(response);
  }

  Future<PromoModel> update(PromoModel item) async {
    final id = item.id;
    if (id == null) throw ArgumentError('A saved promo is required for update');
    final response = await _client.put(
      _uri('promos/$id'),
      headers: _json,
      body: json.encode(item.toMutationJson()),
    );
    _expect(response, const {200}, 'promos/$id', 'Не удалось сохранить');
    return _decode(response);
  }

  Future<void> delete(int id) async {
    final response = await _client.delete(_uri('promos/$id'));
    _expect(response, const {204}, 'promos/$id', 'Не удалось удалить');
  }

  /// `use`, `unuse`, `archive` or `restore`.
  Future<PromoModel> transition(int id, String action) async {
    final response = await _client.post(_uri('promos/$id/$action'));
    _expect(response, const {200}, 'promos/$id/$action',
        'Не удалось изменить статус');
    return _decode(response);
  }

  Future<PromoParseResult> parse(String text) async {
    final response = await _client.post(
      _uri('promos/parse'),
      headers: _json,
      body: json.encode({'text': text}),
    );
    _expect(response, const {200}, 'promos/parse', 'Не удалось разобрать');
    return PromoParseResult.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  static PromoModel _decode(http.Response response) => PromoModel.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );

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
      if (payload is Map<String, dynamic> && payload['error'] is String) {
        message = payload['error'] as String;
      }
    } catch (_) {
      // Keep the fallback for non-JSON bodies.
    }
    throw ApiException(endpoint, response.statusCode, message);
  }
}

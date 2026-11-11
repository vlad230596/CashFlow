import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/planned_payment_model.dart';
import 'api_client.dart';

/// HTTP transport for `/api/payments`; state and caching stay in DataProvider.
class PlannedPaymentApi {
  PlannedPaymentApi(this._client, this._uri);

  final http.Client _client;
  final Uri Function(String path) _uri;

  static const _json = {'Content-Type': 'application/json'};

  Future<List<PlannedPaymentModel>> list({String status = 'all'}) async {
    final response = await _client.get(_uri('payments?status=$status'));
    _expect(response, 200, 'payments', 'Не удалось загрузить платежи');
    final payload = json.decode(response.body);
    final items = payload is List
        ? payload
        : (payload as Map<String, dynamic>)['items'] as List? ?? const [];
    return items
        .map((item) =>
            PlannedPaymentModel.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<PlannedPaymentModel> detail(int id) async {
    final response = await _client.get(_uri('payments/$id'));
    _expect(response, 200, 'payments/$id', 'Не удалось загрузить платёж');
    return _decode(response);
  }

  Future<PlannedPaymentModel> create(PlannedPaymentModel payment) async {
    final response = await _client.post(
      _uri('payments'),
      headers: _json,
      body: json.encode(payment.toMutationJson()),
    );
    _expect(response, 201, 'payments', 'Не удалось создать платёж');
    return _decode(response);
  }

  Future<PlannedPaymentModel> update(PlannedPaymentModel payment) async {
    final id = payment.id;
    if (id == null) {
      throw ArgumentError('A saved payment is required for update');
    }
    final response = await _client.put(
      _uri('payments/$id'),
      headers: _json,
      body: json.encode(payment.toMutationJson()),
    );
    _expect(response, 200, 'payments/$id', 'Не удалось сохранить платёж');
    return _decode(response);
  }

  Future<void> delete(int id) async {
    final response = await _client.delete(_uri('payments/$id'));
    _expect(response, 204, 'payments/$id', 'Не удалось удалить платёж');
  }

  Future<PlannedPaymentModel> archive(int id) async {
    final response = await _client.post(_uri('payments/$id/archive'));
    _expect(response, 200, 'payments/$id/archive',
        'Не удалось перенести платёж в архив');
    return _decode(response);
  }

  Future<PlannedPaymentModel> restore(int id, {DateTime? nextDueDate}) async {
    final response = await _client.post(
      _uri('payments/$id/restore'),
      headers: _json,
      body: json.encode({
        if (nextDueDate != null) 'next_due_date': apiDate(nextDueDate),
      }),
    );
    _expect(response, 200, 'payments/$id/restore',
        'Не удалось восстановить платёж');
    return _decode(response);
  }

  Future<PlannedPaymentModel> markPaid(
    int id, {
    required DateTime paidAt,
    double? amount,
    String? currency,
    int? cardId,
    bool clearCard = false,
  }) async {
    final response = await _client.post(
      _uri('payments/$id/records'),
      headers: _json,
      body: json.encode({
        'paid_at': apiDate(paidAt),
        if (amount != null) 'amount': amount.toStringAsFixed(2),
        if (currency != null) 'currency': currency,
        if (cardId != null || clearCard) 'card_id': cardId,
      }),
    );
    _expect(
        response, 201, 'payments/$id/records', 'Не удалось отметить оплату');
    return _decode(response);
  }

  Future<PlannedPaymentModel> undoRecord(int id, int recordId) async {
    final response =
        await _client.delete(_uri('payments/$id/records/$recordId'));
    _expect(
        response, 200, 'payments/$id/records', 'Не удалось отменить оплату');
    return _decode(response);
  }

  static String apiDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static PlannedPaymentModel _decode(http.Response response) =>
      PlannedPaymentModel.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );

  static void _expect(
    http.Response response,
    int status,
    String endpoint,
    String fallback,
  ) {
    if (response.statusCode == status) return;
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

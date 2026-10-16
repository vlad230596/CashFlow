import 'dart:convert';
import 'package:http/http.dart' as http;

class CashbackImportResult {
  const CashbackImportResult({
    required this.created,
    required this.updated,
    required this.importedBanks,
    required this.skippedBanks,
    this.createdPartnerOffers = 0,
    this.updatedPartnerOffers = 0,
  });

  final int created;
  final int updated;
  final int importedBanks;
  final int skippedBanks;
  final int createdPartnerOffers;
  final int updatedPartnerOffers;

  factory CashbackImportResult.fromJson(Map<String, dynamic> json) {
    return CashbackImportResult(
      created: json['created'] as int? ?? 0,
      updated: json['updated'] as int? ?? 0,
      importedBanks: (json['imported_banks'] as List?)?.length ?? 0,
      skippedBanks: (json['skipped'] as List?)?.length ?? 0,
      createdPartnerOffers: json['created_partner_offers'] as int? ?? 0,
      updatedPartnerOffers: json['updated_partner_offers'] as int? ?? 0,
    );
  }
}

enum ImportStage { categories, partnerOffers, refresh }

/// Committed stages are retained so callers can distinguish retry/refresh
/// from an import that never reached the server.
class PartialImportException implements Exception {
  const PartialImportException(this.stage, this.result, this.cause);
  final ImportStage stage;
  final CashbackImportResult result;
  final Object cause;
  @override
  String toString() => stage == ImportStage.refresh
      ? 'Импорт выполнен, но обновить данные не удалось: $cause'
      : 'Категории импортированы, но предложения сохранить не удалось: $cause';
}

class ImportCoordinator {
  const ImportCoordinator({required this.post, required this.refresh});
  final Future<http.Response> Function(String, Map<String, dynamic>) post;
  final Future<bool> Function() refresh;

  Future<Map<String, dynamic>> _post(
      String endpoint, Map<String, dynamic> body) async {
    final response = await post(endpoint, body);
    Map<String, dynamic> payload;
    try {
      payload = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException(
          'Некорректный ответ импорта (HTTP ${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw Exception(
          payload['error'] ?? 'Ошибка импорта: ${response.statusCode}');
    }
    return payload;
  }

  Future<CashbackImportResult> run(String contents, int userId) async {
    final decoded = json.decode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON должен содержать объект импорта');
    }
    final categories = await _post('cashback/import', {
      'document': decoded,
      'user_id': userId,
    });
    var result = CashbackImportResult.fromJson(categories);
    try {
      final partners = await _post('partner-offers/import', {
        'document': decoded,
        'card_user_id': userId,
      });
      result = CashbackImportResult(
        created: result.created,
        updated: result.updated,
        importedBanks: result.importedBanks,
        skippedBanks: result.skippedBanks,
        createdPartnerOffers: partners['created_offers'] as int? ?? 0,
        updatedPartnerOffers: partners['updated_offers'] as int? ?? 0,
      );
    } catch (error) {
      // Best-effort refresh makes the already committed first stage visible.
      try {
        await refresh();
      } catch (_) {}
      throw PartialImportException(ImportStage.partnerOffers, result, error);
    }
    try {
      if (!await refresh()) throw StateError('Обновление недоступно');
    } catch (error) {
      throw PartialImportException(ImportStage.refresh, result, error);
    }
    return result;
  }
}

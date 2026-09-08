import '../models/bank_model.dart';
import '../models/card_model.dart';
import '../models/cashback_category_model.dart';
import '../models/user_model.dart';

String? cashbackBankId(String? bankName) {
  final normalized = (bankName ?? '')
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();

  if (normalized.contains('т банк') || normalized.contains('тинькофф')) {
    return 'tbank';
  }
  if (normalized.contains('яндекс')) return 'yandex';
  if (normalized.contains('альфа') || normalized.contains('alfa')) {
    return 'alfa';
  }
  if (normalized.contains('сбер')) return 'sber';
  if (normalized.contains('ozon') || normalized.contains('озон')) return 'ozon';
  if (normalized == 'втб' || normalized.contains('втб банк')) return 'vtb';
  return null;
}

Map<String, dynamic> buildCashbackSelectionPlan({
  required DateTime now,
  required List<BankModel> banks,
  required List<UserModel> users,
  required List<CardModel> cards,
  required List<CashbackCategoryModel> categories,
  required Iterable<String> requestedBankIds,
  int? userId,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final requested = requestedBankIds.toSet();
  final bankNames = {for (final bank in banks) bank.id: bank.name};
  final userNames = {for (final user in users) user.id: user.name};
  final planBanks = <Map<String, dynamic>>[];

  for (final card in cards) {
    if (userId != null && card.userId != userId) continue;
    final cardId = card.id;
    final bankId = cashbackBankId(bankNames[card.bankId]);
    if (cardId == null || bankId == null || !requested.contains(bankId)) {
      continue;
    }

    final active = categories.where((category) {
      final start = DateTime(
        category.startDate.year,
        category.startDate.month,
        category.startDate.day,
      );
      final end = DateTime(
        category.endDate.year,
        category.endDate.month,
        category.endDate.day,
      );
      return category.cardId == cardId &&
          !today.isBefore(start) &&
          today.isBefore(end) &&
          category.isSelectable;
    }).toList();
    if (active.isEmpty) continue;

    final desired = active.where((category) => category.isSelected).toList()
      ..sort((a, b) => b.cashbackPercent.compareTo(a.cashbackPercent));
    final owner = userNames[card.userId];
    final suffix = card.lastFourDigits?.trim();
    final labelParts = <String>[
      if (owner != null && owner.isNotEmpty) owner,
      bankNames[card.bankId] ?? bankId,
      if (suffix != null && suffix.isNotEmpty) '•• $suffix',
    ];

    planBanks.add({
      'bankId': bankId,
      'cardId': cardId,
      'cardLabel': labelParts.join(' · '),
      'desiredCategories': [
        for (final category in desired)
          {
            'name': category.name,
            'percent': category.cashbackPercent,
          },
      ],
    });
  }

  return {
    'schemaVersion': 1,
    'kind': 'cashback_selection_plan',
    'generatedAt': now.toUtc().toIso8601String(),
    'effectiveDate':
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    'banks': planBanks,
  };
}

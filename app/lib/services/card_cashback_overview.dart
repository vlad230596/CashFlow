import '../models/cashback_category_model.dart';
import '../utils/cashback_period.dart';

/// What one card earns in one month, split by how certain the selection is.
class CardCashbackOverview {
  const CardCashbackOverview({
    required this.active,
    required this.pending,
    required this.available,
  });

  /// Selected and confirmed by the bank: these work at the checkout.
  final List<CashbackCategoryModel> active;

  /// Selected in the plan but not yet seen in a bank snapshot.
  final List<CashbackCategoryModel> pending;

  /// Offered by the bank for the month but not selected.
  final List<CashbackCategoryModel> available;

  bool get isEmpty => active.isEmpty && pending.isEmpty && available.isEmpty;
  bool get hasSelection => active.isNotEmpty || pending.isNotEmpty;
}

CardCashbackOverview cardCashbackOverview(
  Iterable<CashbackCategoryModel> categories,
  int cardId,
  CashbackPeriod period,
) {
  final active = <CashbackCategoryModel>[];
  final pending = <CashbackCategoryModel>[];
  final available = <CashbackCategoryModel>[];
  for (final category in categories) {
    if (category.cardId != cardId || !period.overlaps(category)) continue;
    if (category.isActive) {
      active.add(category);
    } else if (category.isSelected) {
      pending.add(category);
    } else {
      available.add(category);
    }
  }
  for (final list in [active, pending, available]) {
    list.sort(_byPercent);
  }
  return CardCashbackOverview(
    active: active,
    pending: pending,
    available: available,
  );
}

int _byPercent(CashbackCategoryModel a, CashbackCategoryModel b) {
  final percent = b.cashbackPercent.compareTo(a.cashbackPercent);
  return percent == 0 ? a.name.compareTo(b.name) : percent;
}

/// First days of the months, starting with [today]'s, for which the card has
/// categories. The current month is always present so the screen has a tab.
List<DateTime> cardCashbackMonths(
  Iterable<CashbackCategoryModel> categories,
  int cardId,
  DateTime today,
) {
  final current = DateTime(today.year, today.month);
  final months = <DateTime>{current};
  for (final category in categories) {
    if (category.cardId != cardId) continue;
    var month = DateTime(category.startDate.year, category.startDate.month);
    final last = DateTime(category.endDate.year, category.endDate.month);
    // Ends are exclusive midnights; a category ending on the 1st does not
    // reach into that month.
    final endsOnMonthStart = category.endDate.day == 1 &&
        category.endDate.hour == 0 &&
        category.endDate.minute == 0;
    final limit = endsOnMonthStart ? DateTime(last.year, last.month - 1) : last;
    while (!month.isAfter(limit)) {
      if (!month.isBefore(current)) months.add(month);
      month = DateTime(month.year, month.month + 1);
    }
  }
  return months.toList()..sort();
}

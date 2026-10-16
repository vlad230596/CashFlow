import '../models/cashback_category_model.dart';

/// Calendar interval: category ends are exclusive, selected UI ends inclusive.
class CashbackPeriod {
  CashbackPeriod(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        endExclusive = DateTime(end.year, end.month, end.day + 1);

  factory CashbackPeriod.month(DateTime day) => CashbackPeriod(
      DateTime(day.year, day.month), DateTime(day.year, day.month + 1, 0));

  final DateTime start;
  final DateTime endExclusive;

  bool overlaps(CashbackCategoryModel category) {
    final categoryStart = DateTime(category.startDate.year,
        category.startDate.month, category.startDate.day);
    final categoryEnd = DateTime(
        category.endDate.year, category.endDate.month, category.endDate.day);
    return categoryEnd.isAfter(start) && categoryStart.isBefore(endExclusive);
  }
}

/// Pure projection shared by the plan and its proof stage.
Map<int, List<CashbackCategoryModel>> selectedCategoriesByCard(
    Iterable<CashbackCategoryModel> categories, CashbackPeriod period) {
  final result = <int, List<CashbackCategoryModel>>{};
  for (final category in categories) {
    if (category.isSelectable &&
        category.isSelected &&
        period.overlaps(category)) {
      result.putIfAbsent(category.cardId, () => []).add(category);
    }
  }
  return result;
}

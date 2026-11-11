import '../models/cashback_category_model.dart';

/// Calendar interval: category ends are exclusive, selected UI ends inclusive.
///
/// [overlaps] runs for every category on every plan rebuild, so it compares
/// integer calendar-day keys. Constructing a local [DateTime] asks the OS for
/// the time-zone offset, which on Windows costs a system call per instance and
/// made the plan's bank view take seconds per frame.
class CashbackPeriod {
  factory CashbackPeriod(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    return CashbackPeriod._(startDay, endExclusive, calendarDayKey(startDay),
        calendarDayKey(endExclusive));
  }

  CashbackPeriod._(
      this.start, this.endExclusive, this._startKey, this._endExclusiveKey);

  factory CashbackPeriod.month(DateTime day) => CashbackPeriod(
      DateTime(day.year, day.month), DateTime(day.year, day.month + 1, 0));

  final DateTime start;
  final DateTime endExclusive;
  final int _startKey;
  final int _endExclusiveKey;

  bool overlaps(CashbackCategoryModel category) =>
      calendarDayKey(category.endDate) > _startKey &&
      calendarDayKey(category.startDate) < _endExclusiveKey;
}

/// Orders calendar days like the dates themselves: 2026-11-01 → 20261101.
int calendarDayKey(DateTime day) =>
    day.year * 10000 + day.month * 100 + day.day;

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

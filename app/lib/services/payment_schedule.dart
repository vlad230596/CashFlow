import '../models/subscription_model.dart';

/// Anchored due-date math, mirrored from `backend/payment_schedule.py`.
///
/// Every occurrence is computed from the anchor, never from the previous
/// occurrence, so month-end anchors do not drift: 31 Jan -> 28 Feb -> 31 Mar.
/// All values are civil dates (time of day is ignored).
class PaymentSchedule {
  const PaymentSchedule({required this.anchor, required this.interval});

  final DateTime anchor;
  final BillingInterval interval;

  DateTime occurrence(int index) {
    if (index < 0) throw RangeError.value(index, 'index');
    final base = dateOnly(anchor);
    final count = interval.count;
    return switch (interval.unit) {
      BillingIntervalUnit.days =>
        DateTime(base.year, base.month, base.day + count * index),
      BillingIntervalUnit.weeks =>
        DateTime(base.year, base.month, base.day + 7 * count * index),
      BillingIntervalUnit.months => addMonthsClamped(base, count * index),
      BillingIntervalUnit.years => addMonthsClamped(base, 12 * count * index),
    };
  }

  /// Smallest occurrence strictly later than [after].
  DateTime nextAfter(DateTime after) {
    final base = dateOnly(anchor);
    final limit = dateOnly(after);
    if (limit.isBefore(base)) return base;
    var index = _indexNotAfter(base, limit);
    var candidate = occurrence(index);
    while (!candidate.isAfter(limit)) {
      index++;
      candidate = occurrence(index);
    }
    return candidate;
  }

  bool isOccurrence(DateTime value) {
    final day = dateOnly(value);
    if (day.isBefore(dateOnly(anchor))) return false;
    return nextAfter(DateTime(day.year, day.month, day.day - 1)) == day;
  }

  /// Occurrences within [start]..[end] inclusive, at most [limit] items.
  List<DateTime> between(DateTime start, DateTime end, {int limit = 1000}) {
    final last = dateOnly(end);
    final result = <DateTime>[];
    final first = dateOnly(start);
    var current = nextAfter(DateTime(first.year, first.month, first.day - 1));
    while (!current.isAfter(last) && result.length < limit) {
      result.add(current);
      current = nextAfter(current);
    }
    return result;
  }

  int _indexNotAfter(DateTime base, DateTime value) {
    switch (interval.unit) {
      case BillingIntervalUnit.days:
      case BillingIntervalUnit.weeks:
        final step = interval.count *
            (interval.unit == BillingIntervalUnit.weeks ? 7 : 1);
        return _civilDayDifference(base, value) ~/ step;
      case BillingIntervalUnit.months:
      case BillingIntervalUnit.years:
        final stepMonths = interval.count *
            (interval.unit == BillingIntervalUnit.years ? 12 : 1);
        final monthsBetween =
            (value.year - base.year) * 12 + value.month - base.month;
        final index = monthsBetween ~/ stepMonths - 1;
        return index < 0 ? 0 : index;
    }
  }
}

bool isLastDayOfMonth(DateTime value) =>
    DateTime(value.year, value.month, value.day + 1).month != value.month;

/// An anchor on the 31st whose schedule hits [due], so a monthly payment
/// stays on the last day of every month ("до конца месяца"). Returns [due]
/// itself when it already falls on the 31st, and null when no such anchor
/// exists (non-monthly interval or [due] is not a month end).
DateTime? monthEndAnchor(DateTime due, BillingInterval interval) {
  final day = dateOnly(due);
  if (!isLastDayOfMonth(day)) return null;
  if (interval.unit != BillingIntervalUnit.months &&
      interval.unit != BillingIntervalUnit.years) {
    return null;
  }
  if (day.day == 31) return day;
  final stepMonths =
      interval.count * (interval.unit == BillingIntervalUnit.years ? 12 : 1);
  for (var steps = 1; steps <= 12; steps++) {
    final monthStart = DateTime(day.year, day.month - steps * stepMonths);
    final candidate = DateTime(monthStart.year, monthStart.month, 31);
    if (candidate.month != monthStart.month) continue;
    if (PaymentSchedule(anchor: candidate, interval: interval)
        .isOccurrence(day)) {
      return candidate;
    }
  }
  return null;
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime addMonthsClamped(DateTime anchor, int months) {
  final monthStart = DateTime(anchor.year, anchor.month + months);
  final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  return DateTime(
    monthStart.year,
    monthStart.month,
    anchor.day > lastDay ? lastDay : anchor.day,
  );
}

/// Whole civil days from [from] to [to], immune to DST shifts.
int civilDayDifference(DateTime from, DateTime to) =>
    _civilDayDifference(dateOnly(from), dateOnly(to));

int _civilDayDifference(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

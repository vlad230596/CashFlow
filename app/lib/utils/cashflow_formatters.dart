String calendarDateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

String mccCacheLabel(DateTime? updatedAt, DateTime? asOf) {
  final updated = updatedAt == null
      ? ''
      : ' · обновлено ${moscowTimestampLabel(updatedAt)}';
  final period = asOf == null
      ? ''
      : ' · правила на ${calendarDateLabel(asOf.toUtc().add(const Duration(hours: 3)))}';
  return 'Сохранённые данные$updated$period';
}

String moscowTimestampLabel(DateTime timestamp) {
  final moscow = timestamp.toUtc().add(const Duration(hours: 3));
  return '${calendarDateLabel(moscow)} '
      '${moscow.hour.toString().padLeft(2, '0')}:'
      '${moscow.minute.toString().padLeft(2, '0')} МСК';
}

/// Shared primitives; callers choose precision, decimal separator and suffix.
class CashFlowFormatters {
  static String calendarDate(DateTime date) => calendarDateLabel(date);
  static String time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
  static String month(DateTime date) =>
      '${_months[date.month - 1]} ${date.year}';
  static String percent(double value,
      {bool suffix = true, int? decimalPlaces = 1, bool decimalComma = true}) {
    var amount = value == value.roundToDouble()
        ? value.toInt().toString()
        : decimalPlaces == null
            ? '$value'
            : value.toStringAsFixed(decimalPlaces);
    if (decimalComma) amount = amount.replaceAll('.', ',');
    return suffix ? '$amount%' : amount;
  }

  static String localSnapshot(DateTime date) {
    final local = date.toLocal();
    return '${calendarDate(local)}, ${time(local)}';
  }

  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь'
  ];
}

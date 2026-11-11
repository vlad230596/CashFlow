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

/// «обновлено 12 мин назад», «обновлено вчера в 18:40» in device-local time.
String freshnessLabel(DateTime fetchedAt, DateTime now) {
  final local = fetchedAt.toLocal();
  final current = now.toLocal();
  final age = current.difference(local);
  if (age < const Duration(minutes: 1)) return 'обновлено только что';
  if (age < const Duration(hours: 1)) {
    return 'обновлено ${age.inMinutes} мин назад';
  }
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(current.year, current.month, current.day);
  final time = CashFlowFormatters.time(local);
  final days = today.difference(day).inDays;
  if (days == 0) return 'обновлено сегодня в $time';
  if (days == 1) return 'обновлено вчера в $time';
  final date = local.year == current.year
      ? '${local.day.toString().padLeft(2, '0')}.'
          '${local.month.toString().padLeft(2, '0')}'
      : calendarDateLabel(local);
  return 'обновлено $date в $time';
}

/// «15 234,50 ₽»; whole amounts drop the kopecks («80 000 ₽»).
String moneyLabel(double amount, String? currency) {
  final negative = amount < 0;
  final cents = (amount.abs() * 100).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(' ');
    grouped.write(digits[index]);
  }
  final number = fraction == 0
      ? grouped.toString()
      : '$grouped,${fraction.toString().padLeft(2, '0')}';
  final symbol = switch (currency?.toUpperCase()) {
    null || '' || 'RUB' => '₽',
    'USD' => r'$',
    'EUR' => '€',
    final String code => code,
  };
  return '${negative ? '−' : ''}$number $symbol';
}

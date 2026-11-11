import '../models/promo_model.dart';

/// Minimal on-device parsing used when `/api/promos/parse` is unreachable.
///
/// It recognizes only the expiry date after deadline wording and a promo
/// code after «промокод»/«по коду»; the backend parser
/// (`backend/promo_parser.py`) remains the full implementation.
PromoParseResult parsePromoTextOffline(String text, DateTime today) {
  final low = text.toLowerCase().replaceAll('ё', 'е');
  final expiry = _expiry(low, today);
  return PromoParseResult(
    promoCode: _code(text),
    expiresAt: expiry?.$1,
    expiryPhrase: expiry?.$2,
    offline: true,
  );
}

const _months = {
  'янв': 1,
  'фев': 2,
  'мар': 3,
  'апр': 4,
  'мая': 5,
  'июн': 6,
  'июл': 7,
  'авг': 8,
  'сен': 9,
  'окт': 10,
  'ноя': 11,
  'дек': 12,
};

const _deadline = r'(?<![а-яё])(?:до|по|сгора[а-яё]*|сгорят|сгорит|истекает|заканчивается)\s+';

final _numeric = RegExp(
  _deadline + r'(\d{1,2})[./](\d{1,2})(?:[./](\d{4}|\d{2}))?(?![\d])',
);
final _named = RegExp(
  _deadline + r'(\d{1,2})(?:-?го)?\s+([а-я]{3,8})\.?(?:\s+(\d{4}))?',
);
final _iso = RegExp(_deadline + r'(\d{4})-(\d{2})-(\d{2})');

(DateTime, String)? _expiry(String low, DateTime today) {
  final found = <(DateTime, int, String)>[];
  void add(RegExpMatch match, int day, int month, String? year) {
    final value = _resolve(day, month, year, today);
    if (value != null) found.add((value, match.start, match[0]!.trim()));
  }

  for (final match in _numeric.allMatches(low)) {
    add(match, int.parse(match[1]!), int.parse(match[2]!), match[3]);
  }
  for (final match in _named.allMatches(low)) {
    final word = match[2]!;
    final month = word.length >= 3 ? _months[word.substring(0, 3)] : null;
    if (month != null) add(match, int.parse(match[1]!), month, match[3]);
  }
  for (final match in _iso.allMatches(low)) {
    add(match, int.parse(match[3]!), int.parse(match[2]!), match[1]);
  }
  if (found.isEmpty) return null;
  // Several deadlines: remind about the earliest one.
  found.sort((left, right) => left.$1.compareTo(right.$1));
  return (found.first.$1, found.first.$3);
}

/// A year-less date already in the past means next year.
DateTime? _resolve(int day, int month, String? year, DateTime today) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  DateTime? build(int value) {
    final date = DateTime(value, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  if (year != null) {
    final parsed = int.parse(year);
    return build(parsed < 100 ? 2000 + parsed : parsed);
  }
  final current = build(today.year);
  if (current != null && !current.isBefore(today)) return current;
  return build(today.year + 1);
}

final _codeAfterKeyword = RegExp(
  r'(?:промо[\s-]?код[а-яё]*|купон[а-яё]*|по\s+коду)[\s:—–\-]*[«"“]?'
  r'([A-Za-zА-ЯЁа-яё0-9][A-Za-zА-ЯЁа-яё0-9_\-]{2,39})',
  caseSensitive: false,
);

String? _code(String text) {
  for (final match in _codeAfterKeyword.allMatches(text)) {
    final token = match[1]!;
    final hasDigit = token.contains(RegExp(r'\d'));
    final hasLetter = token.contains(RegExp(r'[A-Za-zА-ЯЁа-яё]'));
    if (token == token.toUpperCase() || (hasDigit && hasLetter)) return token;
  }
  return null;
}

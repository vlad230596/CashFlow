import 'package:cashflow/services/promo_text_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 11);

  test('finds deadline dates with year rollover', () {
    DateTime? expiry(String text) =>
        parsePromoTextOffline(text, today).expiresAt;

    expect(expiry('Скидка по промокоду AUTUMN20 до 13.11'),
        DateTime(2026, 11, 13));
    expect(expiry('Действует до 10 ноября'), DateTime(2027, 11, 10));
    expect(expiry('Действует до 11 ноября'), DateTime(2026, 11, 11));
    expect(expiry('Баллы сгорят 15 декабря'), DateTime(2026, 12, 15));
    expect(expiry('Акция по 05.01.27'), DateTime(2027, 1, 5));
    expect(expiry('Срок действия до 2026-12-31'), DateTime(2026, 12, 31));
    expect(expiry('Скидка до 25.11, баллы сгорят 15.12'),
        DateTime(2026, 11, 25));
    expect(expiry('Новая коллекция 20.11'), isNull);
    expect(expiry('Подойдёт 13.11'), isNull);
  });

  test('finds promo codes after keywords only', () {
    String? code(String text) => parsePromoTextOffline(text, today).promoCode;

    expect(code('Введите промокод: SPRING25'), 'SPRING25');
    expect(code('по промокоду «ЛЕТО2026» скидка'), 'ЛЕТО2026');
    expect(code('Скидка по коду sale15'), 'sale15');
    expect(code('Промокод действует при заказе'), isNull);
    expect(code('Код подтверждения 4821'), isNull);
  });

  test('marks the result as offline and keeps the phrase', () {
    final result = parsePromoTextOffline('Действует до 30 ноября', today);
    expect(result.offline, isTrue);
    expect(result.expiryPhrase, 'до 30 ноября');
  });
}

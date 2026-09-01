import 'package:cashflow/screens/monthly_cashback_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCashbackCategoryLine', () {
    test('parses Russian category names after percent without stripping them',
        () {
      final cases = {
        '8 Тбанк.Топливо': ('Тбанк.Топливо', 8.0),
        '10 Тбанк.Супермаркеты': ('Тбанк.Супермаркеты', 10.0),
        '5 Аптеки': ('Аптеки', 5.0),
        '5 Развлечения': ('Развлечения', 5.0),
      };

      for (final entry in cases.entries) {
        final parsed = parseCashbackCategoryLine(entry.key);

        expect(parsed.categoryName, entry.value.$1);
        expect(parsed.percent, entry.value.$2);
      }
    });

    test('parses percent before or after category name', () {
      expect(parseCashbackCategoryLine('5% Кафе').categoryName, 'Кафе');

      final parsed = parseCashbackCategoryLine('Рестораны 10%');

      expect(parsed.categoryName, 'Рестораны');
      expect(parsed.percent, 10);
    });
  });

  group('normalizedCashbackCategoryName', () {
    test('groups common bank aliases into one user need', () {
      expect(
        normalizedCashbackCategoryName('Спорт и фитнес'),
        'Спорт и активный отдых',
      );
      expect(
        normalizedCashbackCategoryName('Активный отдых'),
        'Спорт и активный отдых',
      );
      expect(normalizedCashbackCategoryName('Лекарства'), 'Аптеки');
      expect(
        normalizedCashbackCategoryName('Такси и каршеринг'),
        'Такси и каршеринг',
      );
    });

    test('keeps an unknown category readable', () {
      expect(
        normalizedCashbackCategoryName('Цветы и подарки'),
        'Цветы и подарки',
      );
    });
  });

  test('sorts everyday needs before entertainment and niche shops', () {
    final categories = [
      'Магазин Ромашка',
      'Кино',
      'Аптеки',
      'Одежда',
      'Супермаркеты',
    ]..sort(
        (a, b) => cashbackCategorySortPriority(a).compareTo(
          cashbackCategorySortPriority(b),
        ),
      );

    expect(categories, [
      'Супермаркеты',
      'Одежда',
      'Аптеки',
      'Кино',
      'Магазин Ромашка',
    ]);
  });
}

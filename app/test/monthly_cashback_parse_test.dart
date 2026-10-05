import 'package:cashflow/models/canonical_category_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
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
      expect(
          normalizedCashbackCategoryName('Онлайн-образование'), 'Образование');
      expect(normalizedCashbackCategoryName('Книги и обучение'), 'Образование');
      expect(
          normalizedCashbackCategoryName('Салоны красоты'), 'Красота и уход');
      expect(normalizedCashbackCategoryName('Косметика и парфюмерия'),
          'Красота и уход');
      expect(
          normalizedCashbackCategoryName('Товары для детей'), 'Детские товары');
      expect(normalizedCashbackCategoryName('Игрушки'), 'Детские товары');
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
      'Образование',
      'Одежда',
      'Детские товары',
      'Супермаркеты',
    ]..sort(
        (a, b) => cashbackCategorySortPriority(a).compareTo(
          cashbackCategorySortPriority(b),
        ),
      );

    expect(categories, [
      'Супермаркеты',
      'Одежда',
      'Детские товары',
      'Аптеки',
      'Образование',
      'Кино',
      'Магазин Ромашка',
    ]);
  });

  group('CashbackNeedCatalog', () {
    const catalogue = [
      CanonicalCategoryModel(
        key: 'restaurants',
        title: 'Кафе, рестораны и бары',
        groupKey: 'food',
        groupTitle: 'Еда',
        aliases: ['кафе', 'бары'],
        defaultPriority: 20,
      ),
      CanonicalCategoryModel(
        key: 'fastfood',
        title: 'Фастфуд',
        groupKey: 'food',
        groupTitle: 'Еда',
        aliases: ['быстрое питание'],
        defaultPriority: 25,
      ),
    ];
    CashbackCategoryModel offer(String name, [List<String> keys = const []]) =>
        CashbackCategoryModel(
          id: 1,
          name: name,
          startDate: DateTime(2026, 10),
          endDate: DateTime(2026, 11),
          isSelected: false,
          cashbackPercent: 5,
          cardId: 1,
          canonicalKeys: keys,
        );

    test('a broad offer covers every linked canonical category', () {
      final needs = CashbackNeedCatalog(catalogue);
      expect(
        needs.titlesFor(offer('Кафе и рестораны', ['restaurants', 'fastfood'])),
        ['Кафе, рестораны и бары', 'Фастфуд'],
      );
      expect(needs.priority('Фастфуд'), 25);
      expect(needs.aliases('Кафе, рестораны и бары'), contains('бары'));
    });

    test('offers without links keep the name-based grouping', () {
      final needs = CashbackNeedCatalog(catalogue);
      expect(needs.titlesFor(offer('Лекарства')), ['Аптеки']);
      expect(needs.titlesFor(offer('Магазин Ромашка')), ['Магазин ромашка']);
      expect(needs.priority('Аптеки'), cashbackCategorySortPriority('Аптеки'));
      // Unknown keys (an older cached catalogue) fall back the same way.
      expect(needs.titlesFor(offer('Лекарства', ['pharmacy'])), ['Аптеки']);
    });
  });
}

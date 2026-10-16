import 'package:cashflow/models/canonical_category_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/utils/cashback_needs.dart';
import 'package:flutter_test/flutter_test.dart';

CashbackCategoryModel offer(String name, {List<String> keys = const []}) =>
    CashbackCategoryModel(
        id: 1,
        name: name,
        startDate: DateTime(2026, 10),
        endDate: DateTime(2026, 11),
        isSelected: true,
        cashbackPercent: 5,
        cardId: 1,
        canonicalKeys: keys);

void main() {
  const category = CanonicalCategoryModel(
      key: 'groceries',
      title: 'Продукты',
      groupKey: 'everyday',
      groupTitle: 'Ежедневные покупки',
      aliases: [],
      defaultPriority: 10);
  test('server canonical link wins and preserves bank title', () {
    final result = CashbackNeedCatalog([category])
        .resolve(offer('Любое название', keys: ['groceries']));
    expect(result.method, CategoryResolutionMethod.canonical);
    expect(result.originalName, 'Любое название');
    expect(result.needs.single.key, 'canonical:groceries');
    expect(result.needs.single.title, 'Продукты');
  });
  test('fallback synonyms share a stable approximate key', () {
    final catalog = CashbackNeedCatalog([]);
    final first = catalog.resolve(offer('Такси'));
    final second = catalog.resolve(offer('Каршеринг'));
    expect(first.isApproximate, isTrue);
    expect(first.needs.single.key, 'approximate:taxi_carsharing');
    expect(first.needs.single.key, second.needs.single.key);
  });
  test('canonical identities survive display title changes', () {
    final before = CashbackNeedCatalog([category]);
    final after = CashbackNeedCatalog([
      const CanonicalCategoryModel(
          key: 'groceries',
          title: 'Супермаркеты',
          groupKey: 'everyday',
          groupTitle: 'Ежедневные покупки',
          aliases: [],
          defaultPriority: 10)
    ]);
    expect(before.keysFor(offer('Банк', keys: ['groceries'])),
        after.keysFor(offer('Банк', keys: ['groceries'])));
  });
}

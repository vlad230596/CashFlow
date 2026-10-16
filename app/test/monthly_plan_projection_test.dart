import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/services/monthly_plan_projection.dart';
import 'package:cashflow/utils/cashback_needs.dart';
import 'package:flutter_test/flutter_test.dart';

CashbackCategoryModel offer(
        int id, String name, double percent, bool selected) =>
    CashbackCategoryModel(
        id: id,
        name: name,
        startDate: DateTime(2026, 10),
        endDate: DateTime(2026, 11),
        isSelected: selected,
        cashbackPercent: percent,
        cardId: id);

void main() {
  test('projection computes coverage, duplicates and pure sorted groups', () {
    final source = [
      offer(1, 'Аптеки', 5, false),
      offer(2, 'Лекарства', 3, true),
      offer(3, 'Аптеки', 7, true),
      offer(4, 'Такси', 10, false)
    ];
    final projection = MonthlyPlanProjection(
        categories: source, catalog: CashbackNeedCatalog([]));
    expect(projection.needKeys, hasLength(2));
    expect(projection.coveredNeedKeys, hasLength(1));
    expect(projection.duplicateCount, 1);
    final groups = projection.groups();
    expect(groups.first.selectedCount, 2);
    expect(groups.first.bestPercent, 7);
    expect(groups.first.offers.map((offer) => offer.id), [3, 2, 1]);
    expect(source.map((offer) => offer.id), [1, 2, 3, 4]);
    expect(
        projection.groups(filter: MonthlyPlanFilter.duplicates), hasLength(1));
    expect(projection.groups(filter: MonthlyPlanFilter.uncovered).single.title,
        'Такси и каршеринг');
  });
  test(
      'projection searches original names without changing approximate grouping',
      () {
    final projection = MonthlyPlanProjection(
        categories: [offer(1, 'Лекарства онлайн', 5, false)],
        catalog: CashbackNeedCatalog([]));
    expect(projection.groups(query: 'онлайн').single.title, 'Аптеки');
    expect(projection.groups(query: 'неизвестно'), isEmpty);
  });
}

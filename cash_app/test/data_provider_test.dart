import 'package:cash_app/models/cashback_category_model.dart';
import 'package:cash_app/providers/data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('filters effective active cashback categories by selected date', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider()
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Current',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 2,
          name: 'Expired',
          startDate: DateTime(2026, 3),
          endDate: DateTime(2026, 4),
          isSelected: true,
          cashbackPercent: 10,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 3,
          name: 'Not selected',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: false,
          cashbackPercent: 15,
          cardId: 1,
        ),
      ];

    await provider.setCashbackEffectiveDate(DateTime(2026, 4, 25));

    expect(
      provider.effectiveActiveCashbackCategories.map((category) => category.name),
      ['Current'],
    );
  });

  test('uses active cashback cache when full cashback cache is empty', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = DataProvider()
      ..activeCashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Cached',
          startDate: DateTime(2026, 4),
          endDate: DateTime(2026, 5),
          isSelected: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
      ];

    await provider.setCashbackEffectiveDate(DateTime(2026, 4, 25));

    expect(provider.effectiveActiveCashbackCategories.single.name, 'Cached');
  });
}

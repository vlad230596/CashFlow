import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the production server as the default API URL', () {
    expect(
      DataProvider.defaultApiBaseUrl,
      'https://cash-flow-app.duckdns.org:8443',
    );
  });

  test('cashback category preserves description and stackable type', () {
    final category = CashbackCategoryModel.fromJson({
      'id': 7,
      'name': 'Аптеки в августе',
      'start_date': '2026-08-01T00:00:00',
      'end_date': '2026-09-01T00:00:00',
      'is_selected': true,
      'cashback_percent': 3,
      'card_id': 3,
      'description': 'Дополнительно к обычному кэшбэку',
      'category_type': 'stackable_bonus',
      'is_selection_locked': true,
      'max_cashback_amount': 2000,
      'min_purchase_amount': 5000,
    });

    expect(category.description, 'Дополнительно к обычному кэшбэку');
    expect(category.isStackableBonus, isTrue);
    expect(category.isSelectionLocked, isTrue);
    expect(category.maxCashbackAmount, 2000);
    expect(category.minPurchaseAmount, 5000);
    expect(
      CashbackCategoryModel.toJson(category)['category_type'],
      'stackable_bonus',
    );
    expect(
      CashbackCategoryModel.toJson(category)['is_selection_locked'],
      isTrue,
    );
    expect(
      CashbackCategoryModel.toJson(category)['max_cashback_amount'],
      2000,
    );
    expect(
      CashbackCategoryModel.toJson(category)['min_purchase_amount'],
      5000,
    );
  });

  test('task bonus category is not selectable', () {
    final category = CashbackCategoryModel.fromJson({
      'id': 8,
      'name': 'Награда за задание',
      'start_date': '2026-09-01T00:00:00',
      'end_date': '2026-10-01T00:00:00',
      'is_selected': false,
      'cashback_percent': 5,
      'card_id': 3,
      'category_type': 'task_bonus',
    });

    expect(category.isTaskBonus, isTrue);
    expect(category.isSelectable, isFalse);
    expect(
        CashbackCategoryModel.toJson(category)['category_type'], 'task_bonus');
  });

  test('filters effective active cashback categories by selected date',
      () async {
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
      provider.effectiveActiveCashbackCategories
          .map((category) => category.name),
      ['Current'],
    );
  });

  test('uses active cashback cache when full cashback cache is empty',
      () async {
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

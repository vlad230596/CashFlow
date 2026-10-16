import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/services/cashback_selection_plan.dart';
import 'package:cashflow/utils/cashback_period.dart';
import 'package:flutter_test/flutter_test.dart';

CashbackCategoryModel offer(int id, DateTime start, DateTime end) =>
    CashbackCategoryModel(
        id: id,
        name: 'Category $id',
        startDate: start,
        endDate: end,
        isSelected: true,
        cashbackPercent: 5,
        cardId: 1);

void main() {
  final categories = [
    offer(1, DateTime(2026, 9), DateTime(2026, 10)),
    offer(2, DateTime(2026, 10), DateTime(2026, 11)),
    offer(3, DateTime(2026, 11), DateTime(2026, 12)),
  ];
  test('projection excludes adjacent month history and future', () {
    final period = CashbackPeriod.month(DateTime(2026, 10));
    expect(
        selectedCategoriesByCard(categories, period)[1]!.map((c) => c.id), [2]);
    expect(
        period.overlaps(offer(4, DateTime(2026, 10, 31), DateTime(2026, 11))),
        isTrue);
    expect(period.overlaps(offer(5, DateTime(2026, 9), DateTime(2026, 10))),
        isFalse);
  });
  test('export follows selected month rather than generation day', () {
    final plan = buildCashbackSelectionPlan(
        now: DateTime(2026, 9, 8),
        period: CashbackPeriod.month(DateTime(2026, 10)),
        banks: [BankModel(id: 1, name: 'Сбер')],
        users: [],
        cards: [CardModel(id: 1, bankId: 1)],
        categories: categories,
        requestedBankIds: ['sber']);
    expect(plan['effectiveDate'], '2026-10-01');
    expect(plan['period'], {'from': '2026-10-01', 'to': '2026-10-31'});
    expect((plan['banks'] as List).single['desiredCategories'], [
      {'name': 'Category 2', 'percent': 5.0}
    ]);
  });
  test('stable bank key survives user name and icon changes', () {
    final plan = buildCashbackSelectionPlan(
        now: DateTime(2026, 10, 8),
        banks: [
          BankModel(
              id: 1, name: 'Семейный банк', iconKey: 'generic', bankKey: 'sber')
        ],
        users: [],
        cards: [CardModel(id: 1, bankId: 1)],
        categories: categories,
        requestedBankIds: ['sber']);
    expect((plan['banks'] as List).single['bankId'], 'sber');
  });
}

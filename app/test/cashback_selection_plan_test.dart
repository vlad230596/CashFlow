import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/services/cashback_selection_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps supported bank names', () {
    expect(cashbackBankId('Т-Банк'), 'tbank');
    expect(cashbackBankId('Альфа-Банк'), 'alfa');
    expect(cashbackBankId('Ozon Банк'), 'ozon');
    expect(cashbackBankId('Неизвестный банк'), isNull);
  });

  test('builds a plan only from selectable categories active today', () {
    final plan = buildCashbackSelectionPlan(
      now: DateTime(2026, 9, 8, 14, 30),
      banks: [BankModel(id: 1, name: 'СберБанк', description: '')],
      users: [UserModel(id: 7, name: 'Анна')],
      cards: [
        CardModel(
          id: 11,
          bankId: 1,
          userId: 7,
          lastFourDigits: '1234',
        ),
        CardModel(id: 12, bankId: 1, userId: 8, lastFourDigits: '5678'),
      ],
      categories: [
        CashbackCategoryModel(
          id: 1,
          name: 'Аптеки',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 10, 1),
          isSelected: true,
          cashbackPercent: 5,
          cardId: 11,
        ),
        CashbackCategoryModel(
          id: 2,
          name: 'Такси',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 11, 1),
          isSelected: true,
          cashbackPercent: 10,
          cardId: 11,
        ),
        CashbackCategoryModel(
          id: 3,
          name: 'Бонус',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 10, 1),
          isSelected: true,
          cashbackPercent: 3,
          cardId: 11,
          categoryType: 'stackable_bonus',
        ),
        CashbackCategoryModel(
          id: 4,
          name: 'Кафе',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 10, 1),
          isSelected: true,
          cashbackPercent: 8,
          cardId: 12,
        ),
      ],
      requestedBankIds: const ['sber'],
      userId: 7,
    );

    expect(plan['effectiveDate'], '2026-09-08');
    final banks = plan['banks'] as List<dynamic>;
    expect(banks, hasLength(1));
    expect(banks.single['bankId'], 'sber');
    expect(banks.single['cardLabel'], 'Анна · СберБанк · •• 1234');
    expect(banks.single['desiredCategories'], [
      {'name': 'Аптеки', 'percent': 5.0},
    ]);
  });

  test('keeps an empty desired list so Chrome can show removals', () {
    final plan = buildCashbackSelectionPlan(
      now: DateTime(2026, 9, 8),
      banks: [BankModel(id: 1, name: 'ВТБ', description: '')],
      users: const [],
      cards: [CardModel(id: 2, bankId: 1)],
      categories: [
        CashbackCategoryModel(
          id: 4,
          name: 'Кафе',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 10, 1),
          isSelected: false,
          cashbackPercent: 7,
          cardId: 2,
        ),
      ],
      requestedBankIds: const ['vtb'],
    );

    final banks = plan['banks'] as List<dynamic>;
    expect(banks.single['desiredCategories'], isEmpty);
  });
}

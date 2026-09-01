import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/monthly_cashback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile view compares the same need across banks',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final month = DateTime(now.year, now.day <= 20 ? now.month : now.month + 1);
    final provider = DataProvider();
    provider
      ..banks = [
        BankModel(id: 1, name: 'Первый банк', description: ''),
        BankModel(id: 2, name: 'Второй банк', description: ''),
      ]
      ..users = [UserModel(id: 1, name: 'Анна')]
      ..cards = [
        CardModel(
          id: 1,
          bankId: 1,
          userId: 1,
          lastFourDigits: '1111',
          maxCashbackCategories: 3,
        ),
        CardModel(
          id: 2,
          bankId: 2,
          userId: 1,
          lastFourDigits: '2222',
          maxCashbackCategories: 3,
        ),
      ]
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Аптеки',
          startDate: month,
          endDate: DateTime(month.year, month.month + 1),
          isSelected: true,
          cashbackPercent: 3,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 2,
          name: 'Лекарства',
          startDate: month,
          endDate: DateTime(month.year, month.month + 1),
          isSelected: false,
          cashbackPercent: 5,
          cardId: 2,
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MonthlyCashbackScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('По категориям'), findsOneWidget);
    expect(find.text('Аптеки'), findsWidgets);
    expect(find.text('Лекарства'), findsOneWidget);
    expect(find.text('Есть 5%'), findsOneWidget);
    expect(find.text('Лучший процент'), findsOneWidget);
    expect(find.textContaining('Покрыто 1 из 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('По банкам'));
    await tester.pumpAndSettle();

    expect(find.text('Добавить категории'), findsWidgets);
    expect(find.textContaining('1/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

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
  testWidgets('mobile plan follows the manual needs-first layout',
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
          isSelected: false,
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

    expect(find.text('План'), findsOneWidget);
    expect(find.text('Обязательные потребности'), findsOneWidget);
    expect(find.text('Обязательные'), findsOneWidget);
    expect(find.text('Частые'), findsOneWidget);
    expect(find.text('Остальные'), findsOneWidget);
    expect(find.text('Аптеки'), findsOneWidget);
    expect(find.text('Ещё не назначено'), findsOneWidget);
    expect(find.textContaining('Первый банк'), findsWidgets);
    expect(find.textContaining('Второй банк'), findsWidgets);
    expect(find.text('Добавить потребность'), findsOneWidget);
    expect(find.text('0 из 1'), findsOneWidget);

    await tester.tap(find.textContaining('Второй банк').first);
    await tester.pumpAndSettle();

    expect(find.text('Выберите карту'), findsOneWidget);
    expect(find.text('Назад'), findsOneWidget);
    expect(find.text('Назначить Второй банк'), findsOneWidget);
    expect(find.text('Оставить без карты'), findsOneWidget);

    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();

    expect(find.text('Обязательные потребности'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile plan opens the grouped manual review', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final month = DateTime(now.year, now.day <= 20 ? now.month : now.month + 1);
    final provider = DataProvider()
      ..banks = [BankModel(id: 1, name: 'Первый банк', description: '')]
      ..users = [UserModel(id: 1, name: 'Анна')]
      ..cards = [
        CardModel(
          id: 1,
          bankId: 1,
          userId: 1,
          lastFourDigits: '1111',
          maxCashbackCategories: 3,
        ),
      ]
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Продукты и супермаркеты',
          startDate: month,
          endDate: DateTime(month.year, month.month + 1),
          isSelected: true,
          isBankConfirmed: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
        CashbackCategoryModel(
          id: 2,
          name: 'Такси',
          startDate: month,
          endDate: DateTime(month.year, month.month + 1),
          isSelected: false,
          cashbackPercent: 3,
          cardId: 1,
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MonthlyCashbackScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Проверить план'));
    await tester.pumpAndSettle();

    expect(find.text('План заполнен вручную'), findsOneWidget);
    expect(find.text('Первый банк · 1111'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
    expect(find.textContaining('Не закрыто: Такси'), findsOneWidget);
    expect(find.text('Перейти к подтверждению'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

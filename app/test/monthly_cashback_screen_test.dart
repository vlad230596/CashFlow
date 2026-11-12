import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/canonical_category_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/monthly_cashback_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/mcc_test_cache.dart';

void main() {
  testWidgets('Windows plan toolbar with import actions fits a 1000 px window',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final width in [800.0, 1017.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = DataProvider(mccCacheStore: isolatedMccCache())
        ..banks = [BankModel(id: 1, name: 'Банк', description: '')]
        ..users = [UserModel(id: 1, name: 'Анна')]
        ..cards = [CardModel(id: 1, bankId: 1, userId: 1)];
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: MonthlyCashbackScreen())),
      ));
      await tester.pump();
      expect(find.text('Импортировать JSON'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a card header in «По банкам» opens its categories this month',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final start = DateTime(DateTime.now().year, DateTime.now().month);
    final provider = DataProvider(mccCacheStore: isolatedMccCache())
      ..banks = [BankModel(id: 1, name: 'Банк', description: '')]
      ..users = [UserModel(id: 1, name: 'Анна')]
      ..cards = [CardModel(id: 1, bankId: 1, userId: 1, lastFourDigits: '4321')]
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Аптеки',
          startDate: start,
          endDate: DateTime(start.year, start.month + 1),
          isSelected: true,
          isBankConfirmed: true,
          cashbackPercent: 5,
          cardId: 1,
        ),
      ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: MonthlyCashbackScreen())),
    ));
    await tester.pump();
    await tester.tap(find.text('По банкам'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('plan-bank-card-1')));
    await tester.pumpAndSettle();
    expect(find.text('Карта •4321'), findsOneWidget);
    expect(find.text('Действует · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile plan follows the manual needs-first layout',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final month = DateTime(now.year, now.day <= 20 ? now.month : now.month + 1);
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
    );
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
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
    )
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

  testWidgets('a broad bank offer covers every canonical need it includes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final month = DateTime(now.year, now.day <= 20 ? now.month : now.month + 1);
    final provider = DataProvider(
      mccCacheStore: isolatedMccCache(),
    )
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
      ..canonicalCategories = const [
        CanonicalCategoryModel(
          key: 'restaurants',
          title: 'Кафе, рестораны и бары',
          groupKey: 'food',
          groupTitle: 'Еда',
          aliases: ['кафе'],
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
      ]
      ..cashbackCategories = [
        CashbackCategoryModel(
          id: 1,
          name: 'Кафе и рестораны',
          startDate: month,
          endDate: DateTime(month.year, month.month + 1),
          isSelected: true,
          isBankConfirmed: true,
          cashbackPercent: 5,
          cardId: 1,
          canonicalKeys: const ['restaurants', 'fastfood'],
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MonthlyCashbackScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Кафе, рестораны и бары'), findsOneWidget);
    expect(find.text('Фастфуд'), findsOneWidget);
    expect(find.text('2 из 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

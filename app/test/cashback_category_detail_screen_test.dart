import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/cashback_category_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  CashbackCategoryModel category() => CashbackCategoryModel(
        id: 17,
        name: 'Аптеки',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 30),
        isSelected: true,
        cashbackPercent: 5,
        cardId: 3,
        description: 'Кроме покупок подарочных сертификатов',
        isBankConfirmed: true,
        maxCashbackAmount: 1000,
        minPurchaseAmount: 500,
      );

  DataProvider provider(String role) => DataProvider(
        apiBaseUrl: 'https://cashflow.test',
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      )
        ..currentAuthUser = AuthIdentity(
          id: 1,
          username: 'tester',
          role: role,
        )
        ..banks = [BankModel(id: 1, name: 'Тест Банк')]
        ..users = [UserModel(id: 2, name: 'Анна')]
        ..cards = [
          CardModel(
            id: 3,
            bankId: 1,
            userId: 2,
            lastFourDigits: '1234',
            paymentSystem: 'МИР',
          ),
        ];

  Future<void> pump(
    WidgetTester tester, {
    required DataProvider value,
    required CashbackCategorySaver onSave,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: value,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: ThemeMode.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: CashbackCategoryDetailScreen(
            category: category(),
            onSave: onSave,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('viewer gets a readable compact detail without edit controls',
      (tester) async {
    await pump(
      tester,
      value: provider('viewer'),
      onSave: (_) async {},
      textScale: 2,
    );

    expect(find.text('Аптеки'), findsWidgets);
    expect(find.text('В плане'), findsOneWidget);
    expect(find.text('Подтверждено банком'), findsWidgets);
    expect(find.text('Редактировать'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor opens a dedicated compact edit form', (tester) async {
    await pump(
      tester,
      value: provider('editor'),
      onSave: (_) async {},
      textScale: 1.3,
    );

    final edit = find.text('Редактировать данные');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(find.text('Редактирование'), findsOneWidget);
    expect(find.byKey(const Key('category-name-field')), findsOneWidget);
    expect(find.byKey(const Key('category-percent-field')), findsOneWidget);
    expect(find.text('Сохранить изменения'), findsOneWidget);
    expect(find.text('Выгода'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor updates the category from expanded layout',
      (tester) async {
    CashbackCategoryModel? saved;
    await pump(
      tester,
      value: provider('editor'),
      onSave: (value) async => saved = value,
      size: const Size(1100, 820),
    );

    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-percent-field')),
      '7,5',
    );
    final save = find.text('Сохранить изменения');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved?.cashbackPercent, 7.5);
    expect(find.text('Изменения сохранены'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

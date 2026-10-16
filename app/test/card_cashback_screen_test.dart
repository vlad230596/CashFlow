import 'package:cashflow/models/bank_model.dart';
import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/cashback_category_model.dart';
import 'package:cashflow/models/user_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/card_cashback_screen.dart';
import 'package:cashflow/screens/cards_screen.dart';
import 'package:cashflow/services/business_clock.dart';
import 'package:cashflow/services/card_cashback_overview.dart';
import 'package:cashflow/utils/cashback_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/mcc_test_cache.dart';

CashbackCategoryModel _category(
  int id,
  String name, {
  int cardId = 1,
  double percent = 5,
  bool selected = true,
  bool confirmed = true,
  int month = 10,
}) =>
    CashbackCategoryModel(
      id: id,
      name: name,
      startDate: DateTime(2026, month),
      endDate: DateTime(2026, month + 1, 0, 23, 59, 59),
      isSelected: selected,
      isBankConfirmed: confirmed,
      cashbackPercent: percent,
      cardId: cardId,
    );

final _categories = [
  _category(1, 'Аптеки', percent: 5),
  _category(2, 'Рестораны', percent: 10),
  _category(3, 'Такси', confirmed: false),
  _category(4, 'Кино', selected: false, confirmed: false),
  _category(5, 'Цветы', month: 11),
  _category(6, 'Чужая карта', cardId: 2),
];

DataProvider _provider() => DataProvider(
      mccCacheStore: isolatedMccCache(),
      businessClock: BusinessClock(now: () => DateTime.utc(2026, 10, 16, 9)),
      apiBaseUrl: 'https://cashflow.test',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    )
      ..banks.add(BankModel(id: 1, name: 'Альфа-Банк', description: ''))
      ..users.add(UserModel(id: 7, name: 'Анна'))
      ..cards.addAll([
        CardModel(
          id: 1,
          bankId: 1,
          userId: 7,
          paymentSystem: 'Visa',
          cardType: 'Debit',
          lastFourDigits: '1234',
        ),
        CardModel(
          id: 2,
          bankId: 1,
          userId: 7,
          paymentSystem: 'Mir',
          cardType: 'Debit',
          lastFourDigits: '9999',
        ),
      ])
      ..cashbackCategories = [..._categories];

void main() {
  test('overview splits a card month by selection certainty', () {
    final overview = cardCashbackOverview(
      _categories,
      1,
      CashbackPeriod.month(DateTime(2026, 10, 16)),
    );
    expect(overview.active.map((c) => c.name), ['Рестораны', 'Аптеки']);
    expect(overview.pending.map((c) => c.name), ['Такси']);
    expect(overview.available.map((c) => c.name), ['Кино']);
  });

  test('months start with the current one and include later plans', () {
    expect(
      cardCashbackMonths(_categories, 1, DateTime(2026, 10, 16)),
      [DateTime(2026, 10), DateTime(2026, 11)],
    );
    expect(
      cardCashbackMonths(const [], 1, DateTime(2026, 10, 16)),
      [DateTime(2026, 10)],
    );
  });

  testWidgets('card screen shows selections and marks the source category',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _provider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(
        home: CardCashbackScreen(cardId: 1, highlightCategoryId: 2),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Карта •1234'), findsOneWidget);
    expect(find.text('Действует · 2'), findsOneWidget);
    expect(find.text('Выбрано в плане · 1'), findsOneWidget);
    expect(find.text('Вы пришли из этой категории'), findsOneWidget);
    expect(find.text('Кино'), findsNothing);
    expect(find.text('Чужая карта'), findsNothing);

    await tester.tap(find.textContaining('невыбранные'));
    await tester.pumpAndSettle();
    expect(find.text('Кино'), findsOneWidget);

    await tester.tap(find.textContaining('Ноябрь'));
    await tester.pumpAndSettle();
    expect(find.text('Цветы'), findsOneWidget);
    expect(find.text('Аптеки'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('cards list opens the card selection', (tester) async {
    final provider = _provider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: CardsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Рестораны 10%'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'чужая');
    await tester.pumpAndSettle();
    expect(find.textContaining('•9999'), findsOneWidget);
    expect(find.textContaining('•1234'), findsNothing);

    await tester.tap(find.textContaining('•9999'));
    await tester.pumpAndSettle();
    expect(find.text('Карта •9999'), findsOneWidget);
    expect(find.text('Чужая карта'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}

import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/home_screen.dart';
import 'package:cashflow/screens/subscriptions_screen.dart';
import 'package:cashflow/theme/cashflow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('compact shell fits five destinations at 360 px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_TestDataProvider(), const HomeScreen()));

    expect(
      find.byKey(const ValueKey('shell-destination-Подписки')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows renewal summary and chronological groups', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithSubscriptions();

    await tester.pumpWidget(_app(provider, const SubscriptionsScreen()));

    expect(find.text('Ближайшее списание'), findsOneWidget);
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Ближайшие 7 дней'), findsOneWidget);
    expect(find.text('499 ₽'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded layout shows master and detail without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_providerWithSubscriptions(), const SubscriptionsScreen()),
    );

    expect(find.text('Следующее списание'), findsOneWidget);
    expect(find.text('История платежей'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(DataProvider provider, Widget home) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(theme: CashFlowTheme.light(), home: home),
    );

DataProvider _providerWithSubscriptions() {
  final provider = _TestDataProvider();
  provider.cards = [
    CardModel(id: 3, lastFourDigits: '1234'),
  ];
  final today = DateTime.now();
  provider.subscriptions = [
    SubscriptionModel(
      id: 1,
      name: 'Музыка',
      kind: SubscriptionKind.subscription,
      expectedAmount: 499,
      currency: 'RUB',
      cardId: 3,
      billingInterval: const BillingInterval(
        count: 1,
        unit: BillingIntervalUnit.months,
      ),
      nextPaymentDate: DateTime(today.year, today.month, today.day),
    ),
    SubscriptionModel(
      id: 2,
      name: 'Облако',
      kind: SubscriptionKind.subscription,
      expectedAmount: 2990,
      currency: 'RUB',
      cardId: 3,
      billingInterval: const BillingInterval(
        count: 1,
        unit: BillingIntervalUnit.years,
      ),
      nextPaymentDate: DateTime(today.year, today.month, today.day + 5),
    ),
  ];
  return provider;
}

class _TestDataProvider extends DataProvider {
  @override
  Future<SubscriptionModel> fetchSubscription(int id) async =>
      subscriptions.firstWhere((item) => item.id == id);
}

import 'package:cashflow/models/card_model.dart';
import 'package:cashflow/models/planned_payment_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/providers/data_provider.dart';
import 'package:cashflow/screens/home_screen.dart';
import 'package:cashflow/screens/payments_hub_screen.dart';
import 'package:cashflow/screens/planned_payments_screen.dart';
import 'package:cashflow/screens/subscriptions_screen.dart';
import 'package:cashflow/theme/cashflow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_reminders.dart';
import 'support/mcc_test_cache.dart';

void main() {
  testWidgets('Платежи tab switches between three sections at 360 px',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPayments();

    await tester.pumpWidget(_app(provider, const HomeScreen()));
    await tester.tap(find.byKey(const ValueKey('shell-destination-Платежи')));
    await tester.pumpAndSettle();

    final hub = tester.state<PaymentsHubScreenState>(
      find.byType(PaymentsHubScreen),
    );
    expect(hub.section, PaymentsSection.subscriptions);
    expect(find.text('Регулярные'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Регулярные').first);
    await tester.pumpAndSettle();
    expect(hub.section, PaymentsSection.recurring);
    expect(
        find.byKey(const ValueKey('payments-overdue-banner')), findsOneWidget);
    expect(find.text('Просрочено на 2 дн.'), findsOneWidget);
    expect(find.text(overdueGroupLabel), findsOneWidget);
    expect(find.text('Детский сад'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Разовые').first);
    await tester.pumpAndSettle();
    expect(hub.section, PaymentsSection.oneOff);
    expect(find.text('Страховка'), findsWidgets);
    expect(find.text('Срок оплаты завтра'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment details show overdue state and mark-paid action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPayments();

    await tester.pumpWidget(_app(
      provider,
      PlannedPaymentDetails(payment: provider.plannedPayments.first),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payment-due-status')), findsOneWidget);
    expect(find.text('Просрочено на 2 дн.'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-mark-paid')), findsOneWidget);
    expect(find.text('За 1 день'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment editor defaults to a day-before reminder',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPayments();

    await tester.pumpWidget(_app(
      provider,
      const PlannedPaymentEditScreen(kind: PlannedPaymentKind.recurring),
    ));
    await tester.pumpAndSettle();

    final chip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('reminder-day-1')),
    );
    expect(chip.selected, isTrue);
    expect(find.text('Периодичность'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription editor keeps and saves edited reminder days',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _providerWithPayments();
    final existing = SubscriptionModel(
      id: 1,
      name: 'Облако',
      kind: SubscriptionKind.subscription,
      expectedAmount: 299,
      currency: 'RUB',
      cardId: 3,
      billingInterval:
          const BillingInterval(count: 1, unit: BillingIntervalUnit.months),
      nextPaymentDate: DateTime(2027, 1, 10),
      reminderDays: const [3],
    );
    provider.subscriptions = [existing];

    await tester.pumpWidget(_app(
      provider,
      SubscriptionEditScreen(existing: existing),
    ));
    await tester.pumpAndSettle();

    bool selected(int days) => tester
        .widget<FilterChip>(find.byKey(ValueKey('reminder-day-$days')))
        .selected;
    expect(selected(3), isTrue);
    expect(selected(7), isFalse);

    await tester.tap(find.byKey(const ValueKey('reminder-day-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(provider.savedSubscriptions.single.reminderDays, [3, 0]);
  });
}

Widget _app(DataProvider provider, Widget home) => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(theme: CashFlowTheme.light(), home: home),
    );

_TestDataProvider _providerWithPayments() {
  final provider = _TestDataProvider();
  provider.cards = [CardModel(id: 3, lastFourDigits: '1234')];
  final today = provider.businessToday;
  provider.plannedPayments = [
    PlannedPaymentModel(
      id: 5,
      name: 'Детский сад',
      kind: PlannedPaymentKind.recurring,
      expectedAmount: 8500,
      currency: 'RUB',
      interval:
          const BillingInterval(count: 1, unit: BillingIntervalUnit.months),
      nextDueDate: DateTime(today.year, today.month, today.day - 2),
    ),
    PlannedPaymentModel(
      id: 6,
      name: 'Страховка',
      kind: PlannedPaymentKind.oneOff,
      expectedAmount: 12000,
      currency: 'RUB',
      cardId: 3,
      nextDueDate: DateTime(today.year, today.month, today.day + 1),
    ),
  ];
  return provider;
}

class _TestDataProvider extends DataProvider {
  _TestDataProvider()
      : super(
          mccCacheStore: isolatedMccCache(),
          reminderNotificationService: FakeReminders(),
        );

  final savedSubscriptions = <SubscriptionModel>[];

  @override
  Future<SubscriptionModel> fetchSubscription(int id) async =>
      subscriptions.firstWhere((item) => item.id == id);

  @override
  Future<PlannedPaymentModel> fetchPlannedPayment(int id) async =>
      plannedPayments.firstWhere((item) => item.id == id);

  @override
  Future<SubscriptionModel> updateSubscription(
    SubscriptionModel subscription,
  ) async {
    savedSubscriptions.add(subscription);
    return subscription;
  }
}

import 'package:cashflow/models/planned_payment_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/services/reminder_notification_service.dart';
import 'package:cashflow/services/reminder_sources.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedPaymentModel _payment({
  int id = 7,
  PlannedPaymentKind kind = PlannedPaymentKind.recurring,
  DateTime? due,
  List<int> reminders = const [1],
  bool completed = false,
  bool archived = false,
}) =>
    PlannedPaymentModel(
      id: id,
      name: 'Детский сад',
      kind: kind,
      expectedAmount: 8500,
      currency: 'RUB',
      interval: kind == PlannedPaymentKind.recurring
          ? const BillingInterval(count: 1, unit: BillingIntervalUnit.months)
          : null,
      nextDueDate: due ?? DateTime(2026, 11, 25),
      reminderDays: reminders,
      isCompleted: completed,
      isArchived: archived,
    );

void main() {
  test('each kind owns a disjoint id block below the legacy range', () {
    final ranges = [
      for (final kind in ReminderKind.values)
        (kind.idBase, kind.idBase + ReminderKind.blockSize - 1),
    ];
    for (var i = 0; i < ranges.length; i++) {
      for (var j = i + 1; j < ranges.length; j++) {
        expect(
          ranges[i].$2 < ranges[j].$1 || ranges[j].$2 < ranges[i].$1,
          isTrue,
        );
      }
      expect(ranges[i].$2, lessThan(legacySubscriptionIdStart));
      expect(ranges[i].$1, greaterThan(0));
    }
    expect(ReminderKind.values.map((kind) => kind.key).toSet(),
        hasLength(ReminderKind.values.length));
    expect(ReminderKind.values.map((kind) => kind.block).toSet(),
        hasLength(ReminderKind.values.length));
  });

  test('ids are deterministic, owned by their kind and slot-bounded', () {
    const kind = ReminderKind.payment;
    final first = kind.notificationId(42, 0);
    final last = kind.notificationId(42, ReminderKind.slotsPerEntity - 1);

    expect(first, 200000000 + 42 * ReminderKind.slotsPerEntity);
    expect(last - first, ReminderKind.slotsPerEntity - 1);
    expect(kind.ownsId(first), isTrue);
    expect(ReminderKind.subscription.ownsId(first), isFalse);
    expect(kind.notificationId(43, 0), last + 1);
    // Huge ids wrap inside the block instead of leaking into another kind.
    expect(kind.ownsId(kind.notificationId(1 << 40, 31)), isTrue);
    expect(() => kind.notificationId(1, ReminderKind.slotsPerEntity),
        throwsRangeError);
    expect(isLegacySubscriptionNotificationId(700000000 + 12 * 64), isTrue);
    expect(isLegacySubscriptionNotificationId(first), isFalse);
  });

  test('payloads are typed and legacy bare ids route to subscriptions', () {
    const target = ReminderTarget(ReminderKind.payment, 12);
    expect(target.payload, 'payment:12');
    expect(ReminderTarget.parse('payment:12'), target);
    expect(ReminderTarget.parse('subscription:3'),
        const ReminderTarget(ReminderKind.subscription, 3));
    expect(ReminderTarget.parse('12'),
        const ReminderTarget(ReminderKind.subscription, 12));
    expect(ReminderTarget.parse('promo:1'), isNull);
    expect(ReminderTarget.parse('payment:x'), isNull);
    expect(ReminderTarget.parse(null), isNull);
  });

  test('day-before reminder fires at 10:00 the day before the due date', () {
    final planned = const ReminderPlanner().plan(
      ReminderKind.payment,
      paymentReminderSpecs([_payment()]),
      DateTime(2026, 11, 11, 12),
    );

    expect(planned, hasLength(1));
    final reminder = planned.single;
    expect(reminder.fireAt, DateTime(2026, 11, 24, 10));
    expect(reminder.daysBefore, 1);
    expect(reminder.id, ReminderKind.payment.notificationId(7, 0));
    expect(reminder.payload, 'payment:7');
    expect(reminder.title, 'Пора оплатить: Детский сад');
    expect(reminder.body, contains('до 25.11.2026'));
    expect(reminder.body, contains('завтра'));
  });

  test('one-off: reminder on 12 Nov for a payment due 13 Nov', () {
    final planned = const ReminderPlanner().plan(
      ReminderKind.payment,
      paymentReminderSpecs([
        _payment(
          kind: PlannedPaymentKind.oneOff,
          due: DateTime(2026, 11, 13),
          reminders: const [0, 1, 1, 3],
        ),
      ]),
      DateTime(2026, 11, 11, 9),
    );

    expect(
      planned.map((item) => (item.fireAt, item.daysBefore)).toList(),
      [
        (DateTime(2026, 11, 10, 10), 3),
        (DateTime(2026, 11, 12, 10), 1),
        (DateTime(2026, 11, 13, 10), 0),
      ].where((item) => item.$1.isAfter(DateTime(2026, 11, 11, 9))).toList(),
    );
    expect(planned.map((item) => item.id).toSet(), hasLength(planned.length));
    expect(planned.last.title, 'Сегодня срок оплаты: Детский сад');
  });

  test('past reminders, closed payments and empty reminders are skipped', () {
    final planned = const ReminderPlanner().plan(
      ReminderKind.payment,
      paymentReminderSpecs([
        _payment(id: 1, due: DateTime(2026, 11, 12)),
        _payment(id: 2, completed: true),
        _payment(id: 3, archived: true),
        _payment(id: 4, reminders: const []),
        _payment(id: 5),
      ]),
      DateTime(2026, 11, 11, 10, 30),
    );

    expect(planned.map((item) => item.target.entityId), [5]);
  });

  test('subscription specs keep their kind, defaults and legacy wording', () {
    final subscription = SubscriptionModel(
      id: 9,
      name: 'Облако',
      kind: SubscriptionKind.subscription,
      expectedAmount: 299,
      currency: 'RUB',
      cardId: 1,
      billingInterval:
          const BillingInterval(count: 1, unit: BillingIntervalUnit.months),
      nextPaymentDate: DateTime(2026, 12, 20),
    );
    final planned = const ReminderPlanner().plan(
      ReminderKind.subscription,
      subscriptionReminderSpecs([
        subscription,
        subscription.copyWith(id: 10, isArchived: true),
      ]),
      DateTime(2026, 11, 11),
    );

    expect(planned.map((item) => item.daysBefore), [7, 1]);
    expect(planned.every((item) => item.payload == 'subscription:9'), isTrue);
    expect(
      planned.every((item) => ReminderKind.subscription.ownsId(item.id)),
      isTrue,
    );
    expect(planned.first.title, 'Скоро продление: Облако');
  });
}

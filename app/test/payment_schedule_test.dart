import 'package:cashflow/models/planned_payment_model.dart';
import 'package:cashflow/models/subscription_model.dart';
import 'package:cashflow/services/payment_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

const _monthly = BillingInterval(count: 1, unit: BillingIntervalUnit.months);

void main() {
  test('month-end anchor does not drift', () {
    final schedule = PaymentSchedule(
      anchor: DateTime(2026, 1, 31),
      interval: _monthly,
    );

    expect(
      [for (var i = 0; i < 5; i++) schedule.occurrence(i)],
      [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
        DateTime(2026, 5, 31),
      ],
    );
    expect(schedule.nextAfter(DateTime(2026, 2, 28)), DateTime(2026, 3, 31));
    expect(schedule.nextAfter(DateTime(2025, 12, 1)), DateTime(2026, 1, 31));
    expect(schedule.isOccurrence(DateTime(2026, 2, 28)), isTrue);
    expect(schedule.isOccurrence(DateTime(2026, 2, 27)), isFalse);
  });

  test('anchored to the 25th: early payment keeps the due day', () {
    final schedule = PaymentSchedule(
      anchor: DateTime(2026, 11, 25),
      interval: _monthly,
    );

    // Confirming the 25 Nov due date advances to 25 Dec regardless of when
    // the payment was actually made.
    expect(schedule.nextAfter(DateTime(2026, 11, 25)), DateTime(2026, 12, 25));
    expect(schedule.nextAfter(DateTime(2026, 12, 25)), DateTime(2027, 1, 25));
  });

  test('leap day, weekly and quarterly schedules', () {
    final leap = PaymentSchedule(
      anchor: DateTime(2024, 2, 29),
      interval:
          const BillingInterval(count: 1, unit: BillingIntervalUnit.years),
    );
    expect(leap.nextAfter(DateTime(2024, 2, 29)), DateTime(2025, 2, 28));
    expect(leap.nextAfter(DateTime(2027, 3, 1)), DateTime(2028, 2, 29));

    final biweekly = PaymentSchedule(
      anchor: DateTime(2026, 11, 2),
      interval:
          const BillingInterval(count: 2, unit: BillingIntervalUnit.weeks),
    );
    expect(biweekly.nextAfter(DateTime(2026, 11, 15)), DateTime(2026, 11, 16));
    expect(biweekly.nextAfter(DateTime(2026, 11, 16)), DateTime(2026, 11, 30));
    // Across the end of daylight saving time in zones that still use it.
    expect(biweekly.nextAfter(DateTime(2027, 3, 20)), DateTime(2027, 3, 22));

    final quarterly = PaymentSchedule(
      anchor: DateTime(2026, 1, 31),
      interval:
          const BillingInterval(count: 3, unit: BillingIntervalUnit.months),
    );
    expect(
      quarterly.between(DateTime(2026, 2, 1), DateTime(2026, 12, 31)),
      [DateTime(2026, 4, 30), DateTime(2026, 7, 31), DateTime(2026, 10, 31)],
    );
  });

  test('month-end anchor helper picks a 31st that reaches the due date', () {
    expect(
        monthEndAnchor(DateTime(2026, 2, 28), _monthly), DateTime(2026, 1, 31));
    expect(
        monthEndAnchor(DateTime(2026, 4, 30), _monthly), DateTime(2026, 3, 31));
    expect(
        monthEndAnchor(DateTime(2026, 3, 31), _monthly), DateTime(2026, 3, 31));
    expect(monthEndAnchor(DateTime(2026, 4, 29), _monthly), isNull);
    expect(
      monthEndAnchor(
        DateTime(2026, 6, 30),
        const BillingInterval(count: 1, unit: BillingIntervalUnit.weeks),
      ),
      isNull,
    );
    final quarterly =
        const BillingInterval(count: 3, unit: BillingIntervalUnit.months);
    final anchor = monthEndAnchor(DateTime(2026, 6, 30), quarterly)!;
    expect(anchor.day, 31);
    expect(
      PaymentSchedule(anchor: anchor, interval: quarterly)
          .nextAfter(DateTime(2026, 6, 30)),
      DateTime(2026, 9, 30),
    );
  });

  test('payment model parses API JSON and reports overdue by business day', () {
    final payment = PlannedPaymentModel.fromJson({
      'id': 5,
      'name': 'Детский сад',
      'kind': 'recurring',
      'expected_amount': '8500.00',
      'currency': 'RUB',
      'card_id': null,
      'note': 'группа 3',
      'interval': {'count': 1, 'unit': 'month'},
      'anchor_date': '2026-01-31',
      'next_due_date': '2026-11-30',
      'reminder_days': [1],
      'is_completed': false,
      'is_archived': false,
      'last_record': null,
    });

    expect(payment.kind, PlannedPaymentKind.recurring);
    expect(payment.cardId, isNull);
    expect(payment.anchorDate, DateTime(2026, 1, 31));
    expect(payment.dueDateAfterPayment, DateTime(2026, 12, 31));
    expect(payment.isOverdue(DateTime(2026, 11, 30)), isFalse);
    expect(payment.isOverdue(DateTime(2026, 12, 1)), isTrue);
    expect(payment.daysUntilDue(DateTime(2026, 11, 29)), 1);

    final json = payment.toMutationJson();
    expect(json['kind'], 'recurring');
    expect(json['anchor_date'], '2026-01-31');
    expect(json['next_due_date'], '2026-11-30');
    expect(json['card_id'], isNull);
    expect(PlannedPaymentModel.fromJson(payment.toJson()).anchorDate,
        DateTime(2026, 1, 31));

    final oneOff = PlannedPaymentModel.fromJson({
      ...payment.toJson(),
      'kind': 'one_off',
      'interval': null,
      'is_completed': true,
    });
    expect(oneOff.kind, PlannedPaymentKind.oneOff);
    expect(oneOff.dueDateAfterPayment, isNull);
    expect(oneOff.isOverdue(DateTime(2027, 1, 1)), isFalse);
    expect(oneOff.toMutationJson().containsKey('anchor_date'), isFalse);
  });
}

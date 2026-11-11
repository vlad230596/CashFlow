import '../models/planned_payment_model.dart';
import '../models/subscription_model.dart';
import 'reminder_notification_service.dart';

/// Maps domain entities to reminder specs; one function per [ReminderKind].

List<ReminderSpec> subscriptionReminderSpecs(
  Iterable<SubscriptionModel> subscriptions,
) =>
    [
      for (final subscription in subscriptions)
        if (!subscription.isArchived && subscription.id != null)
          ReminderSpec(
            entityId: subscription.id!,
            dueDate: subscription.nextPaymentDate.toLocal(),
            reminderDays: subscription.effectiveReminderDays,
            title: (_) => 'Скоро продление: ${subscription.name}',
            body: (days) => '${reminderAmount(subscription.expectedAmount)} '
                '${subscription.currency} спишется ${_inDays(days)}',
          ),
    ];

List<ReminderSpec> paymentReminderSpecs(
  Iterable<PlannedPaymentModel> payments,
) =>
    [
      for (final payment in payments)
        if (payment.isOpen && payment.id != null)
          ReminderSpec(
            entityId: payment.id!,
            dueDate: payment.nextDueDate,
            reminderDays: payment.reminderDays,
            title: (days) => days == 0
                ? 'Сегодня срок оплаты: ${payment.name}'
                : 'Пора оплатить: ${payment.name}',
            body: (days) =>
                '${reminderAmount(payment.expectedAmount)} ${payment.currency}'
                ' — оплатить до ${_date(payment.nextDueDate)}'
                '${days == 0 ? '' : ' (${_inDays(days)})'}',
          ),
    ];

String reminderAmount(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2);

String _inDays(int days) => switch (days) {
      0 => 'сегодня',
      1 => 'завтра',
      _ => 'через $days дн.',
    };

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';

import '../services/payment_schedule.dart';
import 'subscription_model.dart';

/// Recurring payments are anchored to a due day; one-off payments are done
/// once they are marked paid.
enum PlannedPaymentKind { recurring, oneOff }

const _kindApiNames = {
  PlannedPaymentKind.recurring: 'recurring',
  PlannedPaymentKind.oneOff: 'one_off',
};

extension PlannedPaymentKindApi on PlannedPaymentKind {
  String get apiName => _kindApiNames[this]!;

  static PlannedPaymentKind parse(Object? value) => value == 'one_off'
      ? PlannedPaymentKind.oneOff
      : PlannedPaymentKind.recurring;
}

const defaultPaymentReminderDays = [1];

String _apiDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime _parseCivilDate(String value) => dateOnly(DateTime.parse(value));

class PlannedPaymentRecord {
  const PlannedPaymentRecord({
    this.id,
    this.paymentId,
    required this.dueDate,
    required this.paidAt,
    required this.amount,
    required this.currency,
    this.cardId,
    this.createdAt,
  });

  final int? id;
  final int? paymentId;
  final DateTime dueDate;
  final DateTime paidAt;
  final double amount;
  final String currency;
  final int? cardId;
  final DateTime? createdAt;

  factory PlannedPaymentRecord.fromJson(Map<String, dynamic> json) =>
      PlannedPaymentRecord(
        id: json['id'] as int?,
        paymentId: json['payment_id'] as int?,
        dueDate: _parseCivilDate(json['due_date'] as String),
        paidAt: _parseCivilDate(json['paid_at'] as String),
        amount: double.parse(json['amount'].toString()),
        currency: json['currency'] as String? ?? 'RUB',
        cardId: json['card_id'] as int?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (paymentId != null) 'payment_id': paymentId,
        'due_date': _apiDate(dueDate),
        'paid_at': _apiDate(paidAt),
        'amount': amount.toStringAsFixed(2),
        'currency': currency,
        'card_id': cardId,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}

class PlannedPaymentModel {
  const PlannedPaymentModel({
    this.id,
    required this.name,
    required this.kind,
    required this.expectedAmount,
    required this.currency,
    this.cardId,
    this.note,
    this.interval,
    DateTime? anchorDate,
    required this.nextDueDate,
    this.reminderDays = defaultPaymentReminderDays,
    this.isCompleted = false,
    this.completedAt,
    this.isArchived = false,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.lastRecord,
    this.records = const [],
  }) : anchorDate = anchorDate ?? nextDueDate;

  final int? id;
  final String name;
  final PlannedPaymentKind kind;
  final double expectedAmount;
  final String currency;
  final int? cardId;
  final String? note;

  /// Null for one-off payments.
  final BillingInterval? interval;

  /// Reference due date of a recurring schedule (e.g. 31 Jan for "by the
  /// last day"); equals [nextDueDate] for one-off payments.
  final DateTime anchorDate;
  final DateTime nextDueDate;

  /// Days before [nextDueDate] to remind; an empty list disables reminders.
  final List<int> reminderDays;
  final bool isCompleted;
  final DateTime? completedAt;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final PlannedPaymentRecord? lastRecord;
  final List<PlannedPaymentRecord> records;

  bool get isRecurring => kind == PlannedPaymentKind.recurring;

  /// Still awaiting payment: not archived and not a completed one-off.
  bool get isOpen => !isArchived && !isCompleted;

  PaymentSchedule? get schedule => interval == null
      ? null
      : PaymentSchedule(anchor: anchorDate, interval: interval!);

  /// Signed whole days until the due date; negative when overdue.
  int daysUntilDue(DateTime today) => civilDayDifference(today, nextDueDate);

  bool isOverdue(DateTime today) => isOpen && daysUntilDue(today) < 0;

  /// The due date that follows a confirmation of the current one.
  DateTime? get dueDateAfterPayment => schedule?.nextAfter(nextDueDate);

  factory PlannedPaymentModel.fromJson(Map<String, dynamic> json) {
    final intervalJson = json['interval'] as Map<String, dynamic>?;
    final lastRecordJson = json['last_record'] as Map<String, dynamic>?;
    final nextDue = _parseCivilDate(json['next_due_date'] as String);
    return PlannedPaymentModel(
      id: json['id'] as int?,
      name: json['name'] as String,
      kind: PlannedPaymentKindApi.parse(json['kind']),
      expectedAmount: double.parse(json['expected_amount'].toString()),
      currency: json['currency'] as String? ?? 'RUB',
      cardId: json['card_id'] as int?,
      note: json['note'] as String?,
      interval:
          intervalJson == null ? null : BillingInterval.fromJson(intervalJson),
      anchorDate: json['anchor_date'] == null
          ? nextDue
          : _parseCivilDate(json['anchor_date'] as String),
      nextDueDate: nextDue,
      reminderDays:
          (json['reminder_days'] as List? ?? defaultPaymentReminderDays)
              .map((value) => value as int)
              .toList(growable: false),
      isCompleted: json['is_completed'] as bool? ?? false,
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      isArchived: json['is_archived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      lastRecord: lastRecordJson == null
          ? null
          : PlannedPaymentRecord.fromJson(lastRecordJson),
      records: (json['records'] as List? ?? const [])
          .map((item) =>
              PlannedPaymentRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// Fields accepted by POST/PUT `/api/payments`.
  Map<String, dynamic> toMutationJson() => {
        'name': name,
        'kind': kind.apiName,
        'expected_amount': expectedAmount.toStringAsFixed(2),
        'currency': currency,
        'card_id': cardId,
        'note': note,
        'interval': interval?.toJson(),
        'next_due_date': _apiDate(nextDueDate),
        if (isRecurring) 'anchor_date': _apiDate(anchorDate),
        'reminder_days': reminderDays,
      };

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        ...toMutationJson(),
        'anchor_date': _apiDate(anchorDate),
        'is_completed': isCompleted,
        'completed_at': completedAt?.toIso8601String(),
        'is_archived': isArchived,
        'archived_at': archivedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'last_record': lastRecord?.toJson(),
        'records': records.map((record) => record.toJson()).toList(),
      };

  PlannedPaymentModel copyWith({
    List<PlannedPaymentRecord>? records,
  }) =>
      PlannedPaymentModel(
        id: id,
        name: name,
        kind: kind,
        expectedAmount: expectedAmount,
        currency: currency,
        cardId: cardId,
        note: note,
        interval: interval,
        anchorDate: anchorDate,
        nextDueDate: nextDueDate,
        reminderDays: reminderDays,
        isCompleted: isCompleted,
        completedAt: completedAt,
        isArchived: isArchived,
        archivedAt: archivedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastRecord: lastRecord,
        records: records ?? this.records,
      );
}

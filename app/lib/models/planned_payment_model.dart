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

/// Four ASCII digits: the only accepted MCC form.
final mccCodePattern = RegExp(r'^\d{4}$');

/// One card choice for a payment MCC, computed by the server.
class PaymentCardOption {
  const PaymentCardOption({
    required this.offerId,
    required this.cardId,
    required this.categoryName,
    required this.cashbackPercent,
    this.bankId,
    this.bankName,
    this.lastFourDigits,
    this.categoryType = 'standard',
  });

  final int offerId;
  final int cardId;
  final int? bankId;
  final String? bankName;
  final String? lastFourDigits;
  final String categoryName;
  final String categoryType;
  final double cashbackPercent;

  bool get isStackableBonus => categoryType == 'stackable_bonus';

  factory PaymentCardOption.fromJson(Map<String, dynamic> json) =>
      PaymentCardOption(
        offerId: json['offer_id'] as int,
        cardId: json['card_id'] as int,
        bankId: json['bank_id'] as int?,
        bankName: json['bank_name'] as String?,
        lastFourDigits: json['last_four_digits'] as String?,
        categoryName: json['category_name'] as String,
        categoryType: json['category_type'] as String? ?? 'standard',
        cashbackPercent: (json['cashback_percent'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'offer_id': offerId,
        'card_id': cardId,
        'bank_id': bankId,
        'bank_name': bankName,
        'last_four_digits': lastFourDigits,
        'category_name': categoryName,
        'category_type': categoryType,
        'cashback_percent': cashbackPercent,
      };
}

enum PaymentCardSuggestionStatus { best, noBonus, noRules }

/// Which active card earns most for a payment's MCC on its due date (today
/// when overdue). The server resolves it with the same MCC rules and offer
/// ranking as the Benefit screen; the copy cached with the payment is shown
/// offline together with its [asOf] day.
class PaymentCardSuggestion {
  const PaymentCardSuggestion({
    required this.mccCode,
    required this.asOf,
    required this.status,
    this.best,
    this.alternatives = const [],
  });

  final String mccCode;
  final DateTime asOf;
  final PaymentCardSuggestionStatus status;
  final PaymentCardOption? best;
  final List<PaymentCardOption> alternatives;

  static const _statusNames = {
    PaymentCardSuggestionStatus.best: 'best',
    PaymentCardSuggestionStatus.noBonus: 'no_bonus',
    PaymentCardSuggestionStatus.noRules: 'no_rules',
  };

  factory PaymentCardSuggestion.fromJson(Map<String, dynamic> json) {
    final best = json['best'] as Map<String, dynamic>?;
    final status = _statusNames.entries
            .where((entry) => entry.value == json['status'])
            .firstOrNull
            ?.key ??
        PaymentCardSuggestionStatus.noRules;
    return PaymentCardSuggestion(
      mccCode: json['mcc_code'] as String,
      asOf: _parseCivilDate(json['as_of'] as String),
      // A "best" answer without an option is treated as nothing to suggest.
      status: status == PaymentCardSuggestionStatus.best && best == null
          ? PaymentCardSuggestionStatus.noBonus
          : status,
      best: best == null ? null : PaymentCardOption.fromJson(best),
      alternatives: (json['alternatives'] as List? ?? const [])
          .map((item) =>
              PaymentCardOption.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'mcc_code': mccCode,
        'as_of': _apiDate(asOf),
        'status': _statusNames[status],
        'best': best?.toJson(),
        'alternatives': alternatives.map((item) => item.toJson()).toList(),
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
    this.mccCode,
    this.cardSuggestion,
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

  /// Merchant category code the payment is charged with (four digits).
  final String? mccCode;

  /// Server answer for [mccCode]; null without a code or once closed.
  final PaymentCardSuggestion? cardSuggestion;

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
      mccCode: json['mcc_code'] as String?,
      cardSuggestion: json['card_suggestion'] is Map<String, dynamic>
          ? PaymentCardSuggestion.fromJson(
              json['card_suggestion'] as Map<String, dynamic>)
          : null,
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
        'mcc_code': mccCode,
        'interval': interval?.toJson(),
        'next_due_date': _apiDate(nextDueDate),
        if (isRecurring) 'anchor_date': _apiDate(anchorDate),
        'reminder_days': reminderDays,
      };

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        ...toMutationJson(),
        'anchor_date': _apiDate(anchorDate),
        'card_suggestion': cardSuggestion?.toJson(),
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
    int? cardId,
  }) =>
      PlannedPaymentModel(
        id: id,
        name: name,
        kind: kind,
        expectedAmount: expectedAmount,
        currency: currency,
        cardId: cardId ?? this.cardId,
        note: note,
        mccCode: mccCode,
        cardSuggestion: cardSuggestion,
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

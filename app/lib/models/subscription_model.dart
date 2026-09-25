enum SubscriptionKind { subscription, trial }

enum BillingIntervalUnit { days, weeks, months, years }

const _billingIntervalUnitApiNames = {
  BillingIntervalUnit.days: 'day',
  BillingIntervalUnit.weeks: 'week',
  BillingIntervalUnit.months: 'month',
  BillingIntervalUnit.years: 'year',
};

String _dateToJson(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class BillingInterval {
  const BillingInterval({required this.count, required this.unit})
      : assert(count > 0);

  final int count;
  final BillingIntervalUnit unit;

  factory BillingInterval.fromJson(Map<String, dynamic> json) {
    return BillingInterval(
      count: json['count'] as int? ?? 1,
      unit: _billingIntervalUnitApiNames.entries
          .firstWhere(
            (entry) => entry.value == json['unit'],
            orElse: () => const MapEntry(
              BillingIntervalUnit.months,
              'month',
            ),
          )
          .key,
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'unit': _billingIntervalUnitApiNames[unit],
      };
}

class SubscriptionPayment {
  const SubscriptionPayment({
    this.id,
    this.subscriptionId,
    required this.paidAt,
    required this.amount,
    required this.currency,
    required this.cardId,
    this.createdAt,
  });

  final int? id;
  final int? subscriptionId;
  final DateTime paidAt;
  final double amount;
  final String currency;
  final int cardId;
  final DateTime? createdAt;

  factory SubscriptionPayment.fromJson(Map<String, dynamic> json) {
    return SubscriptionPayment(
      id: json['id'] as int?,
      subscriptionId: json['subscription_id'] as int?,
      paidAt: DateTime.parse(json['paid_at'] as String),
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] as String? ?? 'RUB',
      cardId: json['card_id'] as int,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson({bool includeId = true}) => {
        if (includeId && id != null) 'id': id,
        if (includeId && subscriptionId != null)
          'subscription_id': subscriptionId,
        'paid_at': _dateToJson(paidAt),
        'amount': amount.toStringAsFixed(2),
        'currency': currency,
        'card_id': cardId,
        if (includeId && createdAt != null)
          'created_at': createdAt!.toIso8601String(),
      };
}

class SubscriptionActivePeriod {
  const SubscriptionActivePeriod({
    this.id,
    this.subscriptionId,
    required this.startedAt,
    this.endedAt,
  });

  final int? id;
  final int? subscriptionId;
  final DateTime startedAt;
  final DateTime? endedAt;

  factory SubscriptionActivePeriod.fromJson(Map<String, dynamic> json) {
    return SubscriptionActivePeriod(
      id: json['id'] as int?,
      subscriptionId: json['subscription_id'] as int?,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.tryParse(json['ended_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (subscriptionId != null) 'subscription_id': subscriptionId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
      };
}

class SubscriptionModel {
  const SubscriptionModel({
    this.id,
    required this.name,
    required this.kind,
    required this.expectedAmount,
    required this.currency,
    required this.cardId,
    required this.billingInterval,
    required this.nextPaymentDate,
    this.reminderDays = const [],
    this.isArchived = false,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.lastPayment,
    this.payments = const [],
    this.activePeriods = const [],
  });

  final int? id;
  final String name;
  final SubscriptionKind kind;
  final double expectedAmount;
  final String currency;
  final int cardId;
  final BillingInterval billingInterval;
  final DateTime nextPaymentDate;
  final List<int> reminderDays;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final SubscriptionPayment? lastPayment;
  final List<SubscriptionPayment> payments;
  final List<SubscriptionActivePeriod> activePeriods;

  DateTime? get lastPaymentDate => lastPayment?.paidAt;

  double get yearlyEquivalent {
    final intervalsPerYear = switch (billingInterval.unit) {
      BillingIntervalUnit.days => 365.2425 / billingInterval.count,
      BillingIntervalUnit.weeks => 52.1775 / billingInterval.count,
      BillingIntervalUnit.months => 12 / billingInterval.count,
      BillingIntervalUnit.years => 1 / billingInterval.count,
    };
    return expectedAmount * intervalsPerYear;
  }

  double get monthlyEquivalent => yearlyEquivalent / 12;

  List<int> get effectiveReminderDays {
    if (reminderDays.isNotEmpty) return reminderDays;
    if (kind == SubscriptionKind.trial) return const [3, 1];
    if (billingInterval.unit == BillingIntervalUnit.years) {
      return const [30, 7, 1];
    }
    return const [7, 1];
  }

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    final paymentJson = json['last_payment'] as Map<String, dynamic>?;
    return SubscriptionModel(
      id: json['id'] as int?,
      name: json['name'] as String,
      kind: json['kind'] == 'trial'
          ? SubscriptionKind.trial
          : SubscriptionKind.subscription,
      expectedAmount: double.parse(json['expected_amount'].toString()),
      currency: json['currency'] as String? ?? 'RUB',
      cardId: json['card_id'] as int,
      billingInterval: BillingInterval.fromJson(
        json['billing_interval'] as Map<String, dynamic>,
      ),
      nextPaymentDate: DateTime.parse(json['next_payment_date'] as String),
      reminderDays: (json['reminder_days'] as List? ?? const [])
          .map((value) => value as int)
          .toList(growable: false),
      isArchived: json['is_archived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      lastPayment: paymentJson == null
          ? null
          : SubscriptionPayment.fromJson(paymentJson),
      payments: (json['payments'] as List? ?? const [])
          .map((item) => SubscriptionPayment.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(growable: false),
      activePeriods: (json['active_periods'] as List? ?? const [])
          .map((item) => SubscriptionActivePeriod.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toMutationJson({bool includeLastPayment = false}) => {
        'name': name,
        'kind': kind.name,
        'expected_amount': expectedAmount.toStringAsFixed(2),
        'currency': currency,
        'card_id': cardId,
        'billing_interval': billingInterval.toJson(),
        'next_payment_date': _dateToJson(nextPaymentDate),
        'reminder_days': effectiveReminderDays,
        if (includeLastPayment && lastPayment != null)
          'last_payment': lastPayment!.toJson(includeId: false),
      };

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        ...toMutationJson(),
        'is_archived': isArchived,
        'archived_at': archivedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'last_payment': lastPayment?.toJson(),
        'payments': payments.map((payment) => payment.toJson()).toList(),
        'active_periods':
            activePeriods.map((period) => period.toJson()).toList(),
      };

  SubscriptionModel copyWith({
    int? id,
    String? name,
    SubscriptionKind? kind,
    double? expectedAmount,
    String? currency,
    int? cardId,
    BillingInterval? billingInterval,
    DateTime? nextPaymentDate,
    List<int>? reminderDays,
    bool? isArchived,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    SubscriptionPayment? lastPayment,
    List<SubscriptionPayment>? payments,
    List<SubscriptionActivePeriod>? activePeriods,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      currency: currency ?? this.currency,
      cardId: cardId ?? this.cardId,
      billingInterval: billingInterval ?? this.billingInterval,
      nextPaymentDate: nextPaymentDate ?? this.nextPaymentDate,
      reminderDays: reminderDays ?? this.reminderDays,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPayment: lastPayment ?? this.lastPayment,
      payments: payments ?? this.payments,
      activePeriods: activePeriods ?? this.activePeriods,
    );
  }
}

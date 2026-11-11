import 'dart:math';

import '../services/payment_schedule.dart';

/// A promo code / offer, or a balance of points (bonuses) that can burn.
enum PromoKind { promo, points }

/// Expired is derived from the expiry date and the Moscow business day.
enum PromoStatus { active, expired, used, archived }

const defaultPromoReminderDays = [3, 1];

/// Days left at which an active item is shown as urgent.
const promoUrgentDays = 3;

String _apiDate(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime? _civilDate(Object? value) => value is String && value.isNotEmpty
    ? dateOnly(DateTime.parse(value))
    : null;

double? _decimal(Object? value) =>
    value == null ? null : double.tryParse(value.toString().replaceAll(',', '.'));

final _random = Random.secure();

/// Idempotency key for creating an item that may first be saved offline.
String newPromoClientId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final noise = List.generate(
    10,
    (_) => _random.nextInt(36).toRadixString(36),
  ).join();
  return 'p$time$noise';
}

class PromoModel {
  const PromoModel({
    this.id,
    this.clientId,
    required this.kind,
    required this.title,
    this.merchant,
    this.promoCode,
    this.discount,
    this.pointsAmount,
    this.pointsUnit,
    this.description,
    this.sourceText,
    this.startsAt,
    this.expiresAt,
    this.reminderDays = defaultPromoReminderDays,
    this.usedAt,
    this.isUsed = false,
    this.archivedAt,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
    this.isPending = false,
  });

  final int? id;

  /// Client-generated key; identifies an item saved offline until synced.
  final String? clientId;
  final PromoKind kind;
  final String title;
  final String? merchant;
  final String? promoCode;
  final String? discount;
  final double? pointsAmount;
  final String? pointsUnit;
  final String? description;

  /// The pasted message, verbatim.
  final String? sourceText;
  final DateTime? startsAt;

  /// Last day on which the offer works (inclusive); null when unknown.
  final DateTime? expiresAt;
  final List<int> reminderDays;
  final DateTime? usedAt;
  final bool isUsed;
  final DateTime? archivedAt;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Saved on this device only; not yet accepted by the server.
  final bool isPending;

  bool get isPoints => kind == PromoKind.points;

  /// Stable identity across the offline → synced transition.
  String get localKey => id != null ? 'id:$id' : 'client:$clientId';

  PromoStatus status(DateTime today) {
    if (isArchived) return PromoStatus.archived;
    if (isUsed) return PromoStatus.used;
    final expires = expiresAt;
    if (expires != null && civilDayDifference(today, expires) < 0) {
      return PromoStatus.expired;
    }
    return PromoStatus.active;
  }

  /// Whole days until [expiresAt]; 0 on the last day, negative once expired.
  int? daysLeft(DateTime today) =>
      expiresAt == null ? null : civilDayDifference(today, expiresAt!);

  bool isUrgent(DateTime today) {
    final days = daysLeft(today);
    return status(today) == PromoStatus.active &&
        days != null &&
        days <= promoUrgentDays;
  }

  factory PromoModel.fromJson(Map<String, dynamic> json) => PromoModel(
        id: json['id'] as int?,
        clientId: json['client_id'] as String?,
        kind: json['kind'] == 'points' ? PromoKind.points : PromoKind.promo,
        title: json['title'] as String? ?? '',
        merchant: json['merchant'] as String?,
        promoCode: json['promo_code'] as String?,
        discount: json['discount'] as String?,
        pointsAmount: _decimal(json['points_amount']),
        pointsUnit: json['points_unit'] as String?,
        description: json['description'] as String?,
        sourceText: json['source_text'] as String?,
        startsAt: _civilDate(json['starts_at']),
        expiresAt: _civilDate(json['expires_at']),
        reminderDays:
            (json['reminder_days'] as List? ?? defaultPromoReminderDays)
                .map((value) => value as int)
                .toList(growable: false),
        usedAt: DateTime.tryParse(json['used_at'] as String? ?? ''),
        isUsed: json['is_used'] as bool? ?? false,
        archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? ''),
        isArchived: json['is_archived'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        isPending: json['pending'] as bool? ?? false,
      );

  /// Fields accepted by POST/PUT `/api/promos`.
  Map<String, dynamic> toMutationJson() => {
        if (clientId != null && id == null) 'client_id': clientId,
        'kind': kind.name,
        'title': title,
        'merchant': merchant,
        'promo_code': promoCode,
        'discount': discount,
        'points_amount': pointsAmount?.toStringAsFixed(2),
        'points_unit': pointsUnit,
        'description': description,
        'source_text': sourceText,
        'starts_at': startsAt == null ? null : _apiDate(startsAt!),
        'expires_at': expiresAt == null ? null : _apiDate(expiresAt!),
        'reminder_days': reminderDays,
      };

  /// Local cache representation, including offline state.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        ...toMutationJson(),
        'client_id': clientId,
        'is_used': isUsed,
        'used_at': usedAt?.toIso8601String(),
        'is_archived': isArchived,
        'archived_at': archivedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        if (isPending) 'pending': true,
      };

  PromoModel copyWith({bool? isPending, String? clientId}) => PromoModel(
        id: id,
        clientId: clientId ?? this.clientId,
        kind: kind,
        title: title,
        merchant: merchant,
        promoCode: promoCode,
        discount: discount,
        pointsAmount: pointsAmount,
        pointsUnit: pointsUnit,
        description: description,
        sourceText: sourceText,
        startsAt: startsAt,
        expiresAt: expiresAt,
        reminderDays: reminderDays,
        usedAt: usedAt,
        isUsed: isUsed,
        archivedAt: archivedAt,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isPending: isPending ?? this.isPending,
      );
}

/// Items with [status], in display order: active by soonest expiry (unknown
/// expiry last), expired by most recent expiry, used/archived by most recent.
List<PromoModel> promosWithStatus(
  Iterable<PromoModel> items,
  PromoStatus status,
  DateTime today,
) {
  final result = items.where((item) => item.status(today) == status).toList();
  int byTitle(PromoModel a, PromoModel b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  switch (status) {
    case PromoStatus.active:
      result.sort((a, b) {
        final left = a.expiresAt, right = b.expiresAt;
        if (left == null || right == null) {
          if (left != right) return left == null ? 1 : -1;
          return byTitle(a, b);
        }
        final order = left.compareTo(right);
        return order != 0 ? order : byTitle(a, b);
      });
    case PromoStatus.expired:
      result.sort((a, b) => b.expiresAt!.compareTo(a.expiresAt!));
    case PromoStatus.used:
    case PromoStatus.archived:
      DateTime moment(PromoModel item) =>
          (status == PromoStatus.used ? item.usedAt : item.archivedAt) ??
          item.updatedAt ??
          DateTime(0);
      result.sort((a, b) => moment(b).compareTo(moment(a)));
  }
  return result;
}

/// Pre-filled editor fields recognized in a pasted message.
class PromoParseResult {
  const PromoParseResult({
    this.kind = PromoKind.promo,
    this.title,
    this.merchant,
    this.promoCode,
    this.discount,
    this.pointsAmount,
    this.pointsUnit,
    this.description,
    this.startsAt,
    this.expiresAt,
    this.expiryPhrase,
    this.expiryGuessed = false,
    this.offline = false,
  });

  final PromoKind kind;
  final String? title;
  final String? merchant;
  final String? promoCode;
  final String? discount;
  final double? pointsAmount;
  final String? pointsUnit;
  final String? description;
  final DateTime? startsAt;
  final DateTime? expiresAt;

  /// The text fragment the expiry date came from, e.g. «до 30 ноября».
  final String? expiryPhrase;

  /// The date had no deadline wording around it; ask the user to check it.
  final bool expiryGuessed;

  /// Produced by the on-device fallback (dates and codes only).
  final bool offline;

  bool get isEmpty =>
      merchant == null &&
      promoCode == null &&
      discount == null &&
      pointsAmount == null &&
      expiresAt == null &&
      startsAt == null;

  factory PromoParseResult.fromJson(Map<String, dynamic> json) =>
      PromoParseResult(
        kind: json['kind'] == 'points' ? PromoKind.points : PromoKind.promo,
        title: json['title'] as String?,
        merchant: json['merchant'] as String?,
        promoCode: json['promo_code'] as String?,
        discount: json['discount'] as String?,
        pointsAmount: _decimal(json['points_amount']),
        pointsUnit: json['points_unit'] as String?,
        description: json['description'] as String?,
        startsAt: _civilDate(json['starts_at']),
        expiresAt: _civilDate(json['expires_at']),
        expiryPhrase: json['expiry_phrase'] as String?,
        expiryGuessed: json['expires_at_confidence'] == 'guessed',
      );
}

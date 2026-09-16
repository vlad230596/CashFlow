class PartnerOfferLimit {
  const PartnerOfferLimit({
    required this.type,
    required this.unit,
    required this.scope,
    required this.originalText,
    this.value,
  });

  final String type;
  final double? value;
  final String unit;
  final String scope;
  final String originalText;

  factory PartnerOfferLimit.fromJson(Map<String, dynamic> json) =>
      PartnerOfferLimit(
        type: json['type'] as String? ?? 'other',
        value: (json['value'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? 'unknown',
        scope: json['scope'] as String? ?? 'unknown',
        originalText: json['original_text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'value': value,
        'unit': unit,
        'scope': scope,
        'original_text': originalText,
      };
}

class PartnerOffer {
  const PartnerOffer({
    required this.id,
    required this.bankId,
    required this.cardUserId,
    required this.bankName,
    required this.name,
    required this.description,
    required this.preference,
    required this.isAvailable,
    required this.collectedAt,
    required this.lastSeenAt,
    this.rateLabel,
    this.iconUrl,
    this.startsAt,
    this.endsAt,
    this.validityLabel,
    this.conditions = '',
    this.limits = const [],
    this.requirements = const [],
    this.steps = const [],
    this.links = const [],
  });

  final int id;
  final int bankId;
  final int cardUserId;
  final String bankName;
  final String name;
  final String description;
  final String preference;
  final bool isAvailable;
  final String? rateLabel;
  final String? iconUrl;
  final DateTime collectedAt;
  final DateTime lastSeenAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? validityLabel;
  final String conditions;
  final List<PartnerOfferLimit> limits;
  final List<String> requirements;
  final List<String> steps;
  final List<Map<String, dynamic>> links;

  factory PartnerOffer.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'] as Map<String, dynamic>? ?? const {};
    return PartnerOffer(
      id: json['id'] as int,
      bankId: json['bank_id'] as int,
      cardUserId: json['card_user_id'] as int,
      bankName: json['bank_name'] as String? ?? 'Банк',
      name: snapshot['title'] as String? ?? 'Предложение',
      description: snapshot['description'] as String? ?? '',
      preference: json['preference'] as String? ?? 'undecided',
      isAvailable: json['is_available'] != false,
      rateLabel: snapshot['rate_label'] as String?,
      iconUrl: snapshot['icon_url'] as String?,
      collectedAt: DateTime.parse(snapshot['collected_at'] as String),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      startsAt: DateTime.tryParse(snapshot['starts_at'] as String? ?? ''),
      endsAt: DateTime.tryParse(snapshot['ends_at'] as String? ?? ''),
      validityLabel: snapshot['validity_label'] as String?,
      conditions: snapshot['conditions'] as String? ?? '',
      limits: (snapshot['limits'] as List? ?? const [])
          .map((item) =>
              PartnerOfferLimit.fromJson(item as Map<String, dynamic>))
          .toList(),
      requirements:
          List<String>.from(snapshot['requirements'] as List? ?? const []),
      steps: List<String>.from(snapshot['steps'] as List? ?? const []),
      links: (snapshot['links'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }

  PartnerOffer copyWith({String? preference}) => PartnerOffer(
        id: id,
        bankId: bankId,
        cardUserId: cardUserId,
        bankName: bankName,
        name: name,
        description: description,
        preference: preference ?? this.preference,
        isAvailable: isAvailable,
        rateLabel: rateLabel,
        iconUrl: iconUrl,
        collectedAt: collectedAt,
        lastSeenAt: lastSeenAt,
        startsAt: startsAt,
        endsAt: endsAt,
        validityLabel: validityLabel,
        conditions: conditions,
        limits: limits,
        requirements: requirements,
        steps: steps,
        links: links,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank_id': bankId,
        'bank_name': bankName,
        'card_user_id': cardUserId,
        'preference': preference,
        'is_available': isAvailable,
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
        'first_seen_at': lastSeenAt.toUtc().toIso8601String(),
        'snapshot': {
          'title': name,
          'description': description,
          'rate_label': rateLabel,
          'icon_url': iconUrl,
          'collected_at': collectedAt.toUtc().toIso8601String(),
          'starts_at': startsAt?.toUtc().toIso8601String(),
          'ends_at': endsAt?.toUtc().toIso8601String(),
          'validity_label': validityLabel,
          'conditions': conditions,
          'limits': limits.map((limit) => limit.toJson()).toList(),
          'requirements': requirements,
          'steps': steps,
          'links': links,
        },
      };
}

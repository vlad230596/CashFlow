import 'dart:convert';

class PartnerOffer {
  const PartnerOffer(
      {required this.name,
      required this.bankId,
      required this.bankName,
      required this.description,
      this.rateLabel,
      this.iconAsset,
      this.iconUrl,
      this.collectedAt,
      this.validityLabel,
      this.conditions = '',
      this.limits = const [],
      this.requirements = const [],
      this.conditionsFromHistory = false,
      this.conditionsCollectedAt});

  final String name;
  final String bankId;
  final String bankName;
  final String description;
  final String? rateLabel;
  final String? iconAsset;
  final String? iconUrl;
  final DateTime? collectedAt;
  final String? validityLabel;
  final String conditions;
  final List<String> limits;
  final List<String> requirements;
  final bool conditionsFromHistory;
  final DateTime? conditionsCollectedAt;

  static List<PartnerOffer> parse(String contents) {
    final document = jsonDecode(contents) as Map<String, dynamic>;
    return (document['offers'] as List).map((value) {
      final json = value as Map<String, dynamic>;
      return PartnerOffer(
        name: json['name'] as String,
        bankId: json['bankId'] as String,
        bankName: json['bankName'] as String,
        description: (json['description'] as String? ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        rateLabel: json['rateLabel'] as String?,
        iconAsset: json['iconAsset'] as String?,
        iconUrl: json['iconUrl'] as String?,
        collectedAt: DateTime.tryParse(json['collectedAt'] as String? ?? ''),
        validityLabel: json['validityLabel'] as String? ??
            json['expirationLabel'] as String?,
        conditions: json['conditions'] as String? ?? '',
        limits: List<String>.from(json['limits'] as List? ?? const []),
        requirements:
            List<String>.from(json['requirements'] as List? ?? const []),
        conditionsFromHistory: json['conditionsFromHistory'] == true,
        conditionsCollectedAt:
            DateTime.tryParse(json['conditionsCollectedAt'] as String? ?? ''),
      );
    }).toList();
  }
}

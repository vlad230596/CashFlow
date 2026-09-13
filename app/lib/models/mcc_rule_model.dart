class MccRuleConditionModel {
  const MccRuleConditionModel({
    required this.kind,
    required this.originalText,
    this.operator,
    this.value,
  });

  final String kind;
  final String originalText;
  final String? operator;
  final String? value;

  factory MccRuleConditionModel.fromJson(Map<String, dynamic> json) =>
      MccRuleConditionModel(
        kind: json['kind'] as String,
        originalText: json['original_text'] as String,
        operator: json['operator'] as String?,
        value: json['value'] as String?,
      );

  Map<String, dynamic> toSnapshotJson() => {
        'kind': kind,
        'originalText': originalText,
        if (operator != null) 'operator': operator,
        if (value != null) 'value': value,
      };
}

class MccBankCategoryModel {
  const MccBankCategoryModel({
    required this.id,
    required this.sourceKey,
    required this.name,
    required this.includedMcc,
    required this.excludedMcc,
    required this.conditions,
    required this.completeness,
    this.sourceExternalId,
    this.description,
  });

  final int id;
  final String sourceKey;
  final String? sourceExternalId;
  final String name;
  final String? description;
  final List<String> includedMcc;
  final List<String> excludedMcc;
  final List<MccRuleConditionModel> conditions;
  final String completeness;

  factory MccBankCategoryModel.fromJson(Map<String, dynamic> json) =>
      MccBankCategoryModel(
        id: json['id'] as int,
        sourceKey: json['source_key'] as String,
        sourceExternalId: json['source_external_id'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        includedMcc:
            List<String>.from(json['included_mcc'] as List? ?? const []),
        excludedMcc:
            List<String>.from(json['excluded_mcc'] as List? ?? const []),
        conditions: (json['conditions'] as List? ?? const [])
            .map(
              (item) => MccRuleConditionModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        completeness: json['completeness'] as String? ?? 'unknown',
      );
}

class MccRuleRevisionModel {
  const MccRuleRevisionModel({
    required this.id,
    required this.bankId,
    required this.programKey,
    required this.programName,
    required this.validFrom,
    required this.validityConfidence,
    required this.completeness,
    required this.status,
    required this.recordedAt,
    required this.sourceType,
    required this.globalExcludedMcc,
    required this.conditions,
    required this.categories,
    this.productScope,
    this.validTo,
    this.sourceUrl,
    this.parserName,
    this.parserVersion,
  });

  final int id;
  final int bankId;
  final String programKey;
  final String programName;
  final String? productScope;
  final DateTime validFrom;
  final DateTime? validTo;
  final String validityConfidence;
  final String completeness;
  final String status;
  final DateTime recordedAt;
  final String sourceType;
  final String? sourceUrl;
  final String? parserName;
  final String? parserVersion;
  final List<String> globalExcludedMcc;
  final List<MccRuleConditionModel> conditions;
  final List<MccBankCategoryModel> categories;

  factory MccRuleRevisionModel.fromJson(Map<String, dynamic> json) {
    final program = json['program'] as Map<String, dynamic>;
    final source = json['source'] as Map<String, dynamic>;
    return MccRuleRevisionModel(
      id: json['id'] as int,
      bankId: json['bank_id'] as int,
      programKey: program['source_key'] as String,
      programName: program['name'] as String,
      productScope: program['product_scope'] as String?,
      validFrom: DateTime.parse(json['valid_from'] as String),
      validTo: json['valid_to'] == null
          ? null
          : DateTime.parse(json['valid_to'] as String),
      validityConfidence: json['validity_confidence'] as String,
      completeness: json['completeness'] as String,
      status: json['status'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      sourceType: source['type'] as String,
      sourceUrl: source['url'] as String?,
      parserName: source['parser_name'] as String?,
      parserVersion: source['parser_version'] as String?,
      globalExcludedMcc:
          List<String>.from(json['global_excluded_mcc'] as List? ?? const []),
      conditions: (json['conditions'] as List? ?? const [])
          .map(
            (item) => MccRuleConditionModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      categories: (json['categories'] as List? ?? const [])
          .map(
            (item) => MccBankCategoryModel.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

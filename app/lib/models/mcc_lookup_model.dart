import 'mcc_rule_model.dart';

/// One MCC from the shared reference: the code and what it means.
class MccCodeModel {
  const MccCodeModel({required this.code, this.title, this.description});

  final String code;
  final String? title;
  final String? description;

  factory MccCodeModel.fromJson(Map<String, dynamic> json) => MccCodeModel(
        code: json['code'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

/// A bank category that lists the looked-up MCC.
class MccMatchedCategoryModel {
  const MccMatchedCategoryModel({required this.name, required this.kind});

  final String name;
  final String kind;

  factory MccMatchedCategoryModel.fromJson(Map<String, dynamic> json) =>
      MccMatchedCategoryModel(
        name: json['name'] as String,
        kind: json['kind'] as String? ?? 'mcc',
      );
}

/// How one bank's published rules treat an MCC.
class MccBankRuleModel {
  const MccBankRuleModel({
    required this.bankId,
    required this.bankName,
    required this.status,
    required this.programName,
    required this.completeness,
    this.bankIconKey,
    this.exclusion,
    this.categories = const [],
    this.offerIds = const [],
  });

  final int bankId;
  final String bankName;
  final String? bankIconKey;

  /// excluded, category_only, conditional, category or not_in_categories.
  final String status;
  final String programName;
  final String completeness;
  final MccExclusionModel? exclusion;
  final List<MccMatchedCategoryModel> categories;

  /// Offers on this bank's cards that earn their category rate for the code.
  final List<int> offerIds;

  factory MccBankRuleModel.fromJson(Map<String, dynamic> json) {
    final bank = json['bank'] as Map<String, dynamic>;
    final program = json['program'] as Map<String, dynamic>? ?? const {};
    final exclusion = json['exclusion'] as Map<String, dynamic>?;
    return MccBankRuleModel(
      bankId: bank['id'] as int,
      bankName: bank['name'] as String? ?? 'Банк ${bank['id']}',
      bankIconKey: bank['icon_key'] as String?,
      status: json['status'] as String,
      programName: program['name'] as String? ?? '',
      completeness: json['completeness'] as String? ?? 'unknown',
      exclusion:
          exclusion == null ? null : MccExclusionModel.fromJson(exclusion),
      categories: (json['categories'] as List? ?? const [])
          .map((item) =>
              MccMatchedCategoryModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      offerIds: List<int>.from(json['offer_ids'] as List? ?? const []),
    );
  }
}

/// Answer to "where does this MCC earn": the code and every bank's verdict.
class MccLookupModel {
  const MccLookupModel(
      {required this.mcc,
      required this.banks,
      this.isFromCache = false,
      this.offerLinksCurrent = true,
      this.snapshotUpdatedAt,
      this.snapshotAsOf});

  final MccCodeModel mcc;
  final List<MccBankRuleModel> banks;
  final bool isFromCache;

  /// False when saved rules cannot establish the current card offer links.
  final bool offerLinksCurrent;
  final DateTime? snapshotUpdatedAt;
  final DateTime? snapshotAsOf;

  factory MccLookupModel.fromJson(Map<String, dynamic> json) => MccLookupModel(
        mcc: MccCodeModel.fromJson(json['mcc'] as Map<String, dynamic>),
        isFromCache: json['_cached'] as bool? ?? false,
        offerLinksCurrent: json['_offer_links_current'] as bool? ?? true,
        snapshotUpdatedAt:
            DateTime.tryParse(json['_updated_at'] as String? ?? ''),
        snapshotAsOf: DateTime.tryParse(json['_as_of'] as String? ?? ''),
        banks: (json['banks'] as List? ?? const [])
            .map((item) =>
                MccBankRuleModel.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

/// The published bank category behind one card offer.
class OfferMccRulesModel {
  const OfferMccRulesModel({
    required this.programName,
    required this.categoryName,
    required this.kind,
    required this.completeness,
    required this.included,
    required this.excluded,
    required this.exclusions,
    required this.validFrom,
    this.validTo,
    this.isFromCache = false,
    this.snapshotUpdatedAt,
    this.snapshotAsOf,
  });

  final String programName;
  final String categoryName;
  final String kind;
  final String completeness;
  final List<MccCodeModel> included;
  final List<MccCodeModel> excluded;

  /// Program-wide exclusions; [MccExclusionModel.title] names the code.
  final List<MccExclusionModel> exclusions;
  final DateTime validFrom;
  final DateTime? validTo;
  final bool isFromCache;
  final DateTime? snapshotUpdatedAt;
  final DateTime? snapshotAsOf;

  factory OfferMccRulesModel.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>;
    final program = json['program'] as Map<String, dynamic>;
    List<MccCodeModel> codes(String key) => (category[key] as List? ?? [])
        .map((item) => MccCodeModel.fromJson(item as Map<String, dynamic>))
        .toList();
    return OfferMccRulesModel(
      isFromCache: json['_cached'] as bool? ?? false,
      snapshotUpdatedAt:
          DateTime.tryParse(json['_updated_at'] as String? ?? ''),
      snapshotAsOf: DateTime.tryParse(json['_as_of'] as String? ?? ''),
      programName: program['name'] as String,
      categoryName: category['name'] as String,
      kind: category['kind'] as String? ?? 'mcc',
      completeness: category['completeness'] as String? ?? 'unknown',
      included: codes('included'),
      excluded: codes('excluded'),
      exclusions: (json['exclusions'] as List? ?? const [])
          .map((item) =>
              MccExclusionModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      validFrom: DateTime.parse(json['valid_from'] as String),
      validTo: json['valid_to'] == null
          ? null
          : DateTime.parse(json['valid_to'] as String),
    );
  }
}

/// Short Russian label of an exclusion kind.
String mccExclusionKindLabel(String kind) => switch (kind) {
      'always' => 'Кешбэк не начисляется',
      'unless_category' => 'Только в категории, где код указан',
      'conditional' => 'Начисляется при условии',
      _ => kind,
    };

class BankModel {
  final int? id;
  final String? name;
  final String? description;
  final String? iconKey;

  BankModel({this.id, this.name, this.description, this.iconKey});

  factory BankModel.fromJson(Map<String, dynamic> json) {
    return BankModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      iconKey: json['icon_key'] as String?,
    );
  }

  static Map<String, dynamic> toJson(BankModel model) {
    final jsonMap = {
      if (model.id != null) 'id': model.id,
      if (model.name != null) 'name': model.name,
      if (model.description != null) 'description': model.description,
      if (model.iconKey != null) 'icon_key': model.iconKey,
    };
    return jsonMap;
  }
}

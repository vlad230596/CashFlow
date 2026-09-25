class UserModel {
  final int id;
  final String name;
  final String? iconKey;

  UserModel({required this.id, required this.name, this.iconKey});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
      iconKey: json['icon_key'] as String?,
    );
  }

  static Map<String, dynamic> toJson(UserModel model) {
    final jsonMap = {
      'id': model.id,
      'name': model.name,
      if (model.iconKey != null) 'icon_key': model.iconKey,
    };
    return jsonMap;
  }
}

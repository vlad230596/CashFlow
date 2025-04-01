class UserModel {
  final int id;
  final String name;

  UserModel({required this.id, required this.name});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  static Map<String, dynamic> toJson(UserModel model) {
    final jsonMap = {
      if (model.id != null) 'id': model.id,
      if (model.name != null) 'name': model.name,
    };
    return jsonMap;
  }
}

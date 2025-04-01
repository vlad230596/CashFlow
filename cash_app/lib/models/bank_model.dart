import 'dart:convert';

class BankModel {
  final int? id;
  final String? name;
  final String? description;

  BankModel({this.id, this.name, this.description});

  factory BankModel.fromJson(Map<String, dynamic> json) {
    return BankModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }

  static Map<String, dynamic> toJson(BankModel model) {
    final jsonMap = {
      if (model.id != null) 'id': model.id,
      if (model.name != null) 'name': model.name,
      if (model.description != null) 'description': model.description,
    };
    return jsonMap;
  }
}

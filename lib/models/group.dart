import 'package:json_annotation/json_annotation.dart';

part 'group.g.dart';

@JsonSerializable(explicitToJson: true)
class Group {
  final String id;
  final String name;
  final String ownerUserId;
  final List<GroupMember> members;

  Group({required this.id, required this.name, required this.ownerUserId, required this.members});

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);
  Map<String, dynamic> toJson() => _$GroupToJson(this);
}

@JsonSerializable()
class GroupMember {
  final String id;
  final String displayName;
  final int? age;
  final String? relation;

  GroupMember({required this.id, required this.displayName, this.age, this.relation});

  factory GroupMember.fromJson(Map<String, dynamic> json) => _$GroupMemberFromJson(json);
  Map<String, dynamic> toJson() => _$GroupMemberToJson(this);
}

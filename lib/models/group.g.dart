// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Group _$GroupFromJson(Map<String, dynamic> json) => Group(
  id: json['id'] as String,
  name: json['name'] as String,
  ownerUserId: json['ownerUserId'] as String,
  members: (json['members'] as List<dynamic>)
      .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$GroupToJson(Group instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'ownerUserId': instance.ownerUserId,
  'members': instance.members.map((e) => e.toJson()).toList(),
};

GroupMember _$GroupMemberFromJson(Map<String, dynamic> json) => GroupMember(
  id: json['id'] as String,
  displayName: json['displayName'] as String,
  age: (json['age'] as num?)?.toInt(),
  relation: json['relation'] as String?,
);

Map<String, dynamic> _$GroupMemberToJson(GroupMember instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'age': instance.age,
      'relation': instance.relation,
    };

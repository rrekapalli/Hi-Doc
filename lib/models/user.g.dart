// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: (json['id'] as num?)?.toInt(),
  uid: json['uid'] as String,
  email: json['email'] as String,
  displayName: json['displayName'] as String,
  photoUrl: json['photoUrl'] as String?,
  givenName: json['givenName'] as String?,
  surname: json['surname'] as String?,
  provider: json['provider'] as String,
  tenantId: json['tenantId'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  lastLoginAt: json['lastLoginAt'] == null
      ? null
      : DateTime.parse(json['lastLoginAt'] as String),
  isActive: json['isActive'] as bool? ?? true,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'uid': instance.uid,
  'email': instance.email,
  'displayName': instance.displayName,
  'photoUrl': instance.photoUrl,
  'givenName': instance.givenName,
  'surname': instance.surname,
  'provider': instance.provider,
  'tenantId': instance.tenantId,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastLoginAt': instance.lastLoginAt?.toIso8601String(),
  'isActive': instance.isActive,
  'metadata': instance.metadata,
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Report _$ReportFromJson(Map<String, dynamic> json) => Report(
      id: json['id'] as String,
      userId: json['user_id'] as String,
  profileId: json['profile_id'] as String? ?? json['conversation_id'] as String?,
      filePath: json['file_path'] as String,
      fileType: $enumDecode(_$ReportFileTypeEnumMap, json['file_type']),
      source: $enumDecode(_$ReportSourceEnumMap, json['source']),
      aiSummary: json['ai_summary'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      parsed: json['parsed'] as bool? ?? false,
      originalFileName: json['original_file_name'] as String?,
    );

Map<String, dynamic> _$ReportToJson(Report instance) => <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
  'profile_id': instance.profileId,
      'file_path': instance.filePath,
      'file_type': _$ReportFileTypeEnumMap[instance.fileType]!,
      'source': _$ReportSourceEnumMap[instance.source]!,
      'ai_summary': instance.aiSummary,
      'created_at': instance.createdAt.toIso8601String(),
      'parsed': instance.parsed,
      'original_file_name': instance.originalFileName,
    };

const _$ReportFileTypeEnumMap = {
  ReportFileType.pdf: 'pdf',
  ReportFileType.image: 'image',
  ReportFileType.unknown: 'unknown',
};

const _$ReportSourceEnumMap = {
  ReportSource.camera: 'camera',
  ReportSource.upload: 'upload',
  ReportSource.profile: 'profile',
};

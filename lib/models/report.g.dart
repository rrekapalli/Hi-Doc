// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Report _$ReportFromJson(Map<String, dynamic> json) => Report(
      id: json['id'] as String,
      userId: json['userId'] as String,
      conversationId: json['conversationId'] as String?,
      filePath: json['filePath'] as String,
      fileType: $enumDecode(_$ReportFileTypeEnumMap, json['fileType']),
      source: $enumDecode(_$ReportSourceEnumMap, json['source']),
      aiSummary: json['aiSummary'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      parsed: json['parsed'] as bool? ?? false,
      originalFileName: json['originalFileName'] as String?,
    );

Map<String, dynamic> _$ReportToJson(Report instance) => <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'conversationId': instance.conversationId,
      'filePath': instance.filePath,
      'fileType': _$ReportFileTypeEnumMap[instance.fileType]!,
      'source': _$ReportSourceEnumMap[instance.source]!,
      'aiSummary': instance.aiSummary,
      'createdAt': instance.createdAt.toIso8601String(),
      'parsed': instance.parsed,
      'originalFileName': instance.originalFileName,
    };

const _$ReportFileTypeEnumMap = {
  ReportFileType.pdf: 'pdf',
  ReportFileType.image: 'image',
  ReportFileType.unknown: 'unknown',
};

const _$ReportSourceEnumMap = {
  ReportSource.camera: 'camera',
  ReportSource.upload: 'upload',
  ReportSource.conversation: 'conversation',
};

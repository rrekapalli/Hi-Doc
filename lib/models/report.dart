import 'package:json_annotation/json_annotation.dart';

part 'report.g.dart';

enum ReportSource { camera, upload, conversation }
enum ReportFileType { pdf, image, unknown }

@JsonSerializable()
class Report {
  final String id;
  final String userId;
  final String? conversationId;
  final String filePath;
  final ReportFileType fileType;
  final ReportSource source;
  final String? aiSummary;
  final DateTime createdAt;
  final bool parsed;
  final String? originalFileName;

  const Report({
    required this.id,
    required this.userId,
    this.conversationId,
    required this.filePath,
    required this.fileType,
    required this.source,
    this.aiSummary,
    required this.createdAt,
    this.parsed = false,
    this.originalFileName,
  });

  factory Report.fromJson(Map<String, dynamic> json) => _$ReportFromJson(json);
  Map<String, dynamic> toJson() => _$ReportToJson(this);

  Report copyWith({
    String? id,
    String? userId,
    String? conversationId,
    String? filePath,
    ReportFileType? fileType,
    ReportSource? source,
    String? aiSummary,
    DateTime? createdAt,
    bool? parsed,
    String? originalFileName,
  }) {
    return Report(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      conversationId: conversationId ?? this.conversationId,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      source: source ?? this.source,
      aiSummary: aiSummary ?? this.aiSummary,
      createdAt: createdAt ?? this.createdAt,
      parsed: parsed ?? this.parsed,
      originalFileName: originalFileName ?? this.originalFileName,
    );
  }

  String get displayName {
    if (originalFileName != null && originalFileName!.isNotEmpty) {
      return originalFileName!;
    }
    
    final fileName = filePath.split('/').last;
    if (fileName.length > 20) {
      final extension = fileName.contains('.') ? fileName.split('.').last : '';
      final name = fileName.substring(0, 15);
      return '$name...$extension';
    }
    return fileName;
  }

  String get typeIcon {
    switch (fileType) {
      case ReportFileType.pdf:
        return '📄';
      case ReportFileType.image:
        return '🖼️';
      case ReportFileType.unknown:
        return '📁';
    }
  }

  String get sourceIcon {
    switch (source) {
      case ReportSource.camera:
        return '📷';
      case ReportSource.upload:
        return '📂';
      case ReportSource.conversation:
        return '💬';
    }
  }
}

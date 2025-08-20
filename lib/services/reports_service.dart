import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../models/report.dart';
import '../models/health_data_entry.dart';
import '../config/app_config.dart';

class ReportsService {
  static const uuid = Uuid();

  /// Get the app's documents directory for storing report files
  Future<Directory> _getReportsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(path.join(appDir.path, 'reports'));
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir;
  }

  /// Save a file to the reports directory and return the local path
  Future<String> saveReportFile(File sourceFile, {String? fileName}) async {
    final reportsDir = await _getReportsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(sourceFile.path);
    final finalFileName = fileName ?? 'report_${timestamp}$extension';
    
    final targetPath = path.join(reportsDir.path, finalFileName);
    final targetFile = await sourceFile.copy(targetPath);
    
    return targetFile.path;
  }

  /// Determine file type from extension
  ReportFileType _getFileType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.pdf':
        return ReportFileType.pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return ReportFileType.image;
      default:
        return ReportFileType.unknown;
    }
  }

  /// Create a new report record
  Future<Report> createReport({
    required String userId,
    required String filePath,
    required ReportSource source,
    String? conversationId,
    String? aiSummary,
    String? originalFileName,
  }) async {
    try {
      final report = Report(
        id: uuid.v4(),
        userId: userId,
        conversationId: conversationId,
        filePath: filePath,
        fileType: _getFileType(filePath),
        source: source,
        aiSummary: aiSummary,
        createdAt: DateTime.now(),
        parsed: false,
        originalFileName: originalFileName,
      );

      // Save to backend
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id': report.id,
          'user_id': report.userId,
          'conversation_id': report.conversationId,
          'file_path': report.filePath,
          'file_type': report.fileType.name,
          'source': report.source.name,
          'ai_summary': report.aiSummary,
          'created_at': report.createdAt.millisecondsSinceEpoch,
          'parsed': report.parsed ? 1 : 0,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Report created successfully: ${report.id}');
        return report;
      } else {
        throw Exception('Failed to create report: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating report: $e');
      rethrow;
    }
  }

  /// Get all reports for a user
  Future<List<Report>> getUserReports(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> reportsJson = jsonDecode(response.body);
        return reportsJson.map((json) => _reportFromBackendJson(json)).toList();
      } else {
        throw Exception('Failed to fetch reports: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      return [];
    }
  }

  /// Get a specific report by ID
  Future<Report?> getReport(String reportId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return _reportFromBackendJson(json);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to fetch report: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching report $reportId: $e');
      return null;
    }
  }

  /// Delete a report
  Future<bool> deleteReport(String reportId) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        // Also try to delete the local file
        try {
          final report = await getReport(reportId);
          if (report != null) {
            final file = File(report.filePath);
            if (await file.exists()) {
              await file.delete();
            }
          }
        } catch (e) {
          debugPrint('Could not delete local file: $e');
        }
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('Error deleting report $reportId: $e');
      return false;
    }
  }

  /// Parse a report using OCR and AI
  Future<List<HealthDataEntry>> parseReport(String reportId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId/parse'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> healthDataList = json['health_data'] ?? [];
        return healthDataList.map((item) => HealthDataEntry.fromJson(item)).toList();
      } else {
        throw Exception('Failed to parse report: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error parsing report $reportId: $e');
      return [];
    }
  }

  /// Update report's AI summary
  Future<bool> updateAiSummary(String reportId, String aiSummary) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ai_summary': aiSummary,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating report summary: $e');
      return false;
    }
  }

  /// Mark report as parsed
  Future<bool> markAsParsed(String reportId) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'parsed': 1,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error marking report as parsed: $e');
      return false;
    }
  }

  /// Convert backend JSON to Report model
  Report _reportFromBackendJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'],
      userId: json['user_id'],
      conversationId: json['conversation_id'],
      filePath: json['file_path'],
      fileType: _parseFileType(json['file_type']),
      source: _parseSource(json['source']),
      aiSummary: json['ai_summary'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['created_at'] is String 
          ? int.parse(json['created_at'])
          : json['created_at'] ?? DateTime.now().millisecondsSinceEpoch
      ),
      parsed: json['parsed'] == 1 || json['parsed'] == true,
    );
  }

  ReportFileType _parseFileType(String? type) {
    if (type == null) return ReportFileType.unknown;
    try {
      return ReportFileType.values.firstWhere((e) => e.name == type);
    } catch (e) {
      return ReportFileType.unknown;
    }
  }

  ReportSource _parseSource(String? source) {
    if (source == null) return ReportSource.upload;
    try {
      return ReportSource.values.firstWhere((e) => e.name == source);
    } catch (e) {
      return ReportSource.upload;
    }
  }
}

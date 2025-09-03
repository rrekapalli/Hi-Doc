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
import 'auth_service.dart';

class ReportsService {
  static const uuid = Uuid();

  /// Get authentication headers for API requests
  Future<Map<String, String>> _getAuthHeaders() async {
    final authService = AuthService();
    final token = await authService.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
  }

  /// Get authentication headers for multipart uploads
  Future<Map<String, String>> _getUploadHeaders() async {
    final authService = AuthService();
    final token = await authService.getIdToken();
    return {
      'Authorization': 'Bearer $token'
    };
  }

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
  final finalFileName = fileName ?? 'report_$timestamp$extension';
    
    final targetPath = path.join(reportsDir.path, finalFileName);
    final targetFile = await sourceFile.copy(targetPath);
    
    return targetFile.path;
  }

  /// Fetch file data from the backend for display
  Future<Uint8List?> getReportFileData(String filePath) async {
    try {
      // Extract filename from full path
      final fileName = path.basename(filePath);
      final headers = await _getUploadHeaders();
      
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/files/$fileName'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        debugPrint('Failed to fetch file. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching file: $e');
      return null;
    }
  }


  /// Create a new report on the backend
  Future<Report> createReport(Report report) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports'),
        headers: headers,
        body: jsonEncode({
          'id': report.id,
          'user_id': report.userId,
          'profile_id': report.profileId,
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
        debugPrint('Failed to create report. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to create report: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating report: $e');
      debugPrint('Backend URL: ${AppConfig.backendBaseUrl}/api/reports');
      rethrow;
    }
  }

  /// Upload a file directly to the backend and create a report
  Future<Report> uploadReportFile({
    required File file,
    required String userId,
    required ReportSource source,
  String? profileId,
    String? aiSummary,
  }) async {
    try {
      final headers = await _getUploadHeaders();
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/reports/upload');
      
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: path.basename(file.path),
      ));
      
      // Add additional fields
      request.fields['source'] = source.name;
  request.fields['profile_id'] = profileId ?? 'default-profile';
      if (aiSummary != null) {
        request.fields['ai_summary'] = aiSummary;
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 201) {
        final json = jsonDecode(responseBody);
        debugPrint('File uploaded successfully: ${json['id']}');
        return _reportFromBackendJson(json);
      } else {
        debugPrint('Failed to upload file. Status: ${response.statusCode}, Body: $responseBody');
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      debugPrint('Backend URL: ${AppConfig.backendBaseUrl}/api/reports/upload');
      rethrow;
    }
  }

  /// Upload file bytes directly to the backend (for web)
  Future<Report> uploadReportBytes({
    required Uint8List bytes,
    required String fileName,
    required String userId,
    required ReportSource source,
  String? profileId,
    String? aiSummary,
  }) async {
    try {
      final headers = await _getUploadHeaders();
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/reports/upload');
      
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);
      
      // Add file bytes
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ));
      
      // Add additional fields
      request.fields['source'] = source.name;
  request.fields['profile_id'] = profileId ?? 'default-profile';
      if (aiSummary != null) {
        request.fields['ai_summary'] = aiSummary;
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 201) {
        final json = jsonDecode(responseBody);
        debugPrint('File uploaded successfully: ${json['id']}');
        return _reportFromBackendJson(json);
      } else {
        debugPrint('Failed to upload file. Status: ${response.statusCode}, Body: $responseBody');
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading file: $e');
      debugPrint('Backend URL: ${AppConfig.backendBaseUrl}/api/reports/upload');
      rethrow;
    }
  }

  /// Get all reports for a user
  Future<List<Report>> getUserReports(String userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> reportsJson = jsonDecode(response.body);
        return reportsJson.map((json) => _reportFromBackendJson(json)).toList();
      } else {
        debugPrint('Failed to fetch reports. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to fetch reports: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      debugPrint('Backend URL: ${AppConfig.backendBaseUrl}/api/reports');
      rethrow; // Re-throw the error so provider can handle it
    }
  }

  /// Get a specific report by ID
  Future<Report?> getReport(String reportId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: headers,
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
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: headers,
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
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId/parse'),
        headers: headers,
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
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: headers,
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
      final headers = await _getAuthHeaders();
      final response = await http.patch(
        Uri.parse('${AppConfig.backendBaseUrl}/api/reports/$reportId'),
        headers: headers,
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
    final filePath = json['file_path']?.toString();
    final originalName = (json['original_file_name'] ?? json['original_name'])?.toString();
    final typeStr = json['file_type']?.toString();

    return Report(
      id: json['id'],
      userId: json['user_id'],
      profileId: json['profile_id'],
      filePath: filePath ?? '',
      fileType: _parseFileType(typeStr, filePath: filePath, originalName: originalName),
      source: _parseSource(json['source']),
      aiSummary: json['ai_summary'],
      createdAt: _parseDateTime(json['created_at']),
      parsed: json['parsed'] == 1 || json['parsed'] == true,
      originalFileName: originalName,
    );
  }

  DateTime _parseDateTime(dynamic dateValue) {
    if (dateValue == null) {
      return DateTime.now();
    }
    
    if (dateValue is String) {
      // Try parsing as ISO string first
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        // If ISO parsing fails, try parsing as timestamp string
        try {
          return DateTime.fromMillisecondsSinceEpoch(int.parse(dateValue));
        } catch (e) {
          debugPrint('Failed to parse date string: $dateValue');
          return DateTime.now();
        }
      }
    } else if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    } else {
      debugPrint('Unknown date format: $dateValue (${dateValue.runtimeType})');
      return DateTime.now();
    }
  }

  ReportFileType _parseFileType(String? type, {String? filePath, String? originalName}) {
    // Normalize
    final t = type?.toLowerCase().trim();

    // 1) Direct enum names from older clients
    if (t == 'pdf') return ReportFileType.pdf;
    if (t == 'image') return ReportFileType.image;

    // 2) Common MIME types from backend (multer)
    if (t != null) {
      if (t == 'application/pdf' || t.endsWith('/pdf')) return ReportFileType.pdf;
      if (t.startsWith('image/')) return ReportFileType.image;
    }

    // 3) Fallback to extension from original name or stored path
    final candidate = (originalName?.isNotEmpty == true ? originalName : filePath) ?? '';
    if (candidate.isNotEmpty) {
      final ext = path.extension(candidate).toLowerCase();
      switch (ext) {
        case '.pdf':
          return ReportFileType.pdf;
        case '.jpg':
        case '.jpeg':
        case '.png':
        case '.gif':
        case '.bmp':
        case '.webp':
          return ReportFileType.image;
      }
    }

    return ReportFileType.unknown;
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

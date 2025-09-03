import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import '../models/report.dart';
import '../services/reports_service.dart';

class ReportsProvider with ChangeNotifier {
  final ReportsService _reportsService = ReportsService();
  static const _uuid = Uuid();
  
  List<Report> _reports = [];
  bool _isLoading = false;
  String? _error;

  List<Report> get reports => [..._reports];
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load reports for the current user
  Future<void> loadReports(String userId) async {
    if (_isLoading) return; // Prevent multiple simultaneous loads
    
    _setLoading(true);
    _error = null;
    
    try {
      _reports = await _reportsService.getUserReports(userId);
      if (kDebugMode) {
        debugPrint('Loaded ${_reports.length} reports for user $userId');
      }
    } catch (e) {
      _error = 'Failed to load reports: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Add a new report
  Future<Report?> addReport({
    required String userId,
    required String filePath,
    required ReportSource source,
  String? profileId,
    String? aiSummary,
    String? originalFileName,
  }) async {
    _error = null;
    
    try {
      // Determine file type from file path
      final fileType = _getFileTypeFromPath(filePath);
      
      // Create Report object
      final report = Report(
        id: _generateId(),
        userId: userId,
  profileId: profileId,
        filePath: filePath,
        fileType: fileType,
        source: source,
        aiSummary: aiSummary,
        createdAt: DateTime.now(),
        parsed: false,
        originalFileName: originalFileName,
      );
      
      // Create report on backend
      final createdReport = await _reportsService.createReport(report);
      
      _reports.insert(0, createdReport); // Add to beginning of list
      notifyListeners();
      return createdReport;
    } catch (e) {
      _error = 'Failed to add report: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
      notifyListeners();
      return null;
    }
  }

  /// Add a new report by uploading a file directly to the backend
  Future<Report?> addReportByUpload({
    required File file,
    required String userId,
    required ReportSource source,
  String? profileId,
    String? aiSummary,
  }) async {
    _error = null;
    
    try {
      // Upload file directly to backend
      final createdReport = await _reportsService.uploadReportFile(
        file: file,
        userId: userId,
        source: source,
  profileId: profileId,
        aiSummary: aiSummary,
      );
      
      _reports.insert(0, createdReport); // Add to beginning of list
      notifyListeners();
      return createdReport;
    } catch (e) {
      _error = 'Failed to upload report: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
      notifyListeners();
      return null;
    }
  }

  /// Add a new report by uploading file bytes directly to the backend (for web)
  Future<Report?> addReportByUploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String userId,
    required ReportSource source,
  String? profileId,
    String? aiSummary,
  }) async {
    _error = null;
    
    try {
      // Upload file bytes directly to backend
      final createdReport = await _reportsService.uploadReportBytes(
        bytes: bytes,
        fileName: fileName,
        userId: userId,
        source: source,
  profileId: profileId,
        aiSummary: aiSummary,
      );
      
      _reports.insert(0, createdReport); // Add to beginning of list
      notifyListeners();
      return createdReport;
    } catch (e) {
      _error = 'Failed to upload report: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
      notifyListeners();
      return null;
    }
  }

  /// Remove a report
  Future<bool> removeReport(String reportId) async {
    _error = null;
    
    try {
      final success = await _reportsService.deleteReport(reportId);
      if (success) {
        _reports.removeWhere((report) => report.id == reportId);
        notifyListeners();
        return true;
      } else {
        _error = 'Failed to delete report';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to delete report: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
      notifyListeners();
      return false;
    }
  }

  /// Update a report's AI summary
  Future<bool> updateReportSummary(String reportId, String aiSummary) async {
    _error = null;
    
    try {
      final success = await _reportsService.updateAiSummary(reportId, aiSummary);
      if (success) {
        final index = _reports.indexWhere((report) => report.id == reportId);
        if (index != -1) {
          _reports[index] = _reports[index].copyWith(aiSummary: aiSummary);
          notifyListeners();
        }
        return true;
      } else {
        _error = 'Failed to update report summary';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to update report summary: $e';
      debugPrint(_error);
      notifyListeners();
      return false;
    }
  }

  /// Mark a report as parsed
  Future<bool> markReportAsParsed(String reportId) async {
    _error = null;
    
    try {
      final success = await _reportsService.markAsParsed(reportId);
      if (success) {
        final index = _reports.indexWhere((report) => report.id == reportId);
        if (index != -1) {
          _reports[index] = _reports[index].copyWith(parsed: true);
          notifyListeners();
        }
        return true;
      } else {
        _error = 'Failed to mark report as parsed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to mark report as parsed: $e';
      debugPrint(_error);
      notifyListeners();
      return false;
    }
  }

  /// Get a specific report by ID
  Report? getReportById(String reportId) {
    try {
      return _reports.firstWhere((report) => report.id == reportId);
    } catch (e) {
      return null;
    }
  }

  /// Filter reports by source
  List<Report> getReportsBySource(ReportSource source) {
    return _reports.where((report) => report.source == source).toList();
  }

  /// Filter reports by file type
  List<Report> getReportsByFileType(ReportFileType fileType) {
    return _reports.where((report) => report.fileType == fileType).toList();
  }

  /// Get parsed reports only
  List<Report> getParsedReports() {
    return _reports.where((report) => report.parsed).toList();
  }

  /// Get unparsed reports only
  List<Report> getUnparsedReports() {
    return _reports.where((report) => !report.parsed).toList();
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  /// Generate a unique ID for a new report
  String _generateId() {
    return _uuid.v4();
  }
  
  /// Determine file type from file path extension
  ReportFileType _getFileTypeFromPath(String filePath) {
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
}

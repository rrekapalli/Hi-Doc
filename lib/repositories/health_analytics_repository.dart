import 'dart:convert';
import '../models/health_entry.dart';
import '../repositories/base_repository_impl.dart';
import '../services/trend_analysis_service.dart';
import '../services/insight_generation_service.dart';

/// Repository for storing and retrieving health analytics data
class HealthAnalyticsRepository
    extends UserScopedRepositoryImpl<HealthAnalytic> {
  HealthAnalyticsRepository({required super.localDb})
    : super(tableName: 'health_analytics');

  @override
  Map<String, dynamic> entityToMap(HealthAnalytic entity) => {
    'id': entity.id,
    'user_id': entity.userId,
    'person_id': entity.personId,
    'vital_type': entity.vitalType?.name,
    'analysis_type': entity.analysisType.name,
    'start_date': entity.startDate.millisecondsSinceEpoch,
    'end_date': entity.endDate.millisecondsSinceEpoch,
    'data': jsonEncode(entity.data),
    'insights': jsonEncode(entity.insights),
    'recommendations': jsonEncode(entity.recommendations),
    'risk_level': entity.riskLevel?.name,
    'generated_at': entity.generatedAt.millisecondsSinceEpoch,
  };

  @override
  HealthAnalytic mapToEntity(Map<String, dynamic> map) {
    return HealthAnalytic(
      id: map['id'],
      userId: map['user_id'],
      personId: map['person_id'],
      vitalType: map['vital_type'] != null
          ? VitalType.values.firstWhere((v) => v.name == map['vital_type'])
          : null,
      analysisType: AnalysisType.values.firstWhere(
        (t) => t.name == map['analysis_type'],
      ),
      startDate: DateTime.fromMillisecondsSinceEpoch(map['start_date']),
      endDate: DateTime.fromMillisecondsSinceEpoch(map['end_date']),
      data: jsonDecode(map['data']),
      insights: List<String>.from(jsonDecode(map['insights'])),
      recommendations: List<String>.from(jsonDecode(map['recommendations'])),
      riskLevel: map['risk_level'] != null
          ? RiskLevel.values.firstWhere((r) => r.name == map['risk_level'])
          : null,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(map['generated_at']),
    );
  }

  /// Store trend analysis result
  Future<void> storeTrendAnalysis({
    required String userId,
    required VitalTrendAnalysis analysis,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
  }) async {
    final analytic = HealthAnalytic(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      personId: personId,
      vitalType: analysis.vitalType,
      analysisType: AnalysisType.trendAnalysis,
      startDate: startDate,
      endDate: endDate,
      data: {
        'average_value': analysis.averageValue,
        'min_value': analysis.minValue,
        'max_value': analysis.maxValue,
        'change_percent': analysis.changePercent,
        'trend_direction': analysis.trend.name,
        'data_quality': analysis.dataQuality.name,
        'data_point_count': analysis.dataPoints.length,
      },
      insights: [],
      recommendations: [],
      riskLevel: null,
      generatedAt: DateTime.now(),
    );

    await create(analytic);
  }

  /// Store vital insight result
  Future<void> storeVitalInsight({
    required String userId,
    required VitalInsight insight,
  }) async {
    final analytic = HealthAnalytic(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      personId: null, // Will be extracted from trend analysis if needed
      vitalType: insight.vitalType,
      analysisType: AnalysisType.vitalInsight,
      startDate: insight.trendAnalysis.dataPoints.isEmpty
          ? DateTime.now().subtract(const Duration(days: 30))
          : insight.trendAnalysis.dataPoints.first.timestamp,
      endDate: insight.trendAnalysis.dataPoints.isEmpty
          ? DateTime.now()
          : insight.trendAnalysis.dataPoints.last.timestamp,
      data: {
        'average_value': insight.trendAnalysis.averageValue,
        'trend_direction': insight.trendAnalysis.trend.name,
        'data_quality': insight.trendAnalysis.dataQuality.name,
        'change_percent': insight.trendAnalysis.changePercent,
      },
      insights: insight.insights,
      recommendations: insight.recommendations,
      riskLevel: insight.riskLevel,
      generatedAt: insight.generatedAt,
    );

    await create(analytic);
  }

  /// Store health insight report
  Future<void> storeHealthInsightReport({
    required String userId,
    required HealthInsightReport report,
  }) async {
    final analytic = HealthAnalytic(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      personId: report.personId,
      vitalType: null,
      analysisType: AnalysisType.healthReport,
      startDate: report.startDate,
      endDate: report.endDate,
      data: {
        'total_entries': report.overview.totalEntries,
        'medication_count': report.overview.medicationCount,
        'lab_result_count': report.overview.labResultCount,
        'vital_insights_count': report.vitalInsights.length,
        'frequent_medications': report.overview.frequentMedications,
        'recent_lab_parameters': report.overview.recentLabParameters,
      },
      insights: report.overallInsights,
      recommendations: [], // Overall recommendations could be added
      riskLevel: report.overallRisk,
      generatedAt: report.generatedAt,
    );

    await create(analytic);
  }

  /// Get recent analytics for a user
  Future<List<HealthAnalytic>> getRecentAnalytics({
    required String userId,
    String? personId,
    int limit = 20,
  }) async {
    final results = await findByUserId(userId);

    var filtered = personId != null
        ? results.where((a) => a.personId == personId).toList()
        : results;

    // Sort by generated date, most recent first
    filtered.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

    return filtered.take(limit).toList();
  }

  /// Get analytics for a specific vital type
  Future<List<HealthAnalytic>> getVitalAnalytics({
    required String userId,
    required VitalType vitalType,
    String? personId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final results = await findByUserId(userId);

    return results.where((a) {
      if (a.vitalType != vitalType) return false;
      if (personId != null && a.personId != personId) return false;
      if (startDate != null && a.endDate.isBefore(startDate)) return false;
      if (endDate != null && a.startDate.isAfter(endDate)) return false;
      return true;
    }).toList();
  }

  /// Get latest health report for a user
  Future<HealthAnalytic?> getLatestHealthReport({
    required String userId,
    String? personId,
  }) async {
    final results = await findByUserId(userId);

    final reports = results.where((a) {
      if (a.analysisType != AnalysisType.healthReport) return false;
      if (personId != null && a.personId != personId) return false;
      return true;
    }).toList();

    if (reports.isEmpty) return null;

    reports.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return reports.first;
  }

  /// Delete old analytics to maintain performance
  Future<void> cleanupOldAnalytics({
    required String userId,
    Duration retentionPeriod = const Duration(days: 90),
  }) async {
    final cutoffDate = DateTime.now().subtract(retentionPeriod);
    final results = await findByUserId(userId);

    final toDelete = results
        .where((a) => a.generatedAt.isBefore(cutoffDate))
        .toList();

    for (final analytic in toDelete) {
      await delete(analytic.id);
    }
  }
}

/// Health analytic data model
class HealthAnalytic {
  final String id;
  final String userId;
  final String? personId;
  final VitalType? vitalType;
  final AnalysisType analysisType;
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, dynamic> data;
  final List<String> insights;
  final List<String> recommendations;
  final RiskLevel? riskLevel;
  final DateTime generatedAt;

  HealthAnalytic({
    required this.id,
    required this.userId,
    this.personId,
    this.vitalType,
    required this.analysisType,
    required this.startDate,
    required this.endDate,
    required this.data,
    required this.insights,
    required this.recommendations,
    this.riskLevel,
    required this.generatedAt,
  });
}

/// Types of analytics supported
enum AnalysisType { trendAnalysis, vitalInsight, healthReport }

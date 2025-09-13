import '../services/trend_analysis_service.dart';
import '../services/insight_generation_service.dart';
import '../repositories/health_analytics_repository.dart';
import '../repositories/repository_manager.dart';
import '../models/health_entry.dart';

/// Service for integrating health analytics components
class HealthAnalyticsIntegrationService {
  final InsightGenerationService _insightService;
  final HealthAnalyticsRepository _analyticsRepository;

  HealthAnalyticsIntegrationService({
    InsightGenerationService? insightService,
    HealthAnalyticsRepository? analyticsRepository,
  }) : _insightService = insightService ?? InsightGenerationService(),
       _analyticsRepository =
           analyticsRepository ??
           RepositoryManager.instance.healthAnalyticsRepository;

  /// Generate and store comprehensive health analytics
  Future<HealthInsightReport> generateAndStoreHealthAnalytics({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
    bool storeResults = true,
  }) async {
    // Generate comprehensive health report
    final healthReport = await _insightService.generateHealthReport(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      personId: personId,
    );

    if (storeResults) {
      // Store the main health report
      await _analyticsRepository.storeHealthInsightReport(
        userId: userId,
        report: healthReport,
      );

      // Store individual vital insights
      for (final vitalInsight in healthReport.vitalInsights) {
        await _analyticsRepository.storeVitalInsight(
          userId: userId,
          insight: vitalInsight,
        );

        // Store trend analysis data
        await _analyticsRepository.storeTrendAnalysis(
          userId: userId,
          analysis: vitalInsight.trendAnalysis,
          startDate: startDate,
          endDate: endDate,
          personId: personId,
        );
      }
    }

    return healthReport;
  }

  /// Get cached analytics with fallback to generation
  Future<HealthInsightReport> getCachedOrGenerateAnalytics({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
    Duration cacheValidityPeriod = const Duration(hours: 6),
  }) async {
    // Check for recent cached analytics
    final cachedReport = await _analyticsRepository.getLatestHealthReport(
      userId: userId,
      personId: personId,
    );

    if (cachedReport != null &&
        DateTime.now().difference(cachedReport.generatedAt) <
            cacheValidityPeriod) {
      // Return cached report if recent enough
      return _reconstructHealthReport(cachedReport, userId, personId);
    }

    // Generate fresh analytics
    return await generateAndStoreHealthAnalytics(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      personId: personId,
      storeResults: true,
    );
  }

  /// Validate trend analysis functionality with test data
  Future<bool> validateTrendAnalysisFunctionality({
    required String userId,
  }) async {
    try {
      // Test trend analysis with real service call
      final testStartDate = DateTime.now().subtract(const Duration(days: 7));
      final testEndDate = DateTime.now();

      // Test insight generation
      final testInsight = await _insightService.generateVitalInsight(
        userId: userId,
        vitalType: VitalType.glucose,
        startDate: testStartDate,
        endDate: testEndDate,
      );

      // Verify insights were generated (even if no data exists)
      if (testInsight.riskLevel == RiskLevel.unknown &&
          testInsight.trendAnalysis.dataQuality == DataQuality.insufficient) {
        // This is expected if no data exists - the service is working
        print('Validation passed: Service correctly handles no data scenario');
      }

      // Test analytics storage
      await _analyticsRepository.storeVitalInsight(
        userId: userId,
        insight: testInsight,
      );

      // Verify storage worked
      final storedAnalytics = await _analyticsRepository.getVitalAnalytics(
        userId: userId,
        vitalType: VitalType.glucose,
      );

      if (storedAnalytics.isEmpty) {
        throw Exception('Analytics not stored properly');
      }

      print('Trend analysis validation completed successfully');
      return true;
    } catch (e) {
      print('Trend analysis validation failed: $e');
      return false;
    }
  }

  /// Cleanup old analytics data
  Future<void> cleanupOldAnalytics({
    required String userId,
    Duration retentionPeriod = const Duration(days: 90),
  }) async {
    await _analyticsRepository.cleanupOldAnalytics(
      userId: userId,
      retentionPeriod: retentionPeriod,
    );
  }

  /// Get analytics summary for dashboard
  Future<Map<String, dynamic>> getAnalyticsSummary({
    required String userId,
    String? personId,
  }) async {
    final recentAnalytics = await _analyticsRepository.getRecentAnalytics(
      userId: userId,
      personId: personId,
      limit: 10,
    );

    final vitalCounts = <VitalType, int>{};
    int totalReports = 0;
    int highRiskCount = 0;

    for (final analytic in recentAnalytics) {
      if (analytic.analysisType == AnalysisType.healthReport) {
        totalReports++;
      } else if (analytic.vitalType != null) {
        vitalCounts[analytic.vitalType!] =
            (vitalCounts[analytic.vitalType!] ?? 0) + 1;
      }

      if (analytic.riskLevel == RiskLevel.high) {
        highRiskCount++;
      }
    }

    return {
      'total_analytics': recentAnalytics.length,
      'total_reports': totalReports,
      'vital_analytics_count': vitalCounts.length,
      'high_risk_count': highRiskCount,
      'most_analyzed_vitals': vitalCounts.entries
          .map((e) => {'vital': e.key.name, 'count': e.value})
          .toList(),
      'last_analysis_date': recentAnalytics.isNotEmpty
          ? recentAnalytics.first.generatedAt.toIso8601String()
          : null,
    };
  }

  /// Reconstruct health report from cached analytics
  Future<HealthInsightReport> _reconstructHealthReport(
    HealthAnalytic cachedReport,
    String userId,
    String? personId,
  ) async {
    // This is a simplified reconstruction - in a real implementation,
    // you would fully reconstruct the report from cached data
    final overview = HealthOverview(
      userId: userId,
      personId: personId,
      startDate: cachedReport.startDate,
      endDate: cachedReport.endDate,
      totalEntries: cachedReport.data['total_entries'] ?? 0,
      vitalTrends: {}, // Would be reconstructed from cached data
      medicationCount: cachedReport.data['medication_count'] ?? 0,
      labResultCount: cachedReport.data['lab_result_count'] ?? 0,
      frequentMedications: List<String>.from(
        cachedReport.data['frequent_medications'] ?? [],
      ),
      recentLabParameters: List<String>.from(
        cachedReport.data['recent_lab_parameters'] ?? [],
      ),
    );

    return HealthInsightReport(
      userId: userId,
      personId: personId,
      startDate: cachedReport.startDate,
      endDate: cachedReport.endDate,
      overview: overview,
      vitalInsights: [], // Would be reconstructed from cached data
      overallInsights: cachedReport.insights,
      overallRisk: cachedReport.riskLevel ?? RiskLevel.unknown,
      generatedAt: cachedReport.generatedAt,
    );
  }
}

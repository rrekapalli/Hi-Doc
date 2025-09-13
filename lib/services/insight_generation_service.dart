import '../models/health_entry.dart';
import 'trend_analysis_service.dart';

/// Service for generating health insights and recommendations based on trend analysis
class InsightGenerationService {
  final TrendAnalysisService _trendAnalysisService;

  InsightGenerationService({TrendAnalysisService? trendAnalysisService})
    : _trendAnalysisService = trendAnalysisService ?? TrendAnalysisService();

  /// Generate insights for a specific vital type
  Future<VitalInsight> generateVitalInsight({
    required String userId,
    required VitalType vitalType,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
  }) async {
    final trendAnalysis = await _trendAnalysisService.analyzeVitalTrend(
      userId: userId,
      vitalType: vitalType,
      startDate: startDate,
      endDate: endDate,
      personId: personId,
    );

    final insights = <String>[];
    final recommendations = <String>[];
    final riskLevel = _assessRiskLevel(vitalType, trendAnalysis);

    // Generate insights based on trend direction
    _generateTrendInsights(vitalType, trendAnalysis, insights, recommendations);

    // Generate range-based insights
    _generateRangeInsights(vitalType, trendAnalysis, insights, recommendations);

    // Generate data quality insights
    _generateDataQualityInsights(trendAnalysis, insights, recommendations);

    return VitalInsight(
      vitalType: vitalType,
      trendAnalysis: trendAnalysis,
      insights: insights,
      recommendations: recommendations,
      riskLevel: riskLevel,
      generatedAt: DateTime.now(),
    );
  }

  /// Generate comprehensive health report with insights
  Future<HealthInsightReport> generateHealthReport({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
  }) async {
    final overview = await _trendAnalysisService.getHealthOverview(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      personId: personId,
    );

    final vitalInsights = <VitalInsight>[];
    for (final vitalType in overview.vitalTrends.keys) {
      final insight = await generateVitalInsight(
        userId: userId,
        vitalType: vitalType,
        startDate: startDate,
        endDate: endDate,
        personId: personId,
      );
      vitalInsights.add(insight);
    }

    final overallInsights = _generateOverallInsights(overview, vitalInsights);
    final overallRisk = _calculateOverallRisk(vitalInsights);

    return HealthInsightReport(
      userId: userId,
      personId: personId,
      startDate: startDate,
      endDate: endDate,
      overview: overview,
      vitalInsights: vitalInsights,
      overallInsights: overallInsights,
      overallRisk: overallRisk,
      generatedAt: DateTime.now(),
    );
  }

  /// Assess risk level based on vital type and trend analysis
  RiskLevel _assessRiskLevel(VitalType vitalType, VitalTrendAnalysis analysis) {
    if (analysis.dataQuality == DataQuality.insufficient) {
      return RiskLevel.unknown;
    }

    // Define normal ranges for different vital types
    bool isInNormalRange = _isValueInNormalRange(
      vitalType,
      analysis.averageValue,
    );
    bool hasConcerningTrend = _hasConcerningTrend(vitalType, analysis);

    if (!isInNormalRange && hasConcerningTrend) {
      return RiskLevel.high;
    } else if (!isInNormalRange || hasConcerningTrend) {
      return RiskLevel.medium;
    } else {
      return RiskLevel.low;
    }
  }

  /// Check if value is in normal range for the vital type
  bool _isValueInNormalRange(VitalType vitalType, double value) {
    switch (vitalType) {
      case VitalType.glucose:
        return value >= 70 && value <= 140; // mg/dL
      case VitalType.weight:
        return value > 0; // Weight depends on individual
      case VitalType.bloodPressure:
        return value < 140; // Systolic pressure
      case VitalType.temperature:
        return value >= 36.1 && value <= 37.2; // Celsius
      case VitalType.heartRate:
        return value >= 60 && value <= 100; // BPM
      case VitalType.steps:
        return value >= 5000; // Daily steps
      case VitalType.hba1c:
        return value < 7.0; // % for diabetics, <5.7% for non-diabetics
    }
  }

  /// Check if trend is concerning for the vital type
  bool _hasConcerningTrend(VitalType vitalType, VitalTrendAnalysis analysis) {
    switch (vitalType) {
      case VitalType.glucose:
      case VitalType.bloodPressure:
      case VitalType.temperature:
      case VitalType.hba1c:
        return analysis.trend == TrendDirection.increasing &&
            analysis.changePercent.abs() > 10;
      case VitalType.weight:
        return analysis.changePercent.abs() > 5; // Weight change > 5%
      case VitalType.heartRate:
        return analysis.trend == TrendDirection.increasing &&
            analysis.averageValue > 100;
      case VitalType.steps:
        return analysis.trend == TrendDirection.decreasing &&
            analysis.changePercent.abs() > 20;
    }
  }

  /// Generate insights based on trend direction
  void _generateTrendInsights(
    VitalType vitalType,
    VitalTrendAnalysis analysis,
    List<String> insights,
    List<String> recommendations,
  ) {
    final vitalName = _getVitalDisplayName(vitalType);
    final changePercent = analysis.changePercent.abs().toStringAsFixed(1);

    switch (analysis.trend) {
      case TrendDirection.increasing:
        insights.add(
          'Your $vitalName has been increasing by $changePercent% over this period.',
        );
        if (_hasConcerningTrend(vitalType, analysis)) {
          recommendations.add(
            'Consider consulting with your healthcare provider about the upward trend in $vitalName.',
          );
        }
        break;

      case TrendDirection.decreasing:
        insights.add(
          'Your $vitalName has been decreasing by $changePercent% over this period.',
        );
        if (vitalType == VitalType.steps || vitalType == VitalType.weight) {
          if (vitalType == VitalType.steps) {
            recommendations.add(
              'Try to increase your daily activity to maintain healthy step counts.',
            );
          }
        }
        break;

      case TrendDirection.stable:
        insights.add(
          'Your $vitalName has remained relatively stable over this period.',
        );
        recommendations.add(
          'Great job maintaining consistent $vitalName levels!',
        );
        break;
    }
  }

  /// Generate insights based on value ranges
  void _generateRangeInsights(
    VitalType vitalType,
    VitalTrendAnalysis analysis,
    List<String> insights,
    List<String> recommendations,
  ) {
    final vitalName = _getVitalDisplayName(vitalType);
    final average = analysis.averageValue.toStringAsFixed(1);
    final isInRange = _isValueInNormalRange(vitalType, analysis.averageValue);

    if (isInRange) {
      insights.add(
        'Your average $vitalName of $average is within the normal range.',
      );
    } else {
      insights.add(
        'Your average $vitalName of $average is outside the typical range.',
      );
      recommendations.add(
        'Discuss your $vitalName readings with your healthcare provider.',
      );
    }

    // Add variability insights
    final range = (analysis.maxValue - analysis.minValue).toStringAsFixed(1);
    if (analysis.maxValue - analysis.minValue > analysis.averageValue * 0.3) {
      insights.add(
        'Your $vitalName shows significant variation (range: $range).',
      );
      recommendations.add(
        'Try to identify factors that might affect your $vitalName consistency.',
      );
    }
  }

  /// Generate insights about data quality
  void _generateDataQualityInsights(
    VitalTrendAnalysis analysis,
    List<String> insights,
    List<String> recommendations,
  ) {
    switch (analysis.dataQuality) {
      case DataQuality.insufficient:
        insights.add('Not enough data points to provide reliable insights.');
        recommendations.add(
          'Record measurements more frequently for better trend analysis.',
        );
        break;
      case DataQuality.limited:
        insights.add('Limited data available for analysis.');
        recommendations.add('Consider recording measurements more regularly.');
        break;
      case DataQuality.moderate:
        insights.add('Good amount of data for trend analysis.');
        break;
      case DataQuality.good:
        insights.add('Excellent data quality for comprehensive analysis.');
        recommendations.add('Keep up the consistent tracking!');
        break;
    }
  }

  /// Generate overall health insights
  List<String> _generateOverallInsights(
    HealthOverview overview,
    List<VitalInsight> vitalInsights,
  ) {
    final insights = <String>[];

    // Data collection insights
    final totalDays = overview.endDate.difference(overview.startDate).inDays;
    insights.add(
      'Analyzed ${overview.totalEntries} health entries over $totalDays days.',
    );

    if (overview.medicationCount > 0) {
      insights.add('Tracked ${overview.medicationCount} medication entries.');
      if (overview.frequentMedications.isNotEmpty) {
        insights.add(
          'Most tracked medications: ${overview.frequentMedications.join(", ")}.',
        );
      }
    }

    if (overview.labResultCount > 0) {
      insights.add('Recorded ${overview.labResultCount} lab results.');
    }

    // Risk-based insights
    final highRiskVitals = vitalInsights
        .where((v) => v.riskLevel == RiskLevel.high)
        .toList();
    final mediumRiskVitals = vitalInsights
        .where((v) => v.riskLevel == RiskLevel.medium)
        .toList();

    if (highRiskVitals.isNotEmpty) {
      final vitalNames = highRiskVitals
          .map((v) => _getVitalDisplayName(v.vitalType))
          .join(", ");
      insights.add('Higher attention needed for: $vitalNames.');
    } else if (mediumRiskVitals.isNotEmpty) {
      insights.add('Some vitals may need monitoring.');
    } else {
      insights.add('Overall health trends look good!');
    }

    return insights;
  }

  /// Calculate overall risk level
  RiskLevel _calculateOverallRisk(List<VitalInsight> vitalInsights) {
    if (vitalInsights.isEmpty) return RiskLevel.unknown;

    final highRiskCount = vitalInsights
        .where((v) => v.riskLevel == RiskLevel.high)
        .length;
    final mediumRiskCount = vitalInsights
        .where((v) => v.riskLevel == RiskLevel.medium)
        .length;

    if (highRiskCount > 0) return RiskLevel.high;
    if (mediumRiskCount > 0) return RiskLevel.medium;
    return RiskLevel.low;
  }

  /// Get display name for vital type
  String _getVitalDisplayName(VitalType vitalType) {
    switch (vitalType) {
      case VitalType.glucose:
        return 'blood glucose';
      case VitalType.weight:
        return 'weight';
      case VitalType.bloodPressure:
        return 'blood pressure';
      case VitalType.temperature:
        return 'temperature';
      case VitalType.heartRate:
        return 'heart rate';
      case VitalType.steps:
        return 'daily steps';
      case VitalType.hba1c:
        return 'HbA1c';
    }
  }
}

/// Risk level assessment
enum RiskLevel { low, medium, high, unknown }

/// Insight for a specific vital type
class VitalInsight {
  final VitalType vitalType;
  final VitalTrendAnalysis trendAnalysis;
  final List<String> insights;
  final List<String> recommendations;
  final RiskLevel riskLevel;
  final DateTime generatedAt;

  VitalInsight({
    required this.vitalType,
    required this.trendAnalysis,
    required this.insights,
    required this.recommendations,
    required this.riskLevel,
    required this.generatedAt,
  });
}

/// Comprehensive health insight report
class HealthInsightReport {
  final String userId;
  final String? personId;
  final DateTime startDate;
  final DateTime endDate;
  final HealthOverview overview;
  final List<VitalInsight> vitalInsights;
  final List<String> overallInsights;
  final RiskLevel overallRisk;
  final DateTime generatedAt;

  HealthInsightReport({
    required this.userId,
    this.personId,
    required this.startDate,
    required this.endDate,
    required this.overview,
    required this.vitalInsights,
    required this.overallInsights,
    required this.overallRisk,
    required this.generatedAt,
  });
}

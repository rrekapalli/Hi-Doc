import 'dart:math' as math;
import '../models/health_entry.dart';
import '../repositories/repository_interfaces.dart';
import '../repositories/repository_manager.dart';

/// Service for analyzing health data trends and patterns
class TrendAnalysisService {
  final HealthEntryRepository _healthEntryRepository;

  TrendAnalysisService({HealthEntryRepository? healthEntryRepository})
    : _healthEntryRepository =
          healthEntryRepository ??
          RepositoryManager.instance.healthEntryRepository;

  /// Get trend analysis for a specific vital type over a time period
  Future<VitalTrendAnalysis> analyzeVitalTrend({
    required String userId,
    required VitalType vitalType,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
  }) async {
    final entries = await _healthEntryRepository.findByDateRange(
      startDate.millisecondsSinceEpoch,
      endDate.millisecondsSinceEpoch,
      userId,
    );

    // Filter entries for specific vital type and person if specified
    final vitalEntries = entries
        .where(
          (entry) =>
              entry.type == HealthEntryType.vital &&
              entry.vital?.vitalType == vitalType &&
              (personId == null || entry.personId == personId),
        )
        .toList();

    return _calculateVitalTrend(vitalEntries, vitalType);
  }

  /// Get comprehensive health overview for a time period
  Future<HealthOverview> getHealthOverview({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    String? personId,
  }) async {
    final entries = await _healthEntryRepository.findByDateRange(
      startDate.millisecondsSinceEpoch,
      endDate.millisecondsSinceEpoch,
      userId,
    );

    // Filter by person if specified
    final filteredEntries = personId != null
        ? entries.where((e) => e.personId == personId).toList()
        : entries;

    final vitalEntries = filteredEntries
        .where((e) => e.type == HealthEntryType.vital)
        .toList();
    final medicationEntries = filteredEntries
        .where((e) => e.type == HealthEntryType.medication)
        .toList();
    final labEntries = filteredEntries
        .where((e) => e.type == HealthEntryType.labResult)
        .toList();

    // Analyze trends for each vital type
    final vitalTrends = <VitalType, VitalTrendAnalysis>{};
    for (final vitalType in VitalType.values) {
      final vitalTypeEntries = vitalEntries
          .where((entry) => entry.vital?.vitalType == vitalType)
          .toList();

      if (vitalTypeEntries.isNotEmpty) {
        vitalTrends[vitalType] = _calculateVitalTrend(
          vitalTypeEntries,
          vitalType,
        );
      }
    }

    return HealthOverview(
      userId: userId,
      personId: personId,
      startDate: startDate,
      endDate: endDate,
      totalEntries: filteredEntries.length,
      vitalTrends: vitalTrends,
      medicationCount: medicationEntries.length,
      labResultCount: labEntries.length,
      frequentMedications: _getMostFrequentMedications(medicationEntries),
      recentLabParameters: _getRecentLabParameters(labEntries),
    );
  }

  /// Calculate trend analysis for vital readings
  VitalTrendAnalysis _calculateVitalTrend(
    List<HealthEntry> entries,
    VitalType vitalType,
  ) {
    if (entries.isEmpty) {
      return VitalTrendAnalysis(
        vitalType: vitalType,
        dataPoints: [],
        trend: TrendDirection.stable,
        averageValue: 0,
        minValue: 0,
        maxValue: 0,
        changePercent: 0,
        dataQuality: DataQuality.insufficient,
      );
    }

    // Sort by timestamp
    entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final dataPoints = <VitalDataPoint>[];
    for (final entry in entries) {
      final vital = entry.vital!;
      double? value;

      // Extract numeric value based on vital type
      if (vitalType == VitalType.bloodPressure) {
        // For BP, we'll analyze systolic pressure as the main trend
        value = vital.systolic;
      } else {
        value = vital.value;
      }

      if (value != null) {
        dataPoints.add(
          VitalDataPoint(
            timestamp: entry.timestamp,
            value: value,
            systolic: vital.systolic,
            diastolic: vital.diastolic,
            unit: vital.unit ?? '',
          ),
        );
      }
    }

    if (dataPoints.isEmpty) {
      return VitalTrendAnalysis(
        vitalType: vitalType,
        dataPoints: [],
        trend: TrendDirection.stable,
        averageValue: 0,
        minValue: 0,
        maxValue: 0,
        changePercent: 0,
        dataQuality: DataQuality.insufficient,
      );
    }

    // Calculate statistics
    final values = dataPoints.map((dp) => dp.value).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);

    // Calculate trend direction using linear regression
    final trend = _calculateTrendDirection(dataPoints);

    // Calculate change percentage (first to last value)
    double changePercent = 0;
    if (dataPoints.length >= 2) {
      final firstValue = dataPoints.first.value;
      final lastValue = dataPoints.last.value;
      if (firstValue != 0) {
        changePercent = ((lastValue - firstValue) / firstValue) * 100;
      }
    }

    // Assess data quality
    final dataQuality = _assessDataQuality(dataPoints);

    return VitalTrendAnalysis(
      vitalType: vitalType,
      dataPoints: dataPoints,
      trend: trend,
      averageValue: average,
      minValue: minValue,
      maxValue: maxValue,
      changePercent: changePercent,
      dataQuality: dataQuality,
    );
  }

  /// Calculate trend direction using simple slope analysis
  TrendDirection _calculateTrendDirection(List<VitalDataPoint> dataPoints) {
    if (dataPoints.length < 2) return TrendDirection.stable;

    // Simple linear regression to determine slope
    final n = dataPoints.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;

    for (int i = 0; i < n; i++) {
      final x = i.toDouble(); // Use index as x-coordinate
      final y = dataPoints[i].value;

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);

    // Determine trend based on slope
    if (slope > 0.1) return TrendDirection.increasing;
    if (slope < -0.1) return TrendDirection.decreasing;
    return TrendDirection.stable;
  }

  /// Assess data quality based on frequency and consistency
  DataQuality _assessDataQuality(List<VitalDataPoint> dataPoints) {
    if (dataPoints.length < 3) return DataQuality.insufficient;
    if (dataPoints.length < 7) return DataQuality.limited;
    if (dataPoints.length < 14) return DataQuality.moderate;
    return DataQuality.good;
  }

  /// Get most frequent medications from entries
  List<String> _getMostFrequentMedications(
    List<HealthEntry> medicationEntries,
  ) {
    final medicationCounts = <String, int>{};

    for (final entry in medicationEntries) {
      final medName = entry.medication?.name;
      if (medName != null) {
        medicationCounts[medName] = (medicationCounts[medName] ?? 0) + 1;
      }
    }

    final sortedMeds = medicationCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedMeds.take(5).map((e) => e.key).toList();
  }

  /// Get recent lab parameters
  List<String> _getRecentLabParameters(List<HealthEntry> labEntries) {
    final recentLabs = <String>[];

    for (final entry in labEntries) {
      final parameters = entry.labResult?.parameters ?? [];
      for (final param in parameters) {
        if (!recentLabs.contains(param.name)) {
          recentLabs.add(param.name);
        }
      }
    }

    return recentLabs.take(10).toList();
  }
}

/// Data classes for trend analysis results

enum TrendDirection { increasing, decreasing, stable }

enum DataQuality { insufficient, limited, moderate, good }

class VitalDataPoint {
  final DateTime timestamp;
  final double value;
  final double? systolic;
  final double? diastolic;
  final String unit;

  VitalDataPoint({
    required this.timestamp,
    required this.value,
    this.systolic,
    this.diastolic,
    required this.unit,
  });
}

class VitalTrendAnalysis {
  final VitalType vitalType;
  final List<VitalDataPoint> dataPoints;
  final TrendDirection trend;
  final double averageValue;
  final double minValue;
  final double maxValue;
  final double changePercent;
  final DataQuality dataQuality;

  VitalTrendAnalysis({
    required this.vitalType,
    required this.dataPoints,
    required this.trend,
    required this.averageValue,
    required this.minValue,
    required this.maxValue,
    required this.changePercent,
    required this.dataQuality,
  });
}

class HealthOverview {
  final String userId;
  final String? personId;
  final DateTime startDate;
  final DateTime endDate;
  final int totalEntries;
  final Map<VitalType, VitalTrendAnalysis> vitalTrends;
  final int medicationCount;
  final int labResultCount;
  final List<String> frequentMedications;
  final List<String> recentLabParameters;

  HealthOverview({
    required this.userId,
    this.personId,
    required this.startDate,
    required this.endDate,
    required this.totalEntries,
    required this.vitalTrends,
    required this.medicationCount,
    required this.labResultCount,
    required this.frequentMedications,
    required this.recentLabParameters,
  });
}

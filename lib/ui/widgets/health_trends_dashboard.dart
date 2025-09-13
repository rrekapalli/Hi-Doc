import 'package:flutter/material.dart';
import '../../services/trend_analysis_service.dart';
import '../../services/insight_generation_service.dart';
import '../../models/health_entry.dart';
import 'health_trend_chart.dart';
import 'health_insight_card.dart';

/// Dashboard widget displaying health trends and analytics
class HealthTrendsDashboard extends StatefulWidget {
  final String userId;
  final String? personId;
  final DateTime? startDate;
  final DateTime? endDate;

  const HealthTrendsDashboard({
    super.key,
    required this.userId,
    this.personId,
    this.startDate,
    this.endDate,
  });

  @override
  State<HealthTrendsDashboard> createState() => _HealthTrendsDashboardState();
}

class _HealthTrendsDashboardState extends State<HealthTrendsDashboard> {
  final TrendAnalysisService _trendService = TrendAnalysisService();
  final InsightGenerationService _insightService = InsightGenerationService();

  HealthInsightReport? _healthReport;
  bool _isLoading = true;
  String? _errorMessage;

  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate =
        widget.startDate ?? DateTime.now().subtract(const Duration(days: 30));
    _endDate = widget.endDate ?? DateTime.now();
    _loadHealthReport();
  }

  Future<void> _loadHealthReport() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await _insightService.generateHealthReport(
        userId: widget.userId,
        startDate: _startDate,
        endDate: _endDate,
        personId: widget.personId,
      );

      if (mounted) {
        setState(() {
          _healthReport = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load health trends: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Trends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _showDateRangePicker,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHealthReport,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHealthReport,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_healthReport == null || _healthReport!.vitalInsights.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No health data available for trend analysis',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add health entries to see trends and insights',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeHeader(),
          const SizedBox(height: 16),
          _buildOverallInsights(),
          const SizedBox(height: 24),
          _buildVitalTrendsSection(),
        ],
      ),
    );
  }

  Widget _buildDateRangeHeader() {
    final dateFormat =
        '${_startDate.day}/${_startDate.month}/${_startDate.year}';
    final endFormat = '${_endDate.day}/${_endDate.month}/${_endDate.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.date_range, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              'Analysis Period: $dateFormat - $endFormat',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            Text(
              '${_healthReport!.overview.totalEntries} entries',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallInsights() {
    final report = _healthReport!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getRiskIcon(report.overallRisk),
                  color: _getRiskColor(report.overallRisk),
                ),
                const SizedBox(width: 8),
                Text(
                  'Overall Health Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getRiskColor(report.overallRisk).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _getRiskColor(report.overallRisk),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    report.overallRisk.name.toUpperCase(),
                    style: TextStyle(
                      color: _getRiskColor(report.overallRisk),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...report.overallInsights.map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        insight,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalTrendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vital Trends', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        ..._healthReport!.vitalInsights.map(
          (insight) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                HealthTrendChart(
                  vitalType: insight.vitalType,
                  trendAnalysis: insight.trendAnalysis,
                ),
                const SizedBox(height: 8),
                HealthInsightCard(insight: insight),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getRiskIcon(RiskLevel riskLevel) {
    switch (riskLevel) {
      case RiskLevel.high:
        return Icons.warning;
      case RiskLevel.medium:
        return Icons.info;
      case RiskLevel.low:
        return Icons.check_circle;
      case RiskLevel.unknown:
        return Icons.help;
    }
  }

  Color _getRiskColor(RiskLevel riskLevel) {
    switch (riskLevel) {
      case RiskLevel.high:
        return Colors.red;
      case RiskLevel.medium:
        return Colors.orange;
      case RiskLevel.low:
        return Colors.green;
      case RiskLevel.unknown:
        return Colors.grey;
    }
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadHealthReport();
    }
  }
}

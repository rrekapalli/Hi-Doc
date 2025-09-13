import 'package:flutter/material.dart';
import '../../services/trend_analysis_service.dart';
import '../../models/health_entry.dart';

/// Widget for displaying health trend charts
class HealthTrendChart extends StatelessWidget {
  final VitalType vitalType;
  final VitalTrendAnalysis trendAnalysis;

  const HealthTrendChart({
    super.key,
    required this.vitalType,
    required this.trendAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildChart(context),
            const SizedBox(height: 12),
            _buildStatistics(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(_getVitalIcon(), color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          _getVitalDisplayName(),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getTrendColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getTrendIcon(), size: 16, color: _getTrendColor()),
              const SizedBox(width: 4),
              Text(
                trendAnalysis.trend.name.toUpperCase(),
                style: TextStyle(
                  color: _getTrendColor(),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context) {
    if (trendAnalysis.dataPoints.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No data points available')),
      );
    }

    // Simple line chart visualization
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: TrendLinePainter(
          dataPoints: trendAnalysis.dataPoints,
          minValue: trendAnalysis.minValue,
          maxValue: trendAnalysis.maxValue,
          trendColor: _getTrendColor(),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildStatistics(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          context,
          'Average',
          '${trendAnalysis.averageValue.toStringAsFixed(1)}${_getUnit()}',
        ),
        _buildStatItem(
          context,
          'Min',
          '${trendAnalysis.minValue.toStringAsFixed(1)}${_getUnit()}',
        ),
        _buildStatItem(
          context,
          'Max',
          '${trendAnalysis.maxValue.toStringAsFixed(1)}${_getUnit()}',
        ),
        _buildStatItem(
          context,
          'Change',
          '${trendAnalysis.changePercent.toStringAsFixed(1)}%',
        ),
      ],
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  IconData _getVitalIcon() {
    switch (vitalType) {
      case VitalType.glucose:
        return Icons.local_hospital;
      case VitalType.weight:
        return Icons.monitor_weight;
      case VitalType.bloodPressure:
        return Icons.favorite;
      case VitalType.temperature:
        return Icons.thermostat;
      case VitalType.heartRate:
        return Icons.favorite;
      case VitalType.steps:
        return Icons.directions_walk;
      case VitalType.hba1c:
        return Icons.science;
    }
  }

  String _getVitalDisplayName() {
    switch (vitalType) {
      case VitalType.glucose:
        return 'Blood Glucose';
      case VitalType.weight:
        return 'Weight';
      case VitalType.bloodPressure:
        return 'Blood Pressure';
      case VitalType.temperature:
        return 'Temperature';
      case VitalType.heartRate:
        return 'Heart Rate';
      case VitalType.steps:
        return 'Daily Steps';
      case VitalType.hba1c:
        return 'HbA1c';
    }
  }

  String _getUnit() {
    switch (vitalType) {
      case VitalType.glucose:
        return ' mg/dL';
      case VitalType.weight:
        return ' kg';
      case VitalType.bloodPressure:
        return ' mmHg';
      case VitalType.temperature:
        return '°C';
      case VitalType.heartRate:
        return ' bpm';
      case VitalType.steps:
        return '';
      case VitalType.hba1c:
        return '%';
    }
  }

  IconData _getTrendIcon() {
    switch (trendAnalysis.trend) {
      case TrendDirection.increasing:
        return Icons.trending_up;
      case TrendDirection.decreasing:
        return Icons.trending_down;
      case TrendDirection.stable:
        return Icons.trending_flat;
    }
  }

  Color _getTrendColor() {
    switch (trendAnalysis.trend) {
      case TrendDirection.increasing:
        return Colors.red;
      case TrendDirection.decreasing:
        return Colors.blue;
      case TrendDirection.stable:
        return Colors.green;
    }
  }
}

/// Custom painter for drawing trend line charts
class TrendLinePainter extends CustomPainter {
  final List<VitalDataPoint> dataPoints;
  final double minValue;
  final double maxValue;
  final Color trendColor;

  TrendLinePainter({
    required this.dataPoints,
    required this.minValue,
    required this.maxValue,
    required this.trendColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final paint = Paint()
      ..color = trendColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = trendColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final points = <Offset>[];

    // Calculate points
    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final normalizedY =
          (dataPoints[i].value - minValue) / (maxValue - minValue);
      final y = size.height - (normalizedY * size.height);

      final point = Offset(x, y);
      points.add(point);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw line
    canvas.drawPath(path, paint);

    // Draw points
    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

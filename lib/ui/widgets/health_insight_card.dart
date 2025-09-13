import 'package:flutter/material.dart';
import '../../services/insight_generation_service.dart';
import '../../services/trend_analysis_service.dart';

/// Card widget displaying health insights and recommendations
class HealthInsightCard extends StatefulWidget {
  final VitalInsight insight;

  const HealthInsightCard({super.key, required this.insight});

  @override
  State<HealthInsightCard> createState() => _HealthInsightCardState();
}

class _HealthInsightCardState extends State<HealthInsightCard> {
  bool _showRecommendations = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildInsights(context),
            if (widget.insight.recommendations.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildRecommendationsToggle(context),
              if (_showRecommendations) ...[
                const SizedBox(height: 8),
                _buildRecommendations(context),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getRiskColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getRiskIcon(), color: _getRiskColor(), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Insights',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'Risk Level: ${widget.insight.riskLevel.name.toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _getRiskColor(),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Quality: ${_getDataQualityText()}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildInsights(BuildContext context) {
    if (widget.insight.insights.isEmpty) {
      return const Text('No insights available');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.insight.insights
          .map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: Colors.amber[700],
                  ),
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
          )
          .toList(),
    );
  }

  Widget _buildRecommendationsToggle(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showRecommendations = !_showRecommendations;
        });
      },
      child: Row(
        children: [
          Icon(
            _showRecommendations
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: 20,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 4),
          Text(
            _showRecommendations
                ? 'Hide Recommendations'
                : 'Show Recommendations (${widget.insight.recommendations.length})',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_services, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 6),
              Text(
                'Recommendations',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.insight.recommendations
              .map(
                (recommendation) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_right,
                        size: 16,
                        color: Colors.blue[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recommendation,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.blue[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  IconData _getRiskIcon() {
    switch (widget.insight.riskLevel) {
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

  Color _getRiskColor() {
    switch (widget.insight.riskLevel) {
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

  String _getDataQualityText() {
    switch (widget.insight.trendAnalysis.dataQuality) {
      case DataQuality.good:
        return 'Excellent';
      case DataQuality.moderate:
        return 'Good';
      case DataQuality.limited:
        return 'Limited';
      case DataQuality.insufficient:
        return 'Poor';
    }
  }
}

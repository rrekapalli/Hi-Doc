import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/trends_provider.dart';

/// Reusable card that renders the trend chart for a given indicator [type].
class IndicatorTrendCard extends StatelessWidget {
  final String type;
  const IndicatorTrendCard({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
        child: Consumer<TrendsProvider>(
          builder: (context, tp, _) {
            if (tp.isLoadingSeries) {
              return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
            }
            if (tp.seriesError != null) {
              return SizedBox(height: 260, child: Center(child: Text('Failed to load: ${tp.seriesError}')));
            }
            final points = tp.series;
            if (points.isEmpty) {
              return const SizedBox(height: 260, child: Center(child: Text('No data in this period.')));
            }
            final target = tp.target;
            final hasBand = target?.hasRange == true;
            final minY = points.map((e) => e.value).reduce((a, b) => a < b ? a : b);
            final maxY = points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
            final bandMin = hasBand ? target!.min!.toDouble() : null;
            final bandMax = hasBand ? target!.max!.toDouble() : null;
            final globalMin = hasBand ? [minY, bandMin!].reduce((a,b)=>a<b?a:b) : minY;
            final globalMax = hasBand ? [maxY, bandMax!].reduce((a,b)=>a>b?a:b) : maxY;
            final span = (globalMax - globalMin).abs();
            final extra = span == 0 ? 1 : span * 0.1;
            final primaryColor = Theme.of(context).colorScheme.primary;

            final bandColor = Colors.green.withOpacity(.14);
            // Removed transparent band edge lines with rangeAnnotations approach

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 260,
                  child: LineChart(
                    LineChartData(
                      minY: globalMin - extra,
                      maxY: globalMax + extra,
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: (points.length / 4).ceilToDouble(),
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= points.length) return const SizedBox.shrink();
                              final dt = points[i].timestamp;
                              return Text(_formatDate(dt), style: const TextStyle(fontSize: 10));
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 44),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) {
                            return spots.where((s) => s.barIndex == 0).map((s) {
                              final p = points[s.x.toInt()];
                              return LineTooltipItem(
                                '${_formatDate(p.timestamp)}\n${p.value.toStringAsFixed(2)} ${p.unit ?? target?.preferredUnit ?? ''}',
                                const TextStyle(fontSize: 12),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      // Use rangeAnnotations for target band background.
                      rangeAnnotations: hasBand ? RangeAnnotations(
                        horizontalRangeAnnotations: [
                          HorizontalRangeAnnotation(
                            y1: bandMin!,
                            y2: bandMax!,
                            color: bandColor,
                          ),
                        ],
                      ) : const RangeAnnotations(),
                      lineBarsData: [
                        // Primary readings line
                        LineChartBarData(
                          isCurved: true,
                          barWidth: 3,
                          color: primaryColor,
                          dotData: const FlDotData(show: true),
                          spots: [
                            for (int i = 0; i < points.length; i++)
                              FlSpot(i.toDouble(), points[i].value),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _LegendDot(color: primaryColor, label: 'Reading'),
                    if (hasBand)
                      _LegendDot(color: bandColor.withOpacity(.8), label: 'Target range')
                    else
                      const Text('No target range available', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label; const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

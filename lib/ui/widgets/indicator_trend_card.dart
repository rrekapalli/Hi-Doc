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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
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

            final bandColor = Colors.green.withOpacity(.18);
            // Removed transparent band edge lines with rangeAnnotations approach

            final multi = tp.multiSeries;
            final otherKeys = multi.keys.where((k) => k != tp.selectedType).take(1).toList();
            final secondKey = otherKeys.isNotEmpty ? otherKeys.first : null;
            final second = secondKey != null ? multi[secondKey]! : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 260,
                  child: LineChart(
                    LineChartData(
                      minY: globalMin - extra,
                      maxY: globalMax + extra,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: span == 0 ? 1 : span / 4,
                        getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: (points.length / 4).ceilToDouble(),
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= points.length) return const SizedBox.shrink();
                              final dt = points[i].timestamp;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(_formatDate(dt), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (v, meta) => Text(
                              v.toStringAsFixed(0),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          ),
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
                                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                        LineChartBarData(
                          isCurved: true,
                          curveSmoothness: 0.25,
                          barWidth: 3,
                          color: primaryColor,
                          dotData: FlDotData(show: true, getDotPainter: (s, p, bar, i) => FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: primaryColor)),
                          shadow: Shadow(color: primaryColor.withOpacity(.3), blurRadius: 4, offset: const Offset(0,1)),
                          spots: [for (int i=0;i<points.length;i++) FlSpot(i.toDouble(), points[i].value)],
                        ),
                        if (second != null && second.isNotEmpty)
                          LineChartBarData(
                            isCurved: false,
                            barWidth: 2,
                            color: Colors.orange,
                            dashArray: [6,4],
                            dotData: const FlDotData(show: false),
                            spots: [for (int i=0;i<second.length;i++) FlSpot(i.toDouble(), second[i].value)],
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
                    _LegendDot(color: primaryColor, label: tp.selectedType ?? 'Reading'),
                    if (secondKey != null) _LegendDot(color: Colors.orange, label: secondKey),
                    if (hasBand)
                      _LegendDot(color: bandColor.withOpacity(.8), label: 'Target range')
                    else
                      const Text('No target range available', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                _Caption(tp: tp, secondKey: secondKey),
                const SizedBox(height: 12),
                _ContextEntriesList(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  final TrendsProvider tp; final String? secondKey;
  const _Caption({required this.tp, required this.secondKey});
  @override
  Widget build(BuildContext context) {
    final unit = tp.dominantUnit ?? tp.target?.preferredUnit ?? '';
    final rangeStr = tp.from != null && tp.to != null ? _formatRange(tp.from!, tp.to!) : '';
    final parts = <String>[ 'Trend: ${tp.selectedType}' ];
    if (secondKey != null) parts.add('vs $secondKey');
    if (rangeStr.isNotEmpty) parts.add(rangeStr);
    if (unit.isNotEmpty) parts.add('Unit $unit');
    return Text(parts.join(' • '), style: const TextStyle(fontSize: 12, color: Colors.black54));
  }
}

String _formatRange(DateTime from, DateTime to) {
  String f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  return '${f(from)} to ${f(to)}';
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

class _ContextEntriesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TrendsProvider>();
    final entries = tp.contextEntries;
    if (entries.isEmpty) {
      return const SizedBox();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Daily Context', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_iconFor(e.type), size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      if (e.details != null && e.details!.isNotEmpty)
                        Text(e.details!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Text(_time(e.timestamp), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'FOOD': return Icons.restaurant;
      case 'MED': return Icons.medication;
      case 'NOTE': return Icons.sticky_note_2_outlined;
      default: return Icons.info_outline;
    }
  }
  static String _time(DateTime dt) => '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

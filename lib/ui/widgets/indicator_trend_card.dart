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
    return Consumer<TrendsProvider>(
      builder: (context, tp, _) {
        final theme = Theme.of(context);
        // Early states use a single card
        if (tp.isLoadingSeries) {
          return _singleStateCard(const Center(child: CircularProgressIndicator()));
        }
        if (tp.seriesError != null) {
          return _singleStateCard(Center(child: Text('Failed to load: ${tp.seriesError}')));
        }
        final points = tp.series;
        if (points.isEmpty) {
          return _singleStateCard(const Center(child: Text('No data in this period.')));
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
        final primaryColor = theme.colorScheme.primary;
        final latest = points.last;
        final classification = _classify(latest.value, target);
        final classificationColor = {
          'Low': Colors.red.shade400,
          'High': Colors.deepOrange.shade400,
          'Normal': Colors.green.shade600,
          '—': Colors.grey.shade600,
        }[classification] ?? theme.colorScheme.secondary;
        final bandColor = Colors.green.withOpacity(.18);
        final multi = tp.multiSeries;
        final otherKeys = multi.keys.where((k) => k != tp.selectedType).take(1).toList();
        final secondKey = otherKeys.isNotEmpty ? otherKeys.first : null;
        final second = secondKey != null ? multi[secondKey]! : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chart Card
            Card(
              color: Colors.white,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header (now on white background)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tp.selectedType ?? type, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: .5)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(latest.value.toStringAsFixed(0), style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: primaryColor)),
                                  const SizedBox(width: 8),
                                  Text(classification, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: classificationColor)),
                                ],
                              ),
                              if (target?.preferredUnit != null)
                                Text(target!.preferredUnit!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_fullDate(latest.timestamp), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 6),
                            if (hasBand)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: bandColor.withOpacity(.55), borderRadius: BorderRadius.circular(6)),
                                child: Text('${bandMin!.toStringAsFixed(0)} - ${bandMax!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                              ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: LineChart(
                        LineChartData(
                          minY: globalMin - extra,
                          maxY: globalMax + extra,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            verticalInterval: points.length <= 1 ? 1 : (points.length / 4).ceilToDouble(),
                            horizontalInterval: span == 0 ? 1 : span / 4,
                            getDrawingHorizontalLine: (v) => FlLine(color: Colors.teal.withOpacity(0.08), strokeWidth: 1),
                            getDrawingVerticalLine: (v) => FlLine(color: Colors.teal.withOpacity(0.05), strokeWidth: 1),
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
                                reservedSize: 40,
                                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
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
                          rangeAnnotations: hasBand ? RangeAnnotations(
                            horizontalRangeAnnotations: [
                              HorizontalRangeAnnotation(y1: bandMin!, y2: bandMax!, color: bandColor),
                            ],
                          ) : const RangeAnnotations(),
                          lineBarsData: [
                            LineChartBarData(
                              isCurved: true,
                              curveSmoothness: 0.25,
                              barWidth: 3,
                              color: primaryColor,
                              dotData: FlDotData(show: true, getDotPainter: (s, p, bar, i) => FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: primaryColor)),
                              spots: [for (int i=0;i<points.length;i++) FlSpot(i.toDouble(), points[i].value)],
                            ),
                            if (second != null && second.isNotEmpty)
                              LineChartBarData(
                                isCurved: false,
                                barWidth: 2,
                                color: Colors.orange,
                                dashArray: const [6,4],
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
                          const Text('No target range available', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _Caption(tp: tp, secondKey: secondKey),
                  ],
                ),
              ),
            ),
            // Table / Context Card
            Card(
              color: Colors.white,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReadingsTable(points: points, target: target),
                    const SizedBox(height: 20),
                    _ContextEntriesList(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _singleStateCard(Widget child) => Card(
  color: Colors.white,
  margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
  elevation: 3,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  child: SizedBox(height: 260, child: child),
);

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

class _ReadingsTable extends StatelessWidget {
  final List points; // List<TrendPoint>
  final dynamic target; // TargetRange?
  const _ReadingsTable({required this.points, required this.target});
  @override
  Widget build(BuildContext context) {
    final unit = target?.preferredUnit ?? '';
    // Show last up to 7 readings sorted descending by time
    final rows = points
        .map((p) => p)
        .toList()
      ..sort((a,b)=>b.timestamp.compareTo(a.timestamp));
    final display = rows.take(7).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Readings', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _tableHeader(),
              for (final p in display)
                _tableRow(
                  date: _fullDate(p.timestamp, short: true),
                  value: p.value.toStringAsFixed(0),
                  range: _classify(p.value, target),
                  notes: '',
                ),
            ],
          ),
        ),
        if (rows.length > display.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Showing latest ${display.length} of ${rows.length}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ),
      ],
    );
  }

  Widget _tableHeader() => Container(
    decoration: BoxDecoration(color: const Color(0xFFEFF6F7), borderRadius: BorderRadius.circular(7)),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: const Row(
      children: [
        Expanded(flex: 3, child: _CellText('Date', bold: true)),
        Expanded(flex: 2, child: _CellText('Value', bold: true)),
        Expanded(flex: 2, child: _CellText('Range', bold: true)),
        Expanded(flex: 3, child: _CellText('Notes', bold: true)),
      ],
    ),
  );

  Widget _tableRow({required String date, required String value, required String range, required String notes}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(.18)))),
    child: Row(
      children: [
        Expanded(flex: 3, child: _CellText(date)),
        Expanded(flex: 2, child: _CellText(value)),
        Expanded(flex: 2, child: _CellText(range)),
        Expanded(flex: 3, child: _CellText(notes, faded: true)),
      ],
    ),
  );
}

class _CellText extends StatelessWidget {
  final String text; final bool bold; final bool faded; const _CellText(this.text,{this.bold=false,this.faded=false});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 11, fontWeight: bold?FontWeight.w600:FontWeight.w400, color: faded?Colors.black54:Colors.black87));
  }
}

String _classify(double value, dynamic target) {
  if (target == null || target.min == null || target.max == null) return '—';
  if (value < target.min) return 'Low';
  if (value > target.max) return 'High';
  return 'Normal';
}

String _fullDate(DateTime dt, {bool short=false}) {
  final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final m = months[dt.month-1];
  if (short) return '$m ${dt.day}';
  return '$m ${dt.day}, ${dt.year}';
}

String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

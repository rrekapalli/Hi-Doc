import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../common/hi_doc_app_bar.dart';
import '../../providers/trends_provider.dart';
import '../../models/trend_models.dart';
import '../widgets/indicator_trend_card.dart';

class TrendsScreen extends StatefulWidget {
  static const route = '/trends';
  const TrendsScreen({super.key});
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Delay init to after first frame to ensure provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TrendsProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'Trends'),
      body: Consumer<TrendsProvider>(
        builder: (context, tp, _) {
          if (tp.isLoadingTypes && tp.types.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (tp.typesError != null && tp.types.isEmpty) {
            return Center(child: Text('Failed to load indicators: ${tp.typesError}'));
          }
          if (tp.types.isEmpty) {
            return const Center(child: Text('No health readings yet.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: tp.selectedType,
                        items: tp.types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: tp.setSelectedType,
                        decoration: const InputDecoration(labelText: 'Indicator'),
                      ),
                    ),
                  ],
                ),
              ),
              _RangeChips(
                selected: tp.range,
                onSelected: tp.setRange,
              ),
              Expanded(child: tp.selectedType == null ? const SizedBox() : IndicatorTrendCard(type: tp.selectedType!)),
            ],
          );
        },
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  final TrendRange selected; final void Function(TrendRange) onSelected;
  const _RangeChips({required this.selected, required this.onSelected});
  @override
  Widget build(BuildContext context) {
    final ranges = TrendRange.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final r in ranges)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(r.label),
                selected: r == selected,
                onSelected: (_) => onSelected(r),
              ),
            ),
        ],
      ),
    );
  }
}

// Chart implementation moved to IndicatorTrendCard


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
    return const _TrendsScaffold();
  }
}

class _TrendsScaffold extends StatefulWidget {
  const _TrendsScaffold();
  @override
  State<_TrendsScaffold> createState() => _TrendsScaffoldState();
}

class _TrendsScaffoldState extends State<_TrendsScaffold> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _submitting = false;

  Future<void> _submit(BuildContext context) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _submitting = true; });
    final tp = context.read<TrendsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final parsed = await tp.runNaturalLanguageQuery(text);
    if (!mounted) return; // widget disposed mid-query
    setState(() { _submitting = false; });
    if (parsed.error == null) {
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(parsed.hint ?? 'Could not parse query')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 180),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _RangeChips(
                          selected: tp.range,
                          onSelected: tp.setRange,
                        ),
                        if (tp.selectedType != null)
                          IndicatorTrendCard(type: tp.selectedType!),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                _ChatInput(
                  controller: _controller,
                  submitting: _submitting || tp.nlLoading,
                  onSend: () => _submit(context),
                  lastError: tp.nlError,
                ),
              ],
            );
        },
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  final TextEditingController controller; final bool submitting; final VoidCallback onSend; final String? lastError;
  const _ChatInput({required this.controller, required this.submitting, required this.onSend, required this.lastError});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: "Ask for a trend (e.g., 'glucose last 90 days')",
                    errorText: lastError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: submitting ? null : onSend,
                icon: submitting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
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


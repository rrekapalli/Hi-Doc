import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/database_service.dart';
import '../../models/health_entry.dart';
import 'user_settings_screen.dart';
import 'debug_entries_screen.dart';
import '../common/hi_doc_app_bar.dart';

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>();
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Medications',
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugEntriesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getMedications(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final medications = snap.data ?? [];
          
          if (medications.isEmpty) {
            return const Center(child: Text('No medications yet'));
          }
          
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: medications.length,
            itemBuilder: (ctx, i) {
              final med = medications[i];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.medication_outlined, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            med['name'] as String? ?? 'Unknown Medication',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dosage',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                med['dosage'] != null
                                  ? med['dosage'] as String
                                  : 'Not specified',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Schedule',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                med['schedule'] as String? ?? 'Not specified',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Duration',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        med['is_forever'] == 1
                            ? 'Ongoing'
                            : med['duration_days'] != null
                                ? '${med['duration_days']} days'
                                : 'Not specified',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            med['start_date'] != null
                              ? 'Started: ${_formatDate(DateTime.fromMillisecondsSinceEpoch(med['start_date'] as int))}'
                              : 'Not started',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

String _formatDate(DateTime date) {
  return DateFormat('MMM d, y').format(date.toLocal());
}

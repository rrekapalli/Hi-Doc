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
      body: FutureBuilder<List<HealthEntry>>(
        future: db.listAllEntries(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data?.where((e) => e.type == HealthEntryType.medication).toList() ?? [];
          items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          
          if (items.isEmpty) {
            return const Center(child: Text('No medications yet'));
          }
          
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final e = items[i];
              final med = e.medication;
              if (med == null) return const SizedBox.shrink();
              
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
                            med.name,
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
                                med.dose != null 
                                  ? '${med.dose}${med.doseUnit != null ? ' ${med.doseUnit}' : ''}'
                                  : 'Not specified',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Frequency',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                med.frequencyPerDay != null 
                                  ? '${med.frequencyPerDay}x daily'
                                  : 'Not specified',
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
                        med.durationDays != null 
                            ? '${med.durationDays} days'
                            : 'Ongoing',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Started: ${_formatDate(e.timestamp)}',
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

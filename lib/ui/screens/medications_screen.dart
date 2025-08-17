import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/database_service.dart';
import '../../models/health_entry.dart';
import 'user_settings_screen.dart';
import 'debug_entries_screen.dart';
import 'medication_schedule_screen.dart';
import 'edit_medication_screen.dart';
import '../common/hi_doc_app_bar.dart';

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  final _scrollController = ScrollController();
  bool _showDeleted = false;

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Show Previous Medications'),
                const SizedBox(width: 8),
                Switch(
                  value: _showDeleted,
                  onChanged: (value) {
                    setState(() {
                      _showDeleted = value;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: db.getMedications(includeDeleted: _showDeleted),
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
                    final isDeleted = med['is_deleted'] == 1;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          if (isDeleted)
                            Positioned.fill(
                              child: Container(
                                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                              ),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.2),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.secondaryContainer,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.medication_outlined,
                                              size: 24,
                                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  med['name'] as String? ?? 'Unknown Medication',
                                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (med['dosage'] != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    med['dosage'] as String,
                                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isDeleted)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton.filledTonal(
                                            icon: const Icon(Icons.schedule, size: 20),
                                            tooltip: 'Schedule',
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => MedicationScheduleScreen(medication: med),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton.filledTonal(
                                            icon: const Icon(Icons.edit, size: 20),
                                            tooltip: 'Edit',
                                            onPressed: () async {
                                              final updated = await Navigator.of(context).push<bool>(
                                                MaterialPageRoute(
                                                  builder: (_) => EditMedicationScreen(medication: med),
                                                ),
                                              );
                                              if (updated == true) {
                                                setState(() {});
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton.filledTonal(
                                            icon: const Icon(Icons.delete_outline, size: 20),
                                            tooltip: 'Delete',
                                            onPressed: () async {
                                              final confirmed = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: const Text('Delete Medication'),
                                                  content: Text('Are you sure you want to delete ${med['name']}?'),
                                                  actions: [
                                                    TextButton(
                                                      child: const Text('Cancel'),
                                                      onPressed: () => Navigator.of(context).pop(false),
                                                    ),
                                                    TextButton(
                                                      child: const Text('Delete'),
                                                      onPressed: () => Navigator.of(context).pop(true),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              
                                              if (confirmed == true) {
                                                await db.deleteMedication(med['id'] as String);
                                                setState(() {});
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _buildInfoChip(
                                          context,
                                          med['schedule_type'] == 'continuous'
                                              ? 'Continuous'
                                              : med['schedule_type'] == 'as_needed'
                                                  ? 'As Needed'
                                                  : 'Fixed Schedule',
                                          icon: med['schedule_type'] == 'continuous'
                                              ? Icons.repeat
                                              : med['schedule_type'] == 'as_needed'
                                                  ? Icons.access_time
                                                  : Icons.calendar_today,
                                        ),
                                        if (med['frequency_per_day'] != null) ...[
                                          const SizedBox(width: 8),
                                          _buildInfoChip(
                                            context,
                                            '${med['frequency_per_day']}x daily',
                                            icon: Icons.schedule,
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (med['schedule_type'] == 'fixed' &&
                                        med['from_date'] != null &&
                                        med['to_date'] != null) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.date_range,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_formatDate(DateTime.fromMillisecondsSinceEpoch(med['from_date'] as int))} - '
                                            '${_formatDate(DateTime.fromMillisecondsSinceEpoch(med['to_date'] as int))}',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildInfoChip(BuildContext context, String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y').format(date.toLocal());
  }
}
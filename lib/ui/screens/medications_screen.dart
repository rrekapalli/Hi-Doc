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

  void _addNewMedication() async {
    try {
      final now = DateTime.now();
      // Using the prototype user ID as shown in the backend logs
      const userId = 'prototype-user-12345';
      final newMedication = {
        'id': now.millisecondsSinceEpoch.toString(),
        'user_id': userId,
        'name': '',
        'dosage': null,
        'frequency_per_day': null,
        'schedule_type': 'fixed',
        'from_date': now.millisecondsSinceEpoch,
        'to_date': now.add(const Duration(days: 7)).millisecondsSinceEpoch,
        'is_deleted': 0,
      };

      if (!mounted) return;

      final updated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EditMedicationScreen(medication: newMedication),
        ),
      );
      
      if (updated == true && mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create medication: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onBackground.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Row(
              children: [
                const Text('Show Previous'),
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
            const Spacer(),
            FilledButton.icon(
              onPressed: _addNewMedication,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Medication'),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
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
                      margin: const EdgeInsets.only(bottom: 8),
                      clipBehavior: Clip.antiAlias,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                          Icon(
                                            Icons.medication_outlined,
                                            size: 20,
                                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.baseline,
                                              textBaseline: TextBaseline.alphabetic,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    med['name'] as String? ?? 'Unknown Medication',
                                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (med['dosage'] != null)
                                                  Text(
                                                    ' [${med['dosage']}]',
                                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
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
                                          IconButton(
                                            icon: const Icon(Icons.schedule, size: 18),
                                            tooltip: 'Schedule',
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => MedicationScheduleScreen(medication: med),
                                                ),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit, size: 18),
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
                                          IconButton(
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
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        _buildInfoChip(
                                          context,
                                          med['schedule_type'] == 'continuous'
                                              ? 'Continuous'
                                              : med['schedule_type'] == 'as_needed'
                                                  ? 'As Needed'
                                                  : 'Fixed',
                                          icon: med['schedule_type'] == 'continuous'
                                              ? Icons.repeat
                                              : med['schedule_type'] == 'as_needed'
                                                  ? Icons.access_time
                                                  : Icons.calendar_today,
                                        ),
                                        if (med['frequency_per_day'] != null)
                                          _buildInfoChip(
                                            context,
                                            '${med['frequency_per_day']}x daily',
                                            icon: Icons.schedule,
                                          ),
                                      ],
                                    ),
                                    if (med['schedule_type'] == 'fixed' &&
                                        med['from_date'] != null &&
                                        med['to_date'] != null) ...[
                                      const SizedBox(height: 8),
                                      _buildInfoChip(
                                        context,
                                        '${_formatDate(DateTime.fromMillisecondsSinceEpoch(med['from_date'] as int))} - '
                                        '${_formatDate(DateTime.fromMillisecondsSinceEpoch(med['to_date'] as int))}',
                                        icon: Icons.date_range,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
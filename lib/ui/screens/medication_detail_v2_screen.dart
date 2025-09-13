import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/medication_models.dart';
import '../../services/medications_repository_bridge.dart';
import '../../services/database_service.dart';
import '../../services/reminder_service.dart';
import 'medication_time_editor_sheet.dart';

class MedicationDetailV2Screen extends StatefulWidget {
  final Medication medication;
  const MedicationDetailV2Screen({super.key, required this.medication});
  @override
  State<MedicationDetailV2Screen> createState() =>
      _MedicationDetailV2ScreenState();
}

class _MedicationDetailV2ScreenState extends State<MedicationDetailV2Screen> {
  late MedicationsRepositoryBridge repo;
  List<Map<String, dynamic>> schedules = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final db = context.read<DatabaseService>();
    repo = MedicationsRepositoryBridge(reminderService: ReminderService(db));
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final data = await repo.getMedicationAggregate(widget.medication.id);
    schedules = data['schedules'] as List<Map<String, dynamic>>;
    setState(() => loading = false);
  }

  void _addTime(String scheduleId) async {
    final added = await showModalBottomSheet<MedicationScheduleTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MedicationTimeEditorSheet(scheduleId: scheduleId),
    );
    if (added != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.medication.name)),
      floatingActionButton: schedules.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addTime(schedules.first['id'] as String),
              icon: const Icon(Icons.access_time),
              label: const Text('Add Time'),
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.medication.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (widget.medication.notes != null)
                  Text(widget.medication.notes!),
                const SizedBox(height: 16),
                for (final s in schedules) ...[
                  _ScheduleCard(
                    schedule: s,
                    onAddTime: () => _addTime(s['id'] as String),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final Map<String, dynamic> schedule;
  final VoidCallback onAddTime;
  const _ScheduleCard({required this.schedule, required this.onAddTime});
  @override
  Widget build(BuildContext context) {
    final times = (schedule['times'] as List).cast<Map<String, dynamic>>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    schedule['schedule'] as String? ?? 'Schedule',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onAddTime,
                  icon: const Icon(Icons.add_alarm),
                ),
              ],
            ),
            for (final t in times) ...[
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(t['time_local'] as String),
                subtitle: Text((t['dosage'] as String?) ?? ''),
                trailing: (t['prn'] == 1) ? const Text('PRN') : null,
              ),
            ],
            if (times.isEmpty)
              TextButton.icon(
                onPressed: onAddTime,
                icon: const Icon(Icons.add),
                label: const Text('Add first time'),
              ),
          ],
        ),
      ),
    );
  }
}

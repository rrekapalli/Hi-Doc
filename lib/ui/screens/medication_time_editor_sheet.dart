import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/medication_models.dart';
import '../../services/database_service.dart';
import '../../services/medications_repository.dart';
import '../../services/reminder_service.dart';

class MedicationTimeEditorSheet extends StatefulWidget {
  final String scheduleId;
  const MedicationTimeEditorSheet({super.key, required this.scheduleId});
  @override
  State<MedicationTimeEditorSheet> createState() => _MedicationTimeEditorSheetState();
}

class _MedicationTimeEditorSheetState extends State<MedicationTimeEditorSheet> {
  TimeOfDay? _time;
  final _dosageCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  bool _prn = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Add Time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: Text(_time == null ? 'Pick time' : _time!.format(context)),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (picked != null) setState(() => _time = picked);
            },
          ),
          TextField(controller: _dosageCtrl, decoration: const InputDecoration(labelText: 'Dosage (e.g. 1 tab 500 mg)')),
          const SizedBox(height: 8),
            TextField(controller: _instructionsCtrl, decoration: const InputDecoration(labelText: 'Instructions (before breakfast etc.)')),
          SwitchListTile(value: _prn, onChanged: (v) => setState(() => _prn = v), title: const Text('PRN (as needed)')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_time == null && !_prn) ? null : () async {
                final db = context.read<DatabaseService>();
                final navigator = Navigator.of(context);
                final scheduleRow = await db.getScheduleById(widget.scheduleId);
                if (scheduleRow == null) {
                  if (mounted) navigator.pop();
                  return;
                }
                final repo = MedicationsRepository(db: db, reminderService: ReminderService(db));
                final formatted = _time == null ? '00:00' : '${_time!.hour.toString().padLeft(2,'0')}:${_time!.minute.toString().padLeft(2,'0')}';
                final timeRow = MedicationScheduleTime.create(
                  scheduleId: widget.scheduleId,
                  timeLocal: formatted,
                  dosage: _dosageCtrl.text.isEmpty ? null : _dosageCtrl.text,
                  instructions: _instructionsCtrl.text.isEmpty ? null : _instructionsCtrl.text,
                  prn: _prn,
                  sortOrder: DateTime.now().millisecondsSinceEpoch,
                );
                final schedule = MedicationSchedule.fromDb(scheduleRow);
                await repo.addScheduleTime(schedule, timeRow);
                if (mounted) navigator.pop(timeRow);
              },
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

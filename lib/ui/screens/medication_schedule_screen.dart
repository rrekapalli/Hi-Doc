import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../debug/dev_title.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class MedicationScheduleScreen extends StatefulWidget {
  final Map<String, dynamic> medication;
  
  const MedicationScheduleScreen({
    super.key,
    required this.medication,
  });

  @override
  State<MedicationScheduleScreen> createState() => _MedicationScheduleScreenState();
}

class _MedicationScheduleScreenState extends State<MedicationScheduleScreen> {
  List<TimeOfDay> _times = [];
  bool _isDaily = true;
  List<bool> _selectedDays = List.generate(7, (index) => true);
  final _daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _loadExistingSchedule();
  }

  Future<void> _loadExistingSchedule() async {
    final db = context.read<DatabaseService>();
    final reminders = await db.getRemindersByMedicationId(widget.medication['id'] as String);
    if (reminders.isNotEmpty) {
      setState(() {
        _times = reminders
            .map((r) => TimeOfDay(
                  hour: int.parse(r['time'].split(':')[0]),
                  minute: int.parse(r['time'].split(':')[1]),
                ))
            .toList();
        _isDaily = reminders.first['repeat'] == 'daily';
        if (!_isDaily) {
          final days = (reminders.first['days'] as String).split(',').map(int.parse).toList();
          _selectedDays = List.generate(7, (index) => days.contains(index + 1));
        }
      });
    }
  }

  Future<void> _addTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      setState(() {
        _times.add(time);
      });
      // Save the schedule immediately after adding a time
      await _saveSchedule();
    }
  }

  Future<void> _saveSchedule() async {
    final db = context.read<DatabaseService>();
    
    try {
      // Use prototype user ID for now to match backend
      const userId = 'prototype-user-12345';
      
      debugPrint('Saving schedule for medication: ${widget.medication['id']}');
      debugPrint('Current times: ${_times.length}');
      
      // Delete existing reminders for this medication
      await db.deleteRemindersForMedication(widget.medication['id'] as String);
      debugPrint('Deleted existing reminders');
      
      // Add new reminders
      for (final time in _times) {
        final reminderData = {
          'user_id': userId,
          'medication_id': widget.medication['id'],
          'title': widget.medication['name'],
          'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          'message': 'Time to take ${widget.medication['name']} ${widget.medication['dosage'] ?? ''}',
          'repeat': _isDaily ? 'daily' : 'weekly',
          'days': _isDaily ? null : _selectedDays
              .asMap()
              .entries
              .where((e) => e.value)
              .map((e) => (e.key + 1).toString())
              .join(','),
          'active': 1,
        };
        
        debugPrint('Inserting reminder: $reminderData');
        await db.insertReminder(reminderData);
      }

      // Update notifications
      await db.updateMedicationReminders(widget.medication['id'] as String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule saved and notifications set')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save schedule: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: devTitle(context, 'medication_schedule_screen.dart', const Text('Schedule Medication')),
        actions: [
          TextButton(
            // Deprecated: medication_schedule_screen.dart removed in favor of medication_wizard_screen.dart
            // File intentionally left nearly empty to avoid broken imports during transition. Will be deleted.
          ),

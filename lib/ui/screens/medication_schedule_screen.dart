import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        title: const Text('Schedule Medication'),
        actions: [
          TextButton(
            onPressed: _times.isEmpty ? null : _saveSchedule,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.medication['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.medication['dosage'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.medication['dosage'] as String,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (widget.medication['schedule'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.medication['schedule'] as String,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Reminder Times',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addTime,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Time'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_times.isEmpty)
            const Center(
              child: Text('No times set yet. Tap "Add Time" to set a reminder.'),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _times.length,
              itemBuilder: (context, index) {
                final time = _times[index];
                return ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(time.format(context)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() {
                        _times.removeAt(index);
                      });
                    },
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          Text(
            'Repeat',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: true,
                label: Text('Daily'),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text('Weekly'),
              ),
            ],
            selected: {_isDaily},
            onSelectionChanged: (Set<bool> selected) {
              setState(() {
                _isDaily = selected.first;
              });
            },
          ),
          if (!_isDaily) ...[
            const SizedBox(height: 16),
            Text(
              'Select Days',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _daysOfWeek
                  .asMap()
                  .entries
                  .map(
                    (e) => FilterChip(
                      label: Text(_daysOfWeek[e.key]),
                      selected: _selectedDays[e.key],
                      onSelected: (bool selected) {
                        setState(() {
                          _selectedDays[e.key] = selected;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

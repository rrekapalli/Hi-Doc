import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/activity.dart';
import '../../providers/activities_provider.dart';
import '../../providers/chat_provider.dart';
import '../common/hi_doc_app_bar.dart';

class ActivityEditScreen extends StatefulWidget {
  static const routeName = '/activity/new';
  const ActivityEditScreen({super.key});

  @override
  State<ActivityEditScreen> createState() => _ActivityEditScreenState();
}

class _ActivityEditScreenState extends State<ActivityEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _intensity;
  DateTime _dateTime = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _caloriesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time == null) return;
    setState(() {
      _dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final chat = context.read<ChatProvider>();
    final pid = chat.currentProfileId ?? 'default-profile';

    setState(() => _saving = true);
    final draft = Activity(
      id: const Uuid().v4(),
      userId: 'local-user', // backend will override using auth token
      profileId: pid,
      name: _nameCtrl.text.trim(),
      timestamp: _dateTime,
      durationMinutes: _durationCtrl.text.isEmpty ? null : int.tryParse(_durationCtrl.text),
      distanceKm: _distanceCtrl.text.isEmpty ? null : double.tryParse(_distanceCtrl.text),
      intensity: _intensity,
      caloriesBurned: _caloriesCtrl.text.isEmpty ? null : double.tryParse(_caloriesCtrl.text),
      notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text.trim(),
    );

    final prov = context.read<ActivitiesProvider>();
    final created = await prov.addActivity(draft);

    if (!mounted) return;
    setState(() => _saving = false);
    if (created != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity added')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add activity')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'New Activity'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v==null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('Date & Time:\n${_dateTime.toLocal()}'.split('.').first),
                  ),
                  TextButton.icon(
                    onPressed: _pickDateTime,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationCtrl,
                decoration: const InputDecoration(labelText: 'Duration (min)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _distanceCtrl,
                decoration: const InputDecoration(labelText: 'Distance (km)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _intensity,
                decoration: const InputDecoration(labelText: 'Intensity'),
                items: const [
                  DropdownMenuItem(value: 'Low', child: Text('Low')),
                  DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                  DropdownMenuItem(value: 'High', child: Text('High')),
                ],
                onChanged: (v) => setState(() => _intensity = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _caloriesCtrl,
                decoration: const InputDecoration(labelText: 'Calories'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width:16,height:16,child: CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.check),
                label: const Text('Save Activity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

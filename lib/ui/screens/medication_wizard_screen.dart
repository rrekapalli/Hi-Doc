import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/medications_provider.dart';
import '../../models/medication_models.dart';
import '../../services/database_service.dart';
import '../../services/reminder_service.dart';
import '../../services/medications_repository.dart';

/// Redesigned single-page add medication screen (name, amount/unit, duration, form, times, description).
class MedicationWizardScreen extends StatefulWidget {
  final Medication? editMedication;
  const MedicationWizardScreen({super.key, this.editMedication});
  @override
  State<MedicationWizardScreen> createState() => _MedicationWizardScreenState();
}

class _MedicationWizardScreenState extends State<MedicationWizardScreen> {
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '1');
  final _durationValueCtrl = TextEditingController(text: '2');
  String _amountUnit = 'pill';
  String _durationUnit = 'weeks'; // days | weeks | months
  String _form = 'Tablet';
  bool _saving = false;
  bool _loadingExisting = false;
  bool get _editing => widget.editMedication != null;

  late MedicationsRepository repo;

  final List<TimeOfDay> _times = [TimeOfDay(hour: 8, minute: 0)];

  final _formOptions = const ['Capsule','Tablet','Solution','Drops'];
  final _amountUnits = const ['pill','mg','ml'];
  final _durationUnits = const ['days','weeks','months'];

  @override
  void initState() {
    super.initState();
    final db = context.read<DatabaseService>();
    repo = MedicationsRepository(db: db, reminderService: ReminderService(db));
    if (_editing) {
      _prefillFromMedication();
      // Defer async load of existing schedules/times
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    }
  }

  void _prefillFromMedication() {
    final med = widget.editMedication!;
    _nameCtrl.text = med.name;
    if (med.notes != null && med.notes!.isNotEmpty) {
      final parts = med.notes!.split('\n');
      if (parts.isNotEmpty) {
        final first = parts.first;
        if (!first.startsWith('Form:')) _descriptionCtrl.text = first; // assume description first
      }
      final formLine = parts.firstWhere((l) => l.startsWith('Form:'), orElse: () => '');
      if (formLine.startsWith('Form:')) {
        final f = formLine.substring(5).trim();
        if (f.isNotEmpty) _form = f;
      }
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final db = context.read<DatabaseService>();
      final schedules = await db.getSchedules(widget.editMedication!.id);
      if (schedules.isNotEmpty) {
        // For now only load first schedule
        final s = schedules.first;
        final times = await db.getScheduleTimes(s['id'] as String);
        if (times.isNotEmpty) {
          _times.clear();
          for (final t in times) {
            final timeStr = (t['time_local'] as String?) ?? '08:00';
            final p = timeStr.split(':');
            final h = int.tryParse(p[0]) ?? 8; final m = int.tryParse(p.length>1?p[1]:'0') ?? 0;
            _times.add(TimeOfDay(hour: h, minute: m));
            // attempt to parse dosage
            final dosage = t['dosage'] as String?; if (dosage != null && dosage.contains(' ')) {
              final dParts = dosage.split(' ');
              if (dParts.isNotEmpty) _amountCtrl.text = dParts.first;
              if (dParts.length>1) _amountUnit = dParts[1];
            }
          }
        }
        // Duration: compute days left (approx) if has end date
        final start = s['start_date'] as int?; final end = s['end_date'] as int?;
        if (start != null && end != null) {
          final days = ((end - start) / (24*60*60*1000)).round();
          if (days % 30 == 0) { _durationUnit = 'months'; _durationValueCtrl.text = (days/30).round().toString(); }
          else if (days % 7 == 0) { _durationUnit = 'weeks'; _durationValueCtrl.text = (days/7).round().toString(); }
          else { _durationUnit = 'days'; _durationValueCtrl.text = days.toString(); }
        }
      }
    } catch (_) {
      // ignore; keep defaults
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  int? _computeEndDateMs(int startMs) {
    final raw = int.tryParse(_durationValueCtrl.text.trim());
    if (raw == null || raw <= 0) return null; // forever
    int days; // convert to days
    switch (_durationUnit) {
      case 'weeks': days = raw * 7; break;
      case 'months': days = raw * 30; break; // simple approx
      default: days = raw; break;
    }
    return startMs + days * 24 * 60 * 60 * 1000;
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) setState(() => _times.add(picked));
  }

  void _editTime(int index) async {
    final picked = await showTimePicker(context: context, initialTime: _times[index]);
    if (picked != null) setState(() => _times[index] = picked);
  }

  void _removeTime(int index) {
    setState(() => _times.removeAt(index));
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and at least one time required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<MedicationsProvider>();
      // Compose notes with optional description + form
      final desc = _descriptionCtrl.text.trim();
      final notes = [if (desc.isNotEmpty) desc, 'Form: $_form'].join('\n');
      Medication med;
      if (_editing) {
        med = widget.editMedication!.copyWith(name: _nameCtrl.text.trim(), notes: notes);
        await provider.update(med);
        // Remove existing schedules & times (simple full replace strategy)
        final db = context.read<DatabaseService>();
        final schedules = await db.getSchedules(med.id);
        for (final s in schedules) {
          final times = await db.getScheduleTimes(s['id'] as String);
          for (final t in times) { await db.deleteScheduleTime(t['id'] as String); }
          await db.deleteSchedule(s['id'] as String);
        }
        await db.deleteRemindersForMedication(med.id);
      } else {
        med = await provider.create(_nameCtrl.text.trim(), notes: notes);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final end = _computeEndDateMs(now);
      final schedule = MedicationSchedule.create(
        medicationId: med.id,
        schedule: 'daily',
        frequencyPerDay: _times.length > 1 ? _times.length : null,
        isForever: end == null,
        startDate: now,
        endDate: end,
        timezone: null,
      );
      await repo.addSchedule(med, schedule);
      for (int i = 0; i < _times.length; i++) {
        final t = _times[i];
        final timeStr = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
        final doseAmount = double.tryParse(_amountCtrl.text.trim());
        final st = MedicationScheduleTime.create(
          scheduleId: schedule.id,
          timeLocal: timeStr,
          dosage: '${_amountCtrl.text} $_amountUnit',
          doseAmount: doseAmount,
          doseUnit: _amountUnit,
          instructions: desc.isEmpty ? null : desc,
          prn: false,
          sortOrder: i + 1,
        );
        await repo.addScheduleTime(schedule, st);
      }
      if (mounted) Navigator.of(context).pop(med);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Pills name',
            suffixIcon: IconButton(icon: const Icon(Icons.photo_camera_outlined), onPressed: (){}),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _LabeledBox(label: 'Amount', child: Row(children:[
            SizedBox(
              width: 64,
              child: TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(width:4),
            DropdownButton<String>(
              value: _amountUnit,
              underline: const SizedBox.shrink(),
              items: _amountUnits.map((u)=>DropdownMenuItem(value:u, child: Text(u))).toList(),
              onChanged: (v){ if (v!=null) setState(()=>_amountUnit=v); },
            )
          ]))),
          const SizedBox(width:12),
          Expanded(child: _LabeledBox(label: 'How long?', child: Row(children:[
            SizedBox(
              width: 56,
              child: TextField(
                controller: _durationValueCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            const SizedBox(width:4),
            DropdownButton<String>(
              value: _durationUnit,
              underline: const SizedBox.shrink(),
              items: _durationUnits.map((u)=>DropdownMenuItem(value:u, child: Text(u))).toList(),
              onChanged: (v){ if (v!=null) setState(()=>_durationUnit=v); },
            )
          ]))),
        ]),
        const SizedBox(height: 20),
        Text('Medicine form', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _formOptions.map((f){
            final selected = f == _form;
            return Padding(
              padding: const EdgeInsets.only(right:8),
              child: ChoiceChip(
                label: Text(f),
                selected: selected,
                onSelected: (_){ setState(()=>_form=f); },
              ),
            );
          }).toList()),
        ),
        const SizedBox(height: 20),
        // Times
        for (int i=0; i<_times.length; i++) ...[
          _TimeCard(
            index: i,
            time: _times[i],
            onEdit: () => _editTime(i),
            onRemove: _times.length>1 ? () => _removeTime(i) : null,
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _addTime, icon: const Icon(Icons.add), label: const Text('Add time')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionCtrl,
            decoration: const InputDecoration(labelText: 'Add description'),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 80), // space for button
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Medication' : 'Add Pills')),
      body: SafeArea(
        child: _loadingExisting
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildForm(context),
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const CircularProgressIndicator.adaptive() : Text(_editing ? 'Save' : 'Done'),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledBox extends StatelessWidget {
  final String label; final Widget child;
  const _LabeledBox({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _TimeCard extends StatelessWidget {
  final int index; final TimeOfDay time; final VoidCallback onEdit; final VoidCallback? onRemove;
  const _TimeCard({required this.index, required this.time, required this.onEdit, this.onRemove});
  @override
  Widget build(BuildContext context) {
    final display = time.format(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: const Icon(Icons.alarm),
        title: Text('Time ${index+1}'),
        subtitle: Text(display, style: Theme.of(context).textTheme.titleLarge),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
            if (onRemove != null) IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

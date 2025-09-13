import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/medications_provider.dart';
import '../../models/medication_models.dart';
import '../../services/database_service.dart';
import '../../services/reminder_service.dart';
import '../../services/medications_repository_bridge.dart';

/// Redesigned single-page add medication screen (name, amount/unit, duration, form, times, description).
class MedicationWizardScreen extends StatefulWidget {
  final Medication? editMedication;
  const MedicationWizardScreen({super.key, this.editMedication});
  @override
  State<MedicationWizardScreen> createState() => _MedicationWizardScreenState();
}

class _MedicationWizardScreenState extends State<MedicationWizardScreen> {
  final _nameCtrl = TextEditingController();
  String _form = 'Tablet';
  bool _saving = false;
  bool _loadingExisting = false;
  bool get _editing => widget.editMedication != null;

  late MedicationsRepositoryBridge repo;

  // Each dosage/time group entry
  final List<_DoseEntry> _entries = [];

  final _formOptions = const ['Tablet', 'Injection', 'Capsule', 'Drops'];
  // Added 'units' per request (e.g. for insulin or other unit-based dosing)
  final _amountUnits = const ['pill', 'mg', 'ml', 'units'];
  final _durationUnits = const ['days', 'weeks', 'months'];

  @override
  void initState() {
    super.initState();
    final db = context.read<DatabaseService>();
    repo = MedicationsRepositoryBridge(reminderService: ReminderService(db));
    if (_editing) {
      _prefillFromMedication();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    } else {
      // Default single entry
      _entries.add(
        _DoseEntry(
          time: const TimeOfDay(hour: 8, minute: 0),
          amountCtrl: TextEditingController(text: '1'),
          durationValueCtrl: TextEditingController(text: '2'),
          descriptionCtrl: TextEditingController(),
          amountUnit: 'pill',
          durationUnit: 'weeks',
        ),
      );
    }
  }

  void _prefillFromMedication() {
    final med = widget.editMedication!;
    _nameCtrl.text = med.name;
    String? desc;
    if (med.notes != null && med.notes!.isNotEmpty) {
      final parts = med.notes!.split('\n');
      if (parts.isNotEmpty) {
        final first = parts.first;
        if (!first.startsWith('Form:'))
          desc = first; // assume description first
      }
      final formLine = parts.firstWhere(
        (l) => l.startsWith('Form:'),
        orElse: () => '',
      );
      if (formLine.startsWith('Form:')) {
        final f = formLine.substring(5).trim();
        if (f.isNotEmpty) _form = f;
      }
    }
    // Seed a provisional entry; actual times & dosage will load in _loadExisting
    _entries.add(
      _DoseEntry(
        time: const TimeOfDay(hour: 8, minute: 0),
        amountCtrl: TextEditingController(text: '1'),
        durationValueCtrl: TextEditingController(text: '2'),
        descriptionCtrl: TextEditingController(text: desc ?? ''),
        amountUnit: 'pill',
        durationUnit: 'weeks',
      ),
    );
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final db = context.read<DatabaseService>();
      final schedules = await db.getSchedules(widget.editMedication!.id);
      if (schedules.isNotEmpty) {
        final s = schedules.first; // only first schedule used currently
        final times = await db.getScheduleTimes(s['id'] as String);
        if (times.isNotEmpty) {
          _entries.clear();
          for (final t in times) {
            final timeStr = (t['time_local'] as String?) ?? '08:00';
            final p = timeStr.split(':');
            final h = int.tryParse(p[0]) ?? 8;
            final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
            String amount = '1';
            String amountUnit = 'pill';
            final dosage = t['dosage'] as String?;
            if (dosage != null && dosage.contains(' ')) {
              final dParts = dosage.split(' ');
              if (dParts.isNotEmpty) amount = dParts.first;
              if (dParts.length > 1) amountUnit = dParts[1];
            }
            _entries.add(
              _DoseEntry(
                time: TimeOfDay(hour: h, minute: m),
                amountCtrl: TextEditingController(text: amount),
                durationValueCtrl: TextEditingController(
                  text: '2',
                ), // fallback; refined below
                descriptionCtrl: TextEditingController(),
                amountUnit: amountUnit,
                durationUnit: 'weeks',
              ),
            );
          }
        }
        // Duration: compute days (approx). Apply to all existing entries equally.
        final start = s['start_date'] as int?;
        final end = s['end_date'] as int?;
        if (start != null && end != null) {
          final days = ((end - start) / (24 * 60 * 60 * 1000)).round();
          String unit;
          String value;
          if (days % 30 == 0) {
            unit = 'months';
            value = (days / 30).round().toString();
          } else if (days % 7 == 0) {
            unit = 'weeks';
            value = (days / 7).round().toString();
          } else {
            unit = 'days';
            value = days.toString();
          }
          for (final e in _entries) {
            e.durationUnit = unit;
            e.durationValueCtrl.text = value;
          }
        }
      }
    } catch (_) {
      // ignore; keep defaults
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  int? _computeEndDateMs(int startMs) {
    // Compute max end date across entries; if any entry has null (forever) treat overall as forever
    int? maxEnd;
    for (final e in _entries) {
      final raw = int.tryParse(e.durationValueCtrl.text.trim());
      if (raw == null || raw <= 0) return null; // forever
      int days;
      switch (e.durationUnit) {
        case 'weeks':
          days = raw * 7;
          break;
        case 'months':
          days = raw * 30;
          break;
        default:
          days = raw;
          break;
      }
      final end = startMs + days * 24 * 60 * 60 * 1000;
      if (maxEnd == null || end > maxEnd) maxEnd = end;
    }
    return maxEnd;
  }

  Future<void> _addTime() async {
    final now = TimeOfDay.now();
    final entry = _DoseEntry(
      time: now,
      amountCtrl: TextEditingController(text: '1'),
      durationValueCtrl: TextEditingController(text: '2'),
      descriptionCtrl: TextEditingController(),
      amountUnit: 'pill',
      durationUnit: 'weeks',
    );
    setState(() => _entries.add(entry));
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked != null) setState(() => entry.time = picked);
  }

  void _editTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _entries[index].time,
    );
    if (picked != null) setState(() => _entries[index].time = picked);
  }

  void _removeTime(int index) {
    final removed = _entries.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and at least one time required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<MedicationsProvider>();
      final db = context.read<DatabaseService>();
      // Compose notes: form only (descriptions now per entry)
      final notes = 'Form: $_form';
      Medication med;
      if (_editing) {
        med = widget.editMedication!.copyWith(
          name: _nameCtrl.text.trim(),
          notes: notes,
        );
        await provider.update(med);
        // Remove existing schedules & times (simple full replace strategy)
        final schedules = await db.getSchedules(med.id);
        for (final s in schedules) {
          final times = await db.getScheduleTimes(s['id'] as String);
          for (final t in times) {
            await db.deleteScheduleTime(t['id'] as String);
          }
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
        frequencyPerDay: _entries.length > 1 ? _entries.length : null,
        isForever: end == null,
        startDate: now,
        endDate: end,
        timezone: null,
      );
      await repo.addSchedule(med, schedule);
      for (int i = 0; i < _entries.length; i++) {
        final e = _entries[i];
        final t = e.time;
        final timeStr =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final doseAmount = double.tryParse(e.amountCtrl.text.trim());
        final desc = e.descriptionCtrl.text.trim();
        final st = MedicationScheduleTime.create(
          scheduleId: schedule.id,
          timeLocal: timeStr,
          dosage: '${e.amountCtrl.text} ${e.amountUnit}',
          doseAmount: doseAmount,
          doseUnit: e.amountUnit,
          instructions: desc.isEmpty ? null : desc,
          prn: false,
          sortOrder: i + 1,
        );
        await repo.addScheduleTime(schedule, st);
      }
      // Verification queries
      final medRows = await db.rawQuery(
        'SELECT COUNT(*) c FROM medications WHERE id = ?',
        [med.id],
      );
      final schedRows = await db.rawQuery(
        'SELECT COUNT(*) c FROM medication_schedules WHERE medication_id = ?',
        [med.id],
      );
      final timeRows = await db.rawQuery(
        '''SELECT COUNT(*) c FROM medication_schedule_times WHERE schedule_id = ?''',
        [schedule.id],
      );
      final cMed = medRows.first['c'];
      final cSched = schedRows.first['c'];
      final cTimes = timeRows.first['c'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved (med:$cMed sched:$cSched times:$cTimes)'),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(med);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
            labelText: 'Medication name',
            suffixIcon: IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: () {},
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Medicine form', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _formOptions.map((f) {
              final selected = f == _form;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _form = f);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        for (int i = 0; i < _entries.length; i++) ...[
          _DoseEntryCard(
            index: i,
            entry: _entries[i],
            amountUnits: _amountUnits,
            durationUnits: _durationUnits,
            onEditTime: () => _editTime(i),
            onRemove: _entries.length > 1 ? () => _removeTime(i) : null,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
        ],
        TextButton.icon(
          onPressed: _addTime,
          icon: const Icon(Icons.add),
          label: const Text('Add time'),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Medication' : 'Add Medication'),
      ),
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
              child: _saving
                  ? const CircularProgressIndicator.adaptive()
                  : Text(_editing ? 'Save' : 'Done'),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledBox extends StatelessWidget {
  final String label;
  final Widget child;
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

// New per-dosage/time entry model
class _DoseEntry {
  TimeOfDay time;
  final TextEditingController amountCtrl;
  final TextEditingController durationValueCtrl;
  final TextEditingController descriptionCtrl;
  String amountUnit;
  String durationUnit; // days | weeks | months
  _DoseEntry({
    required this.time,
    required this.amountCtrl,
    required this.durationValueCtrl,
    required this.descriptionCtrl,
    required this.amountUnit,
    required this.durationUnit,
  });
  void dispose() {
    amountCtrl.dispose();
    durationValueCtrl.dispose();
    descriptionCtrl.dispose();
  }
}

class _DoseEntryCard extends StatelessWidget {
  final int index;
  final _DoseEntry entry;
  final List<String> amountUnits;
  final List<String> durationUnits;
  final VoidCallback onEditTime;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  const _DoseEntryCard({
    required this.index,
    required this.entry,
    required this.amountUnits,
    required this.durationUnits,
    required this.onEditTime,
    this.onRemove,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeDisplay = entry.time.format(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm),
              const SizedBox(width: 8),
              Text('Time ${index + 1}', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(timeDisplay, style: theme.textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.edit), onPressed: onEditTime),
              if (onRemove != null)
                IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LabeledBox(
                  label: 'Doseage',
                  child: Row(
                    children: [
                      // Flexible numeric field to avoid overflow
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: entry.amountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isDense: true,
                            value: entry.amountUnit,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                            ),
                            items: amountUnits
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(
                                      u,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                entry.amountUnit = v;
                                onChanged();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledBox(
                  label: 'How long?',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: TextField(
                          controller: entry.durationValueCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isDense: true,
                            value: entry.durationUnit,
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                            ),
                            items: durationUnits
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(
                                      u,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                entry.durationUnit = v;
                                onChanged();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: entry.descriptionCtrl,
            decoration: const InputDecoration(labelText: 'Add description'),
            minLines: 1,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

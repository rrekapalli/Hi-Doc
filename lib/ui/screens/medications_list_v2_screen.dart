import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../debug/dev_title.dart';
import '../../providers/medications_provider.dart';
import '../../providers/selected_profile_provider.dart';
import '../../services/database_service.dart';
import '../../models/medication_models.dart';
// Removed intermediate detail screen navigation; editing happens in schedule screen directly.
import 'medication_wizard_screen.dart';

class MedicationsListV2Screen extends StatefulWidget {
  const MedicationsListV2Screen({super.key});
  @override
  State<MedicationsListV2Screen> createState() => _MedicationsListV2ScreenState();
}

class _MedicationsListV2ScreenState extends State<MedicationsListV2Screen> {
  bool _showLoading = true;
  bool _didInit = false;
  DateTime _selectedDay = DateTime.now();
  List<_DoseEntry> _entries = [];
  bool _buildingEntries = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      // Defer async load until after first frame to avoid setState/notify during build
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    }
  }

  Future<void> _init() async {
    try {
      final provider = context.read<MedicationsProvider>();
      if (provider.medications.isEmpty) {
        await provider.load();
      }
      await _buildEntries();
    } finally {
      if (mounted) setState(() => _showLoading = false);
    }
  }

  Future<void> _buildEntries() async {
    if (_buildingEntries) return;
    _buildingEntries = true;
    final db = context.read<DatabaseService>();
    final provider = context.read<MedicationsProvider>();
    final day = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final midnight = day.millisecondsSinceEpoch;
    final nextMidnight = midnight + 24*60*60*1000;
    final weekdayNames = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    final dayCode = weekdayNames[day.weekday-1];
    final list = <_DoseEntry>[];
    for (final med in provider.medications) {
      final schedules = await db.getSchedules(med.id);
      for (final s in schedules) {
        final start = s['start_date'] as int?; final end = s['end_date'] as int?;
        if (start != null && start >= nextMidnight) continue; // starts in future
        if (end != null && end < midnight) continue; // ended
        final daysCsv = s['days_of_week'] as String?; if (daysCsv != null && daysCsv.isNotEmpty) {
          final parts = daysCsv.split(',').map((e)=>e.trim().toUpperCase()).toSet();
          if (!parts.contains(dayCode)) continue; // not scheduled this day
        }
        final times = await db.getScheduleTimes(s['id'] as String);
        for (final t in times) {
          final timeStr = (t['time_local'] as String?) ?? '00:00';
          final parts = timeStr.split(':');
            int hour = int.tryParse(parts.isNotEmpty?parts[0]:'0') ?? 0;
            int minute = int.tryParse(parts.length>1?parts[1]:'0') ?? 0;
          final ts = DateTime(day.year, day.month, day.day, hour, minute).millisecondsSinceEpoch;
          list.add(_DoseEntry(
            medication: med,
            scheduleId: s['id'] as String,
            scheduleTimeId: t['id'] as String,
            timeLabel: timeStr,
            timestamp: ts,
            dosage: t['dosage'] as String?,
            prn: (t['prn'] as int? ?? 0) == 1,
          ));
        }
      }
    }
    list.sort((a,b)=>a.timestamp.compareTo(b.timestamp));
    if (mounted) setState(() { _entries = list; });
    _buildingEntries = false;
  }

  void _openWizard() async {
    final med = await Navigator.of(context).push<Medication>(
      MaterialPageRoute(builder: (_) => const MedicationWizardScreen()),
    );
    if (med != null && mounted) {
      await context.read<MedicationsProvider>().load();
      await _buildEntries();
    }
  }

  void _changeDay(DateTime day) async {
    setState(()=>_selectedDay = day);
    await _buildEntries();
  }

  Widget _buildMonthStrip() {
    final months = List.generate(6, (i){
      final base = DateTime.now();
      final m = DateTime(base.year, base.month + i, 1);
      return m;
    });
    final selectedMonthKey = '${_selectedDay.year}-${_selectedDay.month}';
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (_, i){
          final m = months[i];
          final key = '${m.year}-${m.month}';
          final selected = key == selectedMonthKey;
          return GestureDetector(
            onTap: (){ _changeDay(DateTime(m.year,m.month,_selectedDay.day.clamp(1, DateUtils.getDaysInMonth(m.year,m.month)))); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds:200),
              padding: const EdgeInsets.symmetric(horizontal:16, vertical:8),
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: .15) : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(child: Text(
                _monthLabel(m.month),
                style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Theme.of(context).colorScheme.primary : null),
              )),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width:8),
        itemCount: months.length,
      ),
    );
  }

  Widget _buildDayStrip() {
    final first = DateTime(_selectedDay.year, _selectedDay.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(first.year, first.month);
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (_, i){
          final d = DateTime(first.year, first.month, i+1);
          final selected = d.day == _selectedDay.day && d.month == _selectedDay.month && d.year == _selectedDay.year;
          return GestureDetector(
            onTap: ()=>_changeDay(d),
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 6, offset: const Offset(0,3))],
                border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_weekdayShort(d.weekday), style: TextStyle(fontSize:11, fontWeight: FontWeight.w500, color: selected?Colors.white70:Colors.grey[600])),
                  const SizedBox(height:4),
                  Text('${d.day}', style: TextStyle(fontSize:18,fontWeight: FontWeight.bold, color:selected?Colors.white:Colors.black87)),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width:8),
        itemCount: daysInMonth,
      ),
    );
  }

  Widget _buildTimeline() {
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Column(
            children: [
              const Icon(Icons.medication_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No doses scheduled for this day'),
              const SizedBox(height: 12),
              ElevatedButton.icon(onPressed: _openWizard, icon: const Icon(Icons.add), label: const Text('Add Medication')),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      padding: const EdgeInsets.only(bottom: 120, top: 8),
      itemBuilder: (context, index) {
        final e = _entries[index];
        final prev = index>0 ? _entries[index-1] : null;
        final showTime = prev == null || _timeOfDay(prev.timestamp) != _timeOfDay(e.timestamp);
        return _TimelineRow(entry: e, showTime: showTime, onTap: () async {
          // Navigate straight to schedule editor for the medication
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MedicationWizardScreen(editMedication: e.medication),
          ));
          await _buildEntries();
        });
      },
    );
  }

  String _timeOfDay(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  String _weekdayShort(int weekday) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][weekday-1];
  String _monthLabel(int month) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month-1];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MedicationsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: devTitle(context, 'medications_list_v2_screen.dart', const Text('Medications')),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _openWizard)],
      ),
      floatingActionButton: (_showLoading || provider.loading)
          ? null
          : FloatingActionButton(onPressed: _openWizard, child: const Icon(Icons.add)),
      body: provider.loading || _showLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 4),
                _buildMonthStrip(),
                const SizedBox(height: 12),
                _buildDayStrip(),
                const Divider(height: 1),
                Expanded(child: _buildTimeline()),
              ],
            ),
    );
  }
}

/// Helper widget to provide medications provider down the tree if not already.
class MedicationsV2ProviderScope extends StatelessWidget {
  final Widget child;
  const MedicationsV2ProviderScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return ProxyProvider<DatabaseService, MedicationsProvider>(
      update: (context, db, previous) {
        final profileId = context.read<SelectedProfileProvider>().selectedProfileId;
        final userId = 'prototype-user-12345';
        return previous ?? MedicationsProvider(db: db, userId: userId, profileId: profileId);
      },
      child: child,
    );
  }
}

class _DoseEntry {
  final Medication medication;
  final String scheduleId;
  final String scheduleTimeId;
  final String timeLabel;
  final int timestamp;
  final String? dosage;
  final bool prn;
  _DoseEntry({required this.medication, required this.scheduleId, required this.scheduleTimeId, required this.timeLabel, required this.timestamp, this.dosage, required this.prn});
}

class _TimelineRow extends StatelessWidget {
  final _DoseEntry entry; final bool showTime; final VoidCallback onTap;
  const _TimelineRow({required this.entry, required this.showTime, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final timeStr = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(entry.timestamp)).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: showTime ? Text(timeStr, style: const TextStyle(fontWeight: FontWeight.w600)) : const SizedBox(),
          ),
          Container(
            width: 2,
            height: 72,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(color: Theme.of(context).dividerColor.withValues(alpha: .5), borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10, offset: const Offset(0,4))],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _MedicationIcon(form: entry.medication.notes ?? ''),
                        const SizedBox(width: 12),
                        Expanded(child: Text(entry.medication.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (!entry.prn) const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(entry.dosage ?? 'Dose', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _MedicationIcon extends StatelessWidget {
  final String form;
  const _MedicationIcon({required this.form});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.medication_outlined, color: Colors.black54),
    );
  }
}

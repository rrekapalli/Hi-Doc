import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../debug/dev_title.dart';
import '../common/hi_doc_app_bar.dart';
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
  // Month + week navigation controllers
  late final PageController _monthPageController; // centers current month
  late final PageController _weekController;
  static const int _weekCenterPage = 10000; // large number to allow back/forward paging
  int _currentWeekPage = _weekCenterPage;
  late DateTime _weekAnchorMonday; // Monday of the currently centered week
  final List<DateTime> _monthWindow = List.generate(25, (i) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + i - 12, 1);
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      // Defer async load until after first frame to avoid setState/notify during build
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
      _monthPageController = PageController(initialPage: 12, viewportFraction: .22); // show neighbors
      _weekController = PageController(initialPage: _weekCenterPage);
      _weekAnchorMonday = _startOfWeek(_selectedDay);
    }
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _weekController.dispose();
    super.dispose();
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
    final selectedMonthKey = '${_selectedDay.year}-${_selectedDay.month}';
    return SizedBox(
      height: 56,
      child: PageView.builder(
        controller: _monthPageController,
        onPageChanged: (page) {
          final m = _monthWindow[page];
          final day = _selectedDay.day.clamp(1, DateUtils.getDaysInMonth(m.year, m.month));
          _changeDay(DateTime(m.year, m.month, day));
          _animateWeekToSelected();
        },
        itemCount: _monthWindow.length,
        itemBuilder: (_, i) {
          final m = _monthWindow[i];
          final key = '${m.year}-${m.month}';
          final selected = key == selectedMonthKey;
          return Center(
            child: GestureDetector(
              onTap: () {
                _monthPageController.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha:.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_monthLabel(m.month), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: selected ? Theme.of(context).colorScheme.primary : Colors.grey[700])),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayStrip() {
    // Weekly pager: stable anchor to avoid artifacts. Swipe to move week.
    return SizedBox(
  height: 110,
      child: PageView.builder(
        controller: _weekController,
        onPageChanged: (page) {
          final delta = page - _currentWeekPage;
            if (delta != 0) {
              final weekdayOffset = _selectedDay.weekday - 1; // 0-based
              setState(() {
                _weekAnchorMonday = _weekAnchorMonday.add(Duration(days: 7 * delta));
                _selectedDay = _weekAnchorMonday.add(Duration(days: weekdayOffset));
                _currentWeekPage = page;
              });
              _buildEntries();
            }
        },
        itemBuilder: (context, pageIndex) {
          final weekOffset = pageIndex - _currentWeekPage;
          final displayWeekStart = _weekAnchorMonday.add(Duration(days: 7 * weekOffset));
          final days = List.generate(7, (i) => displayWeekStart.add(Duration(days: i)));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [for (final d in days) _buildDayTile(d)],
                ),
                const SizedBox(height:8),
                // handle bar indicator mimic
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayTile(DateTime d) {
    final selected = d.year == _selectedDay.year && d.month == _selectedDay.month && d.day == _selectedDay.day;
    return GestureDetector(
      onTap: () {
        _changeDay(d);
        _weekAnchorMonday = _startOfWeek(d);
        _animateWeekToSelected();
        _syncMonthPageToSelected();
      },
      child: Container(
        width: 52,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: selected?12:4, offset: const Offset(0, 3))
          ],
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.black87)),
            const SizedBox(height:4),
            // Placeholder dots row (max 3) to mimic med markers
            SizedBox(
              height: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal:2),
                  decoration: BoxDecoration(
                    color: i==0? (selected? Colors.white : Theme.of(context).colorScheme.primary): Colors.orangeAccent,
                    shape: BoxShape.circle,
                  ),
                )),
              ),
            ),
            const SizedBox(height:6),
            Text(_weekdayShort(d.weekday), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: selected ? Colors.white70 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  DateTime _startOfWeek(DateTime d) {
    // Treat Monday as start of week
    final weekday = d.weekday; // Mon=1
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: weekday - 1));
  }

  void _animateWeekToSelected() {
    if (!_weekController.hasClients) return;
    // Always keep selected week at center page for simplicity; jump instead of animate for snappy navigation
    _currentWeekPage = _weekCenterPage;
    _weekController.jumpToPage(_weekCenterPage);
  }

  void _syncMonthPageToSelected() {
    if (!_monthPageController.hasClients) return;
    final idx = _monthWindow.indexWhere((m) => m.year == _selectedDay.year && m.month == _selectedDay.month);
    if (idx != -1 && _monthPageController.page?.round() != idx) {
      _monthPageController.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
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
      appBar: HiDocAppBar(
        pageTitle: 'Medications',
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

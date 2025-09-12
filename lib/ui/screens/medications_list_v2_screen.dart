import 'package:flutter/material.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
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
  State<MedicationsListV2Screen> createState() =>
      _MedicationsListV2ScreenState();
}

class _MedicationsListV2ScreenState extends State<MedicationsListV2Screen> {
  bool _showLoading = true;
  bool _didInit = false;
  DateTime _selectedDay = DateTime.now();
  List<_DoseEntry> _entries = [];
  bool _buildingEntries = false;
  int _takenCount = 0; // selected day counts
  int _totalCount = 0;

  // Per-week cached counts: key = yyyymmdd
  final Map<String, _DayCount> _weekDayCounts = {};

  // Filter toggle (all / taken / remaining)
  _DoseFilter _filter = _DoseFilter.all;
  // Month + week navigation controllers
  late final PageController _monthPageController; // centers current month
  late final PageController _weekController;
  static const int _weekCenterPage =
      10000; // large number to allow back/forward paging
  int _currentWeekPage = _weekCenterPage;
  late DateTime _weekAnchorMonday; // Monday of the currently centered week
  final List<DateTime> _monthWindow = List.generate(13, (i) {
    final now = DateTime.now();
    return DateTime(now.year, now.month + i - 12, 1);
  });

  // --- Month cache (avoid repeated API calls) ---
  String? _cachedMonthKey; // 'yyyy-mm'
  final Map<String, List<Map<String, dynamic>>> _schedulesByMed =
      {}; // medId -> schedules
  final Map<String, List<Map<String, dynamic>>> _timesBySchedule =
      {}; // scheduleId -> times
  final Map<String, List<Map<String, dynamic>>> _logsByMed =
      {}; // medId -> intake logs for cached month
  Timer? _rebuildDebounce;
  static const _debounceDelay = Duration(milliseconds: 160);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      // Defer async load until after first frame to avoid setState/notify during build
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
      _monthPageController = PageController(
        initialPage: 12,
        viewportFraction: .22,
      ); // show neighbors
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
    final provider = context.read<MedicationsProvider>();
    final day = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final midnight = day.millisecondsSinceEpoch;
    final nextMidnight = midnight + 24 * 60 * 60 * 1000;
    await _ensureMonthCache(day);
    final list = _enumerateDayEntries(
      day,
      provider.medications,
      midnight,
      nextMidnight,
    );
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final taken = list.where((e) => e.taken).length;
    if (mounted)
      setState(() {
        _entries = list;
        _takenCount = taken;
        _totalCount = list.length;
      });
    _buildingEntries = false;
    // Update week counts cache for this day
    _weekDayCounts[_dayKey(day)] = _DayCount(taken: taken, total: list.length);
    _computeWeekCounts(_startOfWeek(day));
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
    await _ensureMonthCache(day);
    setState(() => _selectedDay = day);
    await _buildEntries();
  }

  void _scheduleEntriesRebuild() {
    _rebuildDebounce?.cancel();
    _rebuildDebounce = Timer(_debounceDelay, () {
      if (mounted) _buildEntries();
    });
  }

  Future<void> _computeWeekCounts(DateTime weekMonday) async {
    // Avoid recomputing if all 7 present
    if (_weekHasAll(weekMonday)) return;
    final days = List.generate(7, (i) => weekMonday.add(Duration(days: i)));
    for (final d in days) {
      final key = _dayKey(d);
      if (_weekDayCounts.containsKey(key)) continue;
      final provider = context.read<MedicationsProvider>();
      final midnight = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      final nextMidnight = midnight + 24 * 60 * 60 * 1000;
      await _ensureMonthCache(d);
      final entries = _enumerateDayEntries(
        d,
        provider.medications,
        midnight,
        nextMidnight,
      );
      _weekDayCounts[key] = _DayCount(
        taken: entries.where((e) => e.taken).length,
        total: entries.length,
      );
      if (!mounted) return; // early abort if screen gone
      setState(() {}); // trigger repaint for that tile
    }
  }

  bool _weekHasAll(DateTime weekMonday) {
    for (int i = 0; i < 7; i++) {
      if (!_weekDayCounts.containsKey(
        _dayKey(weekMonday.add(Duration(days: i))),
      ))
        return false;
    }
    return true;
  }

  String _dayKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Widget _buildMonthStrip() {
    final selectedMonthKey = '${_selectedDay.year}-${_selectedDay.month}';
    return SizedBox(
      height: 56,
      child: PageView.builder(
        controller: _monthPageController,
        onPageChanged: (page) {
          final m = _monthWindow[page];
          final day = _selectedDay.day.clamp(
            1,
            DateUtils.getDaysInMonth(m.year, m.month),
          );
          _changeDay(DateTime(m.year, m.month, day));
          _animateWeekToSelected();
          _maybeExpandMonthWindow(page);
        },
        itemCount: _monthWindow.length,
        itemBuilder: (_, i) {
          final m = _monthWindow[i];
          final key = '${m.year}-${m.month}';
          final selected = key == selectedMonthKey;
          return Center(
            child: GestureDetector(
              onTap: () {
                _monthPageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _monthLabel(m.month),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[700],
                  ),
                ),
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
      height: 116,
      child: PageView.builder(
        controller: _weekController,
        onPageChanged: (page) {
          final delta = page - _currentWeekPage;
          if (delta != 0) {
            final weekdayOffset = _selectedDay.weekday - 1; // 0-based
            setState(() {
              _weekAnchorMonday = _weekAnchorMonday.add(
                Duration(days: 7 * delta),
              );
              _selectedDay = _weekAnchorMonday.add(
                Duration(days: weekdayOffset),
              );
              _currentWeekPage = page;
            });
            _scheduleEntriesRebuild();
          }
        },
        itemBuilder: (context, pageIndex) {
          final weekOffset = pageIndex - _currentWeekPage;
          final displayWeekStart = _weekAnchorMonday.add(
            Duration(days: 7 * weekOffset),
          );
          _computeWeekCounts(displayWeekStart); // ensure counts
          final days = List.generate(
            7,
            (i) => displayWeekStart.add(Duration(days: i)),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [for (final d in days) _buildDayTile(d)],
                ),
                const SizedBox(height: 8),
                // handle bar indicator mimic
                Container(
                  width: 56,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayTile(DateTime d) {
    final selected =
        d.year == _selectedDay.year &&
        d.month == _selectedDay.month &&
        d.day == _selectedDay.day;
    final count = _weekDayCounts[_dayKey(d)];
    return GestureDetector(
      onTap: () {
        // Immediate change (no debounce) for direct tap
        _changeDay(d);
        _weekAnchorMonday = _startOfWeek(d);
        _animateWeekToSelected();
        _syncMonthPageToSelected();
      },
      child: Container(
        width: 48,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: selected ? 12 : 4,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weekdayShort(d.weekday).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: .5,
                color: selected ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            const _DottedDivider(),
            const SizedBox(height: 4),
            Text(
              count == null ? '-' : '${count.taken}/${count.total}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _startOfWeek(DateTime d) {
    // Treat Monday as start of week
    final weekday = d.weekday; // Mon=1
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: weekday - 1));
  }

  void _animateWeekToSelected() {
    if (!_weekController.hasClients) return;
    // Always keep selected week at center page for simplicity; jump instead of animate for snappy navigation
    _currentWeekPage = _weekCenterPage;
    _weekController.jumpToPage(_weekCenterPage);
  }

  void _syncMonthPageToSelected() {
    if (!_monthPageController.hasClients) return;
    final idx = _monthWindow.indexWhere(
      (m) => m.year == _selectedDay.year && m.month == _selectedDay.month,
    );
    if (idx != -1 && _monthPageController.page?.round() != idx) {
      _monthPageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildTimeline() {
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 64),
          child: Column(
            children: [
              const Icon(
                Icons.medication_outlined,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text('No doses scheduled for this day'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _openWizard,
                icon: const Icon(Icons.add),
                label: const Text('Add Medication'),
              ),
            ],
          ),
        ),
      );
    }
    final filtered = _filter == _DoseFilter.all
        ? _entries
        : _entries
              .where((e) => _filter == _DoseFilter.taken ? e.taken : !e.taken)
              .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                '$_takenCount/$_totalCount taken',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              _FilterToggle(
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            padding: const EdgeInsets.only(bottom: 120, top: 4),
            // Performance optimizations
            itemExtent: 72.0, // Fixed height for better scrolling performance
            cacheExtent: 500.0, // Cache more items for smoother scrolling
            addAutomaticKeepAlives: false, // Reduce memory usage
            addRepaintBoundaries: false, // Reduce overdraw for simple items
            itemBuilder: (context, index) {
              final e = filtered[index];
              final prev = index > 0 ? filtered[index - 1] : null;
              final showTime =
                  prev == null ||
                  _timeOfDay(prev.timestamp) != _timeOfDay(e.timestamp);
              return RepaintBoundary(
                child: _TimelineRow(
                  entry: e,
                  showTime: showTime,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MedicationWizardScreen(
                          editMedication: e.medication,
                        ),
                      ),
                    );
                    _invalidateMonthCache();
                    await _buildEntries();
                  },
                  onToggleTaken: () async {
                    if (e.taken) return; // only allow mark taken for now
                    // Optimistic local update
                    setState(() {
                      e.taken = true;
                      _takenCount++;
                    });
                    final key = _dayKey(_selectedDay);
                    final dayCount = _weekDayCounts[key];
                    if (dayCount != null) {
                      _weekDayCounts[key] = _DayCount(
                        taken: dayCount.taken + 1,
                        total: dayCount.total,
                      );
                    }
                    // Update month logs cache
                    final logs = _logsByMed[e.medication.id] ??= [];
                    logs.add({
                      'id': const Uuid().v4(),
                      'schedule_time_id': e.scheduleTimeId,
                      'taken_ts': DateTime.now().millisecondsSinceEpoch,
                      'status': 'taken',
                    });
                    // Persist in background
                    unawaited(_persistTaken(e));
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _timeOfDay(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _weekdayShort(int weekday) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
  String _monthLabel(int month) => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];

  // --- Caching Helpers ---
  Future<void> _ensureMonthCache(DateTime day) async {
    final key = '${day.year}-${day.month}';
    if (_cachedMonthKey == key) return;
    _cachedMonthKey = key;
    _schedulesByMed.clear();
    _timesBySchedule.clear();
    _logsByMed.clear();
    final provider = context.read<MedicationsProvider>();
    final db = context.read<DatabaseService>();
    final monthStart = DateTime(day.year, day.month, 1);
    final nextMonth = DateTime(day.year, day.month + 1, 1);
    final fromTs = monthStart.millisecondsSinceEpoch;
    final toTs = nextMonth.millisecondsSinceEpoch - 1;
    for (final med in provider.medications) {
      final schedules = await db.getSchedules(med.id);
      _schedulesByMed[med.id] = schedules;
      for (final s in schedules) {
        final times = await db.getScheduleTimes(s['id'] as String);
        _timesBySchedule[s['id'] as String] = times;
      }
      final logs = await db.listIntakeLogs(med.id, fromTs: fromTs, toTs: toTs);
      _logsByMed[med.id] = logs;
    }
  }

  List<_DoseEntry> _enumerateDayEntries(
    DateTime day,
    List<Medication> meds,
    int midnight,
    int nextMidnight,
  ) {
    final weekdayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayCode = weekdayNames[day.weekday - 1];
    final list = <_DoseEntry>[];
    for (final med in meds) {
      final schedules = _schedulesByMed[med.id] ?? const [];
      final medLogs = _logsByMed[med.id] ?? const [];
      final takenIdsForDay = medLogs
          .where(
            (l) =>
                (l['taken_ts'] as int? ?? 0) >= midnight &&
                (l['taken_ts'] as int? ?? 0) < nextMidnight &&
                (l['status'] as String?) == 'taken',
          )
          .map((l) => l['schedule_time_id'])
          .toSet();
      for (final s in schedules) {
        final start = s['start_date'] as int?;
        final end = s['end_date'] as int?;
        if (start != null && start >= nextMidnight) continue;
        if (end != null && end < midnight) continue;
        final daysCsv = s['days_of_week'] as String?;
        if (daysCsv != null && daysCsv.isNotEmpty) {
          final parts = daysCsv
              .split(',')
              .map((e) => e.trim().toUpperCase())
              .toSet();
          if (!parts.contains(dayCode)) continue;
        }
        final times = _timesBySchedule[s['id'] as String] ?? const [];
        for (final t in times) {
          final timeStr = (t['time_local'] as String?) ?? '00:00';
          final tp = timeStr.split(':');
          final hour = int.tryParse(tp.isNotEmpty ? tp[0] : '0') ?? 0;
          final minute = int.tryParse(tp.length > 1 ? tp[1] : '0') ?? 0;
          final ts = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          ).millisecondsSinceEpoch;
          list.add(
            _DoseEntry(
              medication: med,
              scheduleId: s['id'] as String,
              scheduleTimeId: t['id'] as String,
              timeLabel: timeStr,
              timestamp: ts,
              dosage: t['dosage'] as String?,
              prn: (t['prn'] as int? ?? 0) == 1,
              taken: takenIdsForDay.contains(t['id']),
            ),
          );
        }
      }
    }
    return list;
  }

  void _invalidateMonthCache() {
    _cachedMonthKey = null; // next ensureMonthCache will reload current month
  }

  void _maybeExpandMonthWindow(int pageIndex) {
    // Append future months when near end (lazy load months, data already on-demand)
    if (pageIndex > _monthWindow.length - 4) {
      final last = _monthWindow.last;
      final additions = [
        for (int i = 1; i <= 6; i++) DateTime(last.year, last.month + i, 1),
      ];
      setState(() => _monthWindow.addAll(additions));
    }
  }

  Future<void> _persistTaken(_DoseEntry e) async {
    final db = context.read<DatabaseService>();
    try {
      await db.insertIntakeLog({
        'id': const Uuid().v4(),
        'schedule_time_id': e.scheduleTimeId,
        'taken_ts': DateTime.now().millisecondsSinceEpoch,
        'status': 'taken',
        'actual_dose_amount': null,
        'actual_dose_unit': null,
        'notes': null,
      });
    } catch (_) {
      // On failure, silently ignore for now; could add retry/rollback UI later
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MedicationsProvider>();
    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'Medications'),
      floatingActionButton: (_showLoading || provider.loading)
          ? null
          : FloatingActionButton(
              onPressed: _openWizard,
              child: const Icon(Icons.add),
            ),
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
        final profileId = context
            .read<SelectedProfileProvider>()
            .selectedProfileId;
        final userId = 'prototype-user';
        // Updated standardized prototype user id
        // (legacy rows may still exist with earlier id; migration handles normalization)
        // Keeping variable for potential future real auth mapping.
        // NOTE: variable currently unused but retained for clarity.
        return previous ??
            MedicationsProvider(db: db, userId: userId, profileId: profileId);
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
  bool taken;
  _DoseEntry({
    required this.medication,
    required this.scheduleId,
    required this.scheduleTimeId,
    required this.timeLabel,
    required this.timestamp,
    this.dosage,
    required this.prn,
    this.taken = false,
  });
}

class _TimelineRow extends StatelessWidget {
  final _DoseEntry entry;
  final bool showTime;
  final VoidCallback onTap;
  final VoidCallback onToggleTaken;
  const _TimelineRow({
    required this.entry,
    required this.showTime,
    required this.onTap,
    required this.onToggleTaken,
  });
  @override
  Widget build(BuildContext context) {
    final timeStr = TimeOfDay.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(entry.timestamp),
    ).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: showTime
                    ? Text(
                        timeStr,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )
                    : const SizedBox(),
              ),
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.only(right: 14),
                color: Theme.of(context).dividerColor.withValues(alpha: .4),
              ),
              _MedicationIcon(
                form: entry.medication.notes ?? '',
                taken: entry.taken,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: entry.medication.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if ((entry.dosage ?? '').isNotEmpty)
                        TextSpan(
                          text: '  ${entry.dosage}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleTaken,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: entry.taken
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    entry.taken ? Icons.check : Icons.radio_button_unchecked,
                    size: 18,
                    color: entry.taken
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationIcon extends StatelessWidget {
  final String form;
  final bool taken;
  const _MedicationIcon({required this.form, required this.taken});
  @override
  Widget build(BuildContext context) {
    final icon = _iconForForm(form);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: taken
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .25)
            : Theme.of(context).colorScheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.black54),
    );
  }
}

// --- Small UI Components & Helpers ---

enum _DoseFilter { all, taken, remaining }

class _FilterToggle extends StatelessWidget {
  final _DoseFilter value;
  final ValueChanged<_DoseFilter> onChanged;
  const _FilterToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Color selectedBg = Theme.of(context).colorScheme.primary;
    Color unSelBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    TextStyle txtSel = TextStyle(
      color: Theme.of(context).colorScheme.onPrimary,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );
    TextStyle txtUn = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w500,
      fontSize: 12,
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('All', _DoseFilter.all, selectedBg, unSelBg, txtSel, txtUn),
          _seg('Taken', _DoseFilter.taken, selectedBg, unSelBg, txtSel, txtUn),
          _seg(
            'Remaining',
            _DoseFilter.remaining,
            selectedBg,
            unSelBg,
            txtSel,
            txtUn,
          ),
        ],
      ),
    );
  }

  Widget _seg(
    String label,
    _DoseFilter f,
    Color selBg,
    Color unBg,
    TextStyle sel,
    TextStyle un,
  ) {
    final isSel = value == f;
    return GestureDetector(
      onTap: () => onChanged(f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? selBg : unBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: isSel ? sel : un),
      ),
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dots = (constraints.maxWidth / 4).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            dots,
            (i) => Container(
              width: 2,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .7),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DayCount {
  final int taken;
  final int total;
  _DayCount({required this.taken, required this.total});
}

IconData _iconForForm(String form) {
  final f = form.toLowerCase();
  if (f.contains('inject') ||
      f.contains('shot') ||
      f.contains('syringe') ||
      f.contains('vaccine'))
    return Icons.vaccines_outlined;
  if (f.contains('capsule') || f.contains('tablet') || f.contains('pill'))
    return Icons.medication_outlined;
  if (f.contains('drop')) return Icons.water_drop_outlined;
  if (f.contains('spray') || f.contains('inhal')) return Icons.air;
  if (f.contains('cream') || f.contains('gel') || f.contains('ointment'))
    return Icons.blur_on;
  return Icons.medication_outlined;
}

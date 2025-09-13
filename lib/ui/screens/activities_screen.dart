import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'activity_edit_screen.dart';
import '../common/hi_doc_app_bar.dart';
import '../../providers/activities_provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/activity.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});
  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  bool _initialLoadDone = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay; // null means no filter yet -> defaults to today list
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ActivitiesProvider>().load();
      });
      _initialLoadDone = true;
    }
  }

  Map<DateTime, List<Activity>> _groupByDay(List<Activity> all) {
    final map = <DateTime, List<Activity>>{};
    for (final a in all) {
      final day =
          DateTime.utc(a.timestamp.year, a.timestamp.month, a.timestamp.day);
      map.putIfAbsent(day, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final activitiesProvider = context.watch<ActivitiesProvider>();
    final chat = context.watch<ChatProvider>();
    final allActivities = activitiesProvider.activities;
    final grouped = _groupByDay(allActivities);
    final selectedDay = _selectedDay ?? DateTime.now();
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    final monthActivities = allActivities
        .where((a) =>
            a.timestamp.isAfter(
                monthStart.subtract(const Duration(milliseconds: 1))) &&
            a.timestamp.isBefore(nextMonth))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    Widget buildCalendar() {
      return TableCalendar<Activity>(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2100, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (d) => isSameDay(d, selectedDay),
        calendarFormat: _calendarFormat,
        startingDayOfWeek: StartingDayOfWeek.monday,
        headerStyle:
            const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        locale: 'en_US',
        eventLoader: (day) =>
            grouped[DateTime.utc(day.year, day.month, day.day)] ?? const [],
        onDaySelected: (sel, foc) {
          setState(() {
            _selectedDay = sel;
            _focusedDay = foc;
          });
        },
        onPageChanged: (foc) => _focusedDay = foc,
        onFormatChanged: (f) {
          if (_calendarFormat != f) {
            setState(() => _calendarFormat = f);
          }
        },
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return null;
            // Up to 3 dots like the sample; choose colors based on intensity
            final items = events.cast<Activity>();
            final dots = items.take(3).map((a) {
              final intensity = a.intensity?.toLowerCase() ?? '';
              Color c;
              if (intensity.contains('high')) {
                c = Colors.pinkAccent;
              } else if (intensity.contains('moderate')) {
                c = Colors.orangeAccent;
              } else if (intensity.contains('low')) {
                c = Colors.teal;
              } else {
                c = Colors.blueGrey;
              }
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              );
            }).toList();
            return Positioned(
              bottom: 4,
              child: Row(children: dots),
            );
          },
        ),
      );
    }

    Widget buildMonthList() {
      if (activitiesProvider.isLoading && allActivities.isEmpty) {
        return const Expanded(
            child: Center(child: CircularProgressIndicator()));
      }
      if (activitiesProvider.error != null && allActivities.isEmpty) {
        return Expanded(
          child: Center(
            child: Text(
                'Failed to load activities\n${activitiesProvider.error}',
                textAlign: TextAlign.center),
          ),
        );
      }
      if (allActivities.isEmpty) {
        return Expanded(
          child: Center(
            child: Text(chat.currentProfileId == null
                ? 'No activities recorded yet.'
                : 'No activities for this profile.'),
          ),
        );
      }
      if (monthActivities.isEmpty) {
        return Expanded(
          child: Center(
            child: Text(
                'No activities in ${_monthName(_focusedDay.month)} ${_focusedDay.year}'),
          ),
        );
      }

      // Build a combined list with date headers.
      final entries = <_ListEntry>[];
      DateTime? currentDay;
      for (final a in monthActivities) {
        final d =
            DateTime(a.timestamp.year, a.timestamp.month, a.timestamp.day);
        if (currentDay == null || currentDay != d) {
          currentDay = d;
          entries.add(_ListEntry.header(d));
        }
        entries.add(_ListEntry.activity(a));
      }

      return Expanded(
        child: ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            if (e.isHeader) {
              final d = e.day!;
              final dayActs = monthActivities
                  .where((a) =>
                      a.timestamp.year == d.year &&
                      a.timestamp.month == d.month &&
                      a.timestamp.day == d.day)
                  .length;
              return Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('${_monthName(d.month)} ${d.day}',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(width: 8),
                    Text('$dayActs',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              );
            }
            return _ActivityTile(activity: e.activity!);
          },
        ),
      );
    }

    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'Activities'),
      body: RefreshIndicator(
        onRefresh: () async => activitiesProvider.load(),
        child: Column(
          children: [
            buildCalendar(),
            const Divider(height: 0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text('${_monthName(_focusedDay.month)} ${_focusedDay.year}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(
                      '${monthActivities.length} item${monthActivities.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            buildMonthList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ActivityEditScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _monthName(int m) => const [
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
        'Dec'
      ][m - 1];
}

class _ActivityTile extends StatelessWidget {
  final Activity activity;
  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (activity.durationMinutes != null) {
      subtitleParts.add('${activity.durationMinutes} min');
    }
    if (activity.distanceKm != null) {
      subtitleParts.add('${activity.distanceKm!.toStringAsFixed(2)} km');
    }
    if (activity.caloriesBurned != null) {
      subtitleParts.add('${activity.caloriesBurned!.toStringAsFixed(0)} kcal');
    }
    if (activity.intensity != null) {
      subtitleParts.add(activity.intensity!);
    }
    final ts = TimeOfDay.fromDateTime(activity.timestamp);
    final dateStr = ts.format(context);

    return ListTile(
      leading: const Icon(Icons.directions_run),
      title: Text(activity.name),
      subtitle: Text([
        dateStr,
        if (subtitleParts.isNotEmpty) subtitleParts.join(' · '),
      ].join('  ·  ')),
      trailing: Text(activity.profileId,
          style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _ListEntry {
  final DateTime? day;
  final Activity? activity;
  final bool isHeader;
  _ListEntry.header(this.day)
      : activity = null,
        isHeader = true;
  _ListEntry.activity(this.activity)
      : day = null,
        isHeader = false;
}

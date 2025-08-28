import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../common/hi_doc_app_bar.dart';
import '../../providers/medications_provider.dart';
import 'medication_wizard_screen.dart';
import 'medications_list_v2_screen.dart';

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  /// Legacy MedicationsScreen adapted: now a thin wrapper around the new V2 list + wizard.
  class MedicationsScreen extends StatelessWidget {
    const MedicationsScreen({super.key});
    @override
    Widget build(BuildContext context) {
      return const MedicationsListV2Screen();
    }
  }

class _ScheduledMedication {
  final Map<String, dynamic> medication;
  final Map<String, dynamic> reminder;
  _ScheduledMedication({required this.medication, required this.reminder});
}

class _TimeSlot {
  final String time; // HH:mm
  final List<_ScheduledMedication> items;
  _TimeSlot(this.time, this.items);

  TimeOfDay get timeOfDay => TimeOfDay(
        hour: int.parse(time.split(':')[0]),
        minute: int.parse(time.split(':')[1]),
      );
}

// --- Widgets ---
class _TimeSlotWidget extends StatelessWidget {
  final _TimeSlot slot;
  final Map<String, bool> takenToday;
  final void Function(String reminderId) onToggleTaken;
  final void Function(Map<String, dynamic> medication) onEditMedication;
  final void Function(Map<String, dynamic> medication) onScheduleMedication;
  const _TimeSlotWidget({
    required this.slot,
    required this.takenToday,
    required this.onToggleTaken,
    required this.onEditMedication,
    required this.onScheduleMedication,
  });

  @override
  Widget build(BuildContext context) {
    final timeLabel = _format(slot.timeOfDay);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                timeLabel,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                for (final item in slot.items) ...[
                  _MedicationCard(
                    medication: item.medication,
                    reminder: item.reminder,
                    taken: takenToday[item.reminder['id'] as String? ?? ''] ?? false,
                    onToggleTaken: () => onToggleTaken(item.reminder['id'] as String? ?? ''),
                    onEdit: () => onEditMedication(item.medication),
                    onSchedule: () => onScheduleMedication(item.medication),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _format(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute$suffix';
  }
}

class _MedicationCard extends StatelessWidget {
  final Map<String, dynamic> medication;
  final Map<String, dynamic> reminder;
  final bool taken;
  final VoidCallback onToggleTaken;
  final VoidCallback onEdit;
  final VoidCallback onSchedule;
  const _MedicationCard({
    required this.medication,
    required this.reminder,
    required this.taken,
    required this.onToggleTaken,
    required this.onEdit,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final name = medication['name'] as String? ?? 'Medication';
    final dosage = medication['dosage'] as String? ?? '';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggleTaken,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.medication_outlined, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dosage.isNotEmpty)
                      Text(
                        dosage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Schedule',
                    icon: const Icon(Icons.schedule, size: 18),
                    onPressed: onSchedule,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: taken
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      taken ? Icons.check : Icons.radio_button_unchecked,
                      size: 20,
                      color: taken
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekDayStrip extends StatelessWidget {
  final DateTime anchorDate; // selected date
  final ValueChanged<DateTime> onSelect;
  const _WeekDayStrip({required this.anchorDate, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Show current week (Mon-Sun)
    final startOfWeek = anchorDate.subtract(Duration(days: anchorDate.weekday - 1));
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    return SizedBox(
      // Slightly larger overall height to give internal content room while we reduce child sizes
      height: 88,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemBuilder: (c, i) {
          final d = days[i];
            final selected = d.year == anchorDate.year && d.month == anchorDate.month && d.day == anchorDate.day;
          return GestureDetector(
            onTap: () => onSelect(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat.E().format(d),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: selected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: 16, // reduced from 18 to avoid overflow
                    backgroundColor: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.surface,
                    child: Text('${d.day}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            )),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: days.length,
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  const _MonthSelector({required this.selectedDate, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final months = List.generate(6, (i) {
      final base = DateTime(selectedDate.year, selectedDate.month - 2 + i, 1);
      return DateTime(base.year, base.month, 1);
    });
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (c, i) {
          final m = months[i];
          final selected = m.month == selectedDate.month && m.year == selectedDate.year;
          return ChoiceChip(
            label: Text(DateFormat.MMMM().format(m)),
            selected: selected,
            onSelected: (_) {
              // Keep same day number where possible
              final day = selectedDate.day;
              final lastDay = DateTime(m.year, m.month + 1, 0).day;
              final newDay = day > lastDay ? lastDay : day;
              onChanged(DateTime(m.year, m.month, newDay));
            },
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: months.length,
        padding: const EdgeInsets.only(right: 8),
      ),
    );
  }
}
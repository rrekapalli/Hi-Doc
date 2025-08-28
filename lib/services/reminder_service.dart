import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../models/medication_models.dart';

/// Computes next trigger timestamps and interacts with existing NotificationService via DatabaseService reminder API
class ReminderService {
  final DatabaseService db;
  ReminderService(this.db);

  /// Compute next trigger epoch ms for a schedule time given now and timezone (timezone currently unused placeholder)
  int? computeNextTrigger(MedicationSchedule schedule, MedicationScheduleTime timeRow, DateTime nowUtc) {
    // Basic daily/weekly handling. Extend later for every N hours, etc.
    final tz = schedule.timezone; // TODO: apply timezone conversions
    final parts = timeRow.timeLocal.split(':');
    if (parts.length < 2) return null;
    int hour = int.tryParse(parts[0]) ?? 0;
    int minute = int.tryParse(parts[1]) ?? 0;

    DateTime candidate = DateTime.now().toLocal();
    candidate = DateTime(candidate.year, candidate.month, candidate.day, hour, minute);

    bool validDay(DateTime d) {
      if (schedule.daysOfWeek == null || schedule.daysOfWeek!.isEmpty) return true;
      final csv = schedule.daysOfWeek!;
      final shortNames = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
      if (csv.contains('-') && RegExp(r'^\d-\d').hasMatch(csv)) {
        // numeric form 0-6 not implemented fully
        return true; // fallback
      }
      final set = csv.split(',').map((e) => e.trim().toUpperCase()).toSet();
      final idx = candidate.weekday - 1; // 0-based
      return set.contains(shortNames[idx]);
    }

    // move to next valid day if needed
    while (!validDay(candidate) || candidate.isBefore(DateTime.now())) {
      candidate = candidate.add(const Duration(days: 1));
      candidate = DateTime(candidate.year, candidate.month, candidate.day, hour, minute);
      if (schedule.endDate != null && candidate.millisecondsSinceEpoch > schedule.endDate!) {
        return null; // outside window
      }
    }

    if (schedule.startDate != null && candidate.millisecondsSinceEpoch < schedule.startDate!) {
      // jump to start date day
      final s = DateTime.fromMillisecondsSinceEpoch(schedule.startDate!);
      candidate = DateTime(s.year, s.month, s.day, hour, minute);
      while (!validDay(candidate)) {
        candidate = candidate.add(const Duration(days: 1));
        candidate = DateTime(candidate.year, candidate.month, candidate.day, hour, minute);
      }
    }

    return candidate.millisecondsSinceEpoch;
  }

  Future<void> recomputeAndPersist(MedicationSchedule schedule, MedicationScheduleTime timeRow) async {
    final ts = computeNextTrigger(schedule, timeRow, DateTime.now().toUtc());
    await db.updateScheduleTime({...timeRow.toDb(), 'next_trigger_ts': ts});
  }
}

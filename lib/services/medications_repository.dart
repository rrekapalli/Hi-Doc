import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../models/medication_models.dart';
import 'reminder_service.dart';

class MedicationsRepository {
  final DatabaseService db;
  final ReminderService reminderService;
  MedicationsRepository({required this.db, required this.reminderService});

  Future<Medication> createMedication({
    required String userId,
    required String profileId,
    required String name,
    String? notes,
    String? url,
  }) async {
    final med = Medication.create(userId: userId, profileId: profileId, name: name, notes: notes, url: url);
    await db.createMedicationV2(med.toDb());
    return med;
  }

  Future<MedicationSchedule> addSchedule(Medication med, MedicationSchedule schedule) async {
    await db.createSchedule(schedule.toDb());
    return schedule;
  }

  Future<MedicationScheduleTime> addScheduleTime(MedicationSchedule schedule, MedicationScheduleTime time) async {
    await db.createScheduleTime(time.toDb());
    await reminderService.recomputeAndPersist(schedule, time);
    return time;
  }

  Future<Map<String, dynamic>> getMedicationAggregate(String medicationId) async {
    final schedules = await db.getSchedules(medicationId);
    final resultSchedules = <Map<String, dynamic>>[];
    for (final s in schedules) {
      final times = await db.getScheduleTimes(s['id'] as String);
      resultSchedules.add({...s, 'times': times});
    }
    return {
      'schedules': resultSchedules,
    };
  }

  Future<List<Map<String,dynamic>>> upcomingDoses(String medicationId, {int horizonMs = 86400000}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = now + horizonMs;
    return await db.rawQuery('''SELECT mst.*, ms.schedule, ms.reminder_enabled FROM medication_schedule_times mst
      JOIN medication_schedules ms ON mst.schedule_id = ms.id
      WHERE ms.medication_id = ? AND mst.next_trigger_ts IS NOT NULL AND mst.next_trigger_ts BETWEEN ? AND ?
      ORDER BY mst.next_trigger_ts ASC LIMIT 10''',[medicationId, now, until]);
  }
}

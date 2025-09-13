import '../models/medication_models.dart';
import '../repositories/repository_manager.dart';
import '../repositories/repository_interfaces.dart';
import 'reminder_service.dart';

/// Bridge service that provides the same interface as the old MedicationsRepository
/// but uses the new repository pattern underneath
/// This allows gradual migration without breaking existing code
class MedicationsRepositoryBridge {
  final ReminderService reminderService;

  // Repository dependencies
  late final MedicationRepository _medicationRepository;
  late final MedicationScheduleRepository _scheduleRepository;
  late final MedicationScheduleTimeRepository _scheduleTimeRepository;
  late final MedicationIntakeLogRepository _intakeLogRepository;

  MedicationsRepositoryBridge({required this.reminderService}) {
    final repoManager = RepositoryManager.instance;
    _medicationRepository = repoManager.medicationRepository;
    _scheduleRepository = repoManager.medicationScheduleRepository;
    _scheduleTimeRepository = repoManager.medicationScheduleTimeRepository;
    _intakeLogRepository = repoManager.medicationIntakeLogRepository;
  }

  /// Create medication - compatible with old interface
  Future<Medication> createMedication({
    required String userId,
    required String profileId,
    required String name,
    String? notes,
    String? url,
  }) async {
    final med = Medication.create(
      userId: userId,
      profileId: profileId,
      name: name,
      notes: notes,
      url: url,
    );

    await _medicationRepository.create(med);
    return med;
  }

  /// Add schedule - compatible with old interface
  Future<MedicationSchedule> addSchedule(
    Medication med,
    MedicationSchedule schedule,
  ) async {
    final scheduleId = await _scheduleRepository.create(schedule);

    // Return updated schedule with actual ID if different
    if (scheduleId != schedule.id) {
      return MedicationSchedule(
        id: scheduleId,
        medicationId: schedule.medicationId,
        schedule: schedule.schedule,
        frequencyPerDay: schedule.frequencyPerDay,
        isForever: schedule.isForever,
        startDate: schedule.startDate,
        endDate: schedule.endDate,
        daysOfWeek: schedule.daysOfWeek,
        timezone: schedule.timezone,
        reminderEnabled: schedule.reminderEnabled,
      );
    }

    return schedule;
  }

  /// Add schedule time - compatible with old interface
  Future<MedicationScheduleTime> addScheduleTime(
    MedicationSchedule schedule,
    MedicationScheduleTime time,
  ) async {
    final timeId = await _scheduleTimeRepository.create(time);

    MedicationScheduleTime finalTime = time;
    if (timeId != time.id) {
      finalTime = MedicationScheduleTime(
        id: timeId,
        scheduleId: time.scheduleId,
        timeLocal: time.timeLocal,
        dosage: time.dosage,
        doseAmount: time.doseAmount,
        doseUnit: time.doseUnit,
        instructions: time.instructions,
        prn: time.prn,
        sortOrder: time.sortOrder,
        nextTriggerTs: time.nextTriggerTs,
      );
    }

    // Keep reminder computation as before
    await reminderService.recomputeAndPersist(schedule, finalTime);
    return finalTime;
  }

  /// Get medication aggregate - compatible with old interface
  Future<Map<String, dynamic>> getMedicationAggregate(
    String medicationId,
  ) async {
    final schedules = await _scheduleRepository.findByMedicationId(
      medicationId,
    );
    final resultSchedules = <Map<String, dynamic>>[];

    for (final schedule in schedules) {
      final times = await _scheduleTimeRepository.findByScheduleId(schedule.id);
      final scheduleMap = schedule.toDb();
      scheduleMap['times'] = times.map((t) => t.toDb()).toList();
      resultSchedules.add(scheduleMap);
    }

    return {'schedules': resultSchedules};
  }

  /// Get upcoming doses - compatible with old interface
  Future<List<Map<String, dynamic>>> upcomingDoses(
    String medicationId, {
    int horizonMs = 86400000,
  }) async {
    final scheduleTimes = await _scheduleTimeRepository.findUpcoming(
      medicationId,
      horizonMs: horizonMs,
    );

    // Convert to the old format expected by callers
    final result = <Map<String, dynamic>>[];

    for (final scheduleTime in scheduleTimes) {
      // Get schedule info for each time
      final schedules = await _scheduleRepository.findByMedicationId(
        medicationId,
      );
      final schedule = schedules.firstWhere(
        (s) => s.id == scheduleTime.scheduleId,
        orElse: () =>
            throw Exception('Schedule not found for time ${scheduleTime.id}'),
      );

      final timeMap = scheduleTime.toDb();
      timeMap['schedule'] = schedule.schedule;
      timeMap['reminder_enabled'] = schedule.reminderEnabled;
      result.add(timeMap);
    }

    return result;
  }
}

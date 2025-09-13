import 'package:flutter/foundation.dart';
import '../models/medication_models.dart';
import '../repositories/repository_manager.dart';
import '../repositories/repository_interfaces.dart';
import '../utils/performance_monitor.dart';

/// Updated MedicationsProvider using repository pattern for offline-first operation
/// Replaces direct database calls with repository-based operations
class MedicationsProviderV2 extends ChangeNotifier {
  final String userId;
  final String profileId;
  List<Medication> medications = [];
  bool loading = false;
  DateTime? _lastLoadTime;

  // Repository dependencies
  late final MedicationRepository _medicationRepository;
  late final MedicationScheduleRepository _scheduleRepository;
  late final MedicationScheduleTimeRepository _scheduleTimeRepository;
  late final MedicationIntakeLogRepository _intakeLogRepository;
  late final ReminderRepository _reminderRepository;

  // Cache to prevent unnecessary database calls
  static const Duration _cacheTimeout = Duration(minutes: 5);

  MedicationsProviderV2({required this.userId, required this.profileId}) {
    _initializeRepositories();
  }

  /// Initialize repository dependencies
  void _initializeRepositories() {
    final repoManager = RepositoryManager.instance;
    _medicationRepository = repoManager.medicationRepository;
    _scheduleRepository = repoManager.medicationScheduleRepository;
    _scheduleTimeRepository = repoManager.medicationScheduleTimeRepository;
    _intakeLogRepository = repoManager.medicationIntakeLogRepository;
    _reminderRepository = repoManager.reminderRepository;
  }

  /// Load medications with caching and performance monitoring
  Future<void> load({bool forceRefresh = false}) async {
    // Check cache validity
    if (!forceRefresh &&
        _lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!) < _cacheTimeout) {
      return;
    }

    if (loading) return; // Prevent concurrent loads

    loading = true;
    notifyListeners();

    try {
      // Use repository instead of direct database calls
      medications = await PerformanceMonitor.timeAsync(
        'medications_load',
        () => _medicationRepository.findByProfileId(
          profileId,
          filters: {'user_id': userId},
        ),
      );

      _lastLoadTime = DateTime.now();

      if (kDebugMode) {
        debugPrint(
          '[MedicationsProviderV2.load] loaded ${medications.length} medications for user=$userId profile=$profileId',
        );
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Create a new medication using repository
  Future<Medication> create(String name, {String? notes}) async {
    final med = Medication.create(
      userId: userId,
      profileId: profileId,
      name: name,
      notes: notes,
    );

    final medicationId = await PerformanceMonitor.timeAsync(
      'medication_create',
      () => _medicationRepository.create(med),
    );

    // Update the medication with the actual ID if different
    final finalMedication = medicationId != med.id
        ? med
              .copyWith() // In case ID was changed by repository
        : med;

    medications.add(finalMedication);
    _invalidateCache();
    notifyListeners();
    return finalMedication;
  }

  /// Update an existing medication using repository
  Future<void> update(Medication medication) async {
    await PerformanceMonitor.timeAsync(
      'medication_update',
      () => _medicationRepository.update(medication.id, medication),
    );

    final idx = medications.indexWhere((m) => m.id == medication.id);
    if (idx >= 0) {
      medications[idx] = medication;
    } else {
      medications.add(medication);
    }
    _invalidateCache();
    notifyListeners();
  }

  /// Delete a medication and all related data using repository
  Future<void> delete(String id) async {
    await PerformanceMonitor.timeAsync('medication_delete', () async {
      // Delete related reminders first
      await _reminderRepository.deleteByMedicationId(id, userId);

      // Delete schedules and their times (cascading)
      final schedules = await _scheduleRepository.findByMedicationId(id);
      for (final schedule in schedules) {
        await _scheduleTimeRepository.deleteByScheduleId(schedule.id);
      }
      await _scheduleRepository.deleteByMedicationId(id);

      // Finally delete the medication
      await _medicationRepository.delete(id);
    });

    medications.removeWhere((m) => m.id == id);
    _invalidateCache();
    notifyListeners();
  }

  /// Get medication with its schedules and times
  Future<MedicationWithSchedules?> getMedicationWithSchedules(
    String medicationId,
  ) async {
    return await _medicationRepository.findByIdWithSchedules(medicationId);
  }

  /// Get upcoming doses for a medication
  Future<List<MedicationScheduleTime>> getUpcomingDoses(
    String medicationId, {
    int horizonMs = 86400000,
  }) async {
    return await _scheduleTimeRepository.findUpcoming(
      medicationId,
      horizonMs: horizonMs,
    );
  }

  /// Create a medication schedule
  Future<MedicationSchedule> createSchedule(MedicationSchedule schedule) async {
    final scheduleId = await _scheduleRepository.create(schedule);

    // Return the schedule with the actual ID
    return schedule.id != scheduleId
        ? MedicationSchedule(
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
          )
        : schedule;
  }

  /// Create a medication schedule time
  Future<MedicationScheduleTime> createScheduleTime(
    MedicationScheduleTime scheduleTime,
  ) async {
    final scheduleTimeId = await _scheduleTimeRepository.create(scheduleTime);

    // Return the schedule time with the actual ID
    return scheduleTime.id != scheduleTimeId
        ? MedicationScheduleTime(
            id: scheduleTimeId,
            scheduleId: scheduleTime.scheduleId,
            timeLocal: scheduleTime.timeLocal,
            dosage: scheduleTime.dosage,
            doseAmount: scheduleTime.doseAmount,
            doseUnit: scheduleTime.doseUnit,
            instructions: scheduleTime.instructions,
            prn: scheduleTime.prn,
            sortOrder: scheduleTime.sortOrder,
            nextTriggerTs: scheduleTime.nextTriggerTs,
          )
        : scheduleTime;
  }

  /// Log medication intake
  Future<void> logIntake(MedicationIntakeLog intakeLog) async {
    await _intakeLogRepository.create(intakeLog);
  }

  /// Get intake logs for a medication
  Future<List<MedicationIntakeLog>> getIntakeLogs(
    String medicationId, {
    int? fromTs,
    int? toTs,
  }) async {
    return await _intakeLogRepository.findByMedicationId(
      medicationId,
      fromTs: fromTs,
      toTs: toTs,
    );
  }

  /// Search medications by name
  Future<List<Medication>> searchByName(String name) async {
    return await _medicationRepository.findByName(name, userId, profileId);
  }

  /// Get schedules for a medication
  Future<List<MedicationSchedule>> getSchedules(String medicationId) async {
    return await _scheduleRepository.findByMedicationId(medicationId);
  }

  /// Get schedule times for a schedule
  Future<List<MedicationScheduleTime>> getScheduleTimes(
    String scheduleId,
  ) async {
    return await _scheduleTimeRepository.findByScheduleId(scheduleId);
  }

  /// Delete a schedule and its times
  Future<void> deleteSchedule(String scheduleId) async {
    await _scheduleTimeRepository.deleteByScheduleId(scheduleId);
    await _scheduleRepository.delete(scheduleId);
  }

  /// Delete a schedule time
  Future<void> deleteScheduleTime(String scheduleTimeId) async {
    await _scheduleTimeRepository.delete(scheduleTimeId);
  }

  /// Get reminders for a medication
  Future<List<Reminder>> getReminders(String medicationId) async {
    return await _reminderRepository.findByMedicationId(medicationId, userId);
  }

  /// Create a reminder
  Future<void> createReminder(Reminder reminder) async {
    await _reminderRepository.create(reminder);
  }

  /// Delete reminders for a medication
  Future<void> deleteRemindersForMedication(String medicationId) async {
    await _reminderRepository.deleteByMedicationId(medicationId, userId);
  }

  /// Invalidate cache to force refresh on next load
  void _invalidateCache() {
    _lastLoadTime = null;
  }

  /// Check if data needs refresh
  bool get needsRefresh {
    return _lastLoadTime == null ||
        DateTime.now().difference(_lastLoadTime!) >= _cacheTimeout;
  }

  @override
  void dispose() {
    medications.clear();
    _invalidateCache();
    super.dispose();
  }
}

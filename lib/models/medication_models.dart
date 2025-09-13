import 'package:uuid/uuid.dart';

// Basic immutable models for normalized medication schema.

class Medication {
  final String id;
  final String userId;
  final String profileId;
  final String name;
  final String? notes;
  final String? medicationUrl;
  final int createdAt; // epoch ms
  final int updatedAt; // epoch ms

  Medication({
    required this.id,
    required this.userId,
    required this.profileId,
    required this.name,
    this.notes,
    this.medicationUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  Medication copyWith({
    String? name,
    String? notes,
    String? medicationUrl,
    int? updatedAt,
  }) => Medication(
    id: id,
    userId: userId,
    profileId: profileId,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    medicationUrl: medicationUrl ?? this.medicationUrl,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, dynamic> toDb() => {
    'id': id,
    'user_id': userId,
    'profile_id': profileId,
    'name': name,
    'notes': notes,
    'medication_url': medicationUrl,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  static Medication fromDb(Map<String, Object?> row) => Medication(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    profileId: row['profile_id'] as String,
    name: row['name'] as String,
    notes: row['notes'] as String?,
    medicationUrl: row['medication_url'] as String?,
    createdAt:
        (row['created_at'] as int?) ??
        (row['createdAt'] as int?) ??
        DateTime.now().millisecondsSinceEpoch,
    updatedAt:
        (row['updated_at'] as int?) ??
        (row['updatedAt'] as int?) ??
        DateTime.now().millisecondsSinceEpoch,
  );

  static Medication create({
    required String userId,
    required String profileId,
    required String name,
    String? notes,
    String? url,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Medication(
      id: const Uuid().v4(),
      userId: userId,
      profileId: profileId,
      name: name,
      notes: notes,
      medicationUrl: url,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class MedicationSchedule {
  final String id;
  final String medicationId;
  final String schedule; // human text: daily, every 8 hours
  final int? frequencyPerDay;
  final bool isForever;
  final int? startDate;
  final int? endDate;
  final String? daysOfWeek; // CSV
  final String? timezone; // IANA
  final bool reminderEnabled;

  MedicationSchedule({
    required this.id,
    required this.medicationId,
    required this.schedule,
    this.frequencyPerDay,
    required this.isForever,
    this.startDate,
    this.endDate,
    this.daysOfWeek,
    this.timezone,
    required this.reminderEnabled,
  });

  Map<String, dynamic> toDb() => {
    'id': id,
    'medication_id': medicationId,
    'schedule': schedule,
    'frequency_per_day': frequencyPerDay,
    'is_forever': isForever ? 1 : 0,
    'start_date': startDate,
    'end_date': endDate,
    'days_of_week': daysOfWeek,
    'timezone': timezone,
    'reminder_enabled': reminderEnabled ? 1 : 0,
  };

  static MedicationSchedule fromDb(Map<String, Object?> row) =>
      MedicationSchedule(
        id: row['id'] as String,
        medicationId: row['medication_id'] as String,
        schedule: row['schedule'] as String,
        frequencyPerDay: row['frequency_per_day'] as int?,
        isForever: (row['is_forever'] as int? ?? 0) == 1,
        startDate: row['start_date'] as int?,
        endDate: row['end_date'] as int?,
        daysOfWeek: row['days_of_week'] as String?,
        timezone: row['timezone'] as String?,
        reminderEnabled: (row['reminder_enabled'] as int? ?? 1) == 1,
      );

  static MedicationSchedule create({
    required String medicationId,
    required String schedule,
    int? frequencyPerDay,
    required bool isForever,
    int? startDate,
    int? endDate,
    String? daysOfWeek,
    String? timezone,
    bool reminderEnabled = true,
  }) => MedicationSchedule(
    id: const Uuid().v4(),
    medicationId: medicationId,
    schedule: schedule,
    frequencyPerDay: frequencyPerDay,
    isForever: isForever,
    startDate: startDate,
    endDate: endDate,
    daysOfWeek: daysOfWeek,
    timezone: timezone,
    reminderEnabled: reminderEnabled,
  );
}

class MedicationScheduleTime {
  final String id;
  final String scheduleId;
  final String timeLocal; // HH:MM
  final String? dosage;
  final double? doseAmount;
  final String? doseUnit;
  final String? instructions;
  final bool prn;
  final int? sortOrder;
  final int? nextTriggerTs;

  MedicationScheduleTime({
    required this.id,
    required this.scheduleId,
    required this.timeLocal,
    this.dosage,
    this.doseAmount,
    this.doseUnit,
    this.instructions,
    required this.prn,
    this.sortOrder,
    this.nextTriggerTs,
  });

  Map<String, dynamic> toDb() => {
    'id': id,
    'schedule_id': scheduleId,
    'time_local': timeLocal,
    'dosage': dosage,
    'dose_amount': doseAmount,
    'dose_unit': doseUnit,
    'instructions': instructions,
    'prn': prn ? 1 : 0,
    'sort_order': sortOrder,
    'next_trigger_ts': nextTriggerTs,
  };

  static MedicationScheduleTime fromDb(Map<String, Object?> row) =>
      MedicationScheduleTime(
        id: row['id'] as String,
        scheduleId: row['schedule_id'] as String,
        timeLocal: row['time_local'] as String,
        dosage: row['dosage'] as String?,
        doseAmount: (row['dose_amount'] as num?)?.toDouble(),
        doseUnit: row['dose_unit'] as String?,
        instructions: row['instructions'] as String?,
        prn: (row['prn'] as int? ?? 0) == 1,
        sortOrder: row['sort_order'] as int?,
        nextTriggerTs: row['next_trigger_ts'] as int?,
      );

  static MedicationScheduleTime create({
    required String scheduleId,
    required String timeLocal,
    String? dosage,
    double? doseAmount,
    String? doseUnit,
    String? instructions,
    bool prn = false,
    int? sortOrder,
  }) => MedicationScheduleTime(
    id: const Uuid().v4(),
    scheduleId: scheduleId,
    timeLocal: timeLocal,
    dosage: dosage,
    doseAmount: doseAmount,
    doseUnit: doseUnit,
    instructions: instructions,
    prn: prn,
    sortOrder: sortOrder,
    nextTriggerTs: null,
  );
}

class MedicationIntakeLog {
  final String id;
  final String scheduleTimeId;
  final int takenTs;
  final String status; // taken, missed, skipped, snoozed
  final double? actualDoseAmount;
  final String? actualDoseUnit;
  final String? notes;

  MedicationIntakeLog({
    required this.id,
    required this.scheduleTimeId,
    required this.takenTs,
    required this.status,
    this.actualDoseAmount,
    this.actualDoseUnit,
    this.notes,
  });

  Map<String, dynamic> toDb() => {
    'id': id,
    'schedule_time_id': scheduleTimeId,
    'taken_ts': takenTs,
    'status': status,
    'actual_dose_amount': actualDoseAmount,
    'actual_dose_unit': actualDoseUnit,
    'notes': notes,
  };

  static MedicationIntakeLog fromDb(Map<String, Object?> row) =>
      MedicationIntakeLog(
        id: row['id'] as String,
        scheduleTimeId: row['schedule_time_id'] as String,
        takenTs: row['taken_ts'] as int,
        status: row['status'] as String,
        actualDoseAmount: (row['actual_dose_amount'] as num?)?.toDouble(),
        actualDoseUnit: row['actual_dose_unit'] as String?,
        notes: row['notes'] as String?,
      );

  static MedicationIntakeLog create({
    required String scheduleTimeId,
    required String status,
    double? actualDoseAmount,
    String? actualDoseUnit,
    String? notes,
  }) => MedicationIntakeLog(
    id: const Uuid().v4(),
    scheduleTimeId: scheduleTimeId,
    takenTs: DateTime.now().millisecondsSinceEpoch,
    status: status,
    actualDoseAmount: actualDoseAmount,
    actualDoseUnit: actualDoseUnit,
    notes: notes,
  );
}

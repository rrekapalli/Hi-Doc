import '../models/medication_models.dart';
import '../models/health_entry.dart';
import '../models/message.dart';
import 'base_repository.dart';

/// Repository interface for user management
abstract class UserRepository extends Repository<User> {
  Future<User?> findByEmail(String email);
  Future<User?> findByProvider(String provider, String providerId);
  Future<List<User>> findAllByProvider(String provider);
}

/// Repository interface for medication management
abstract class MedicationRepository
    extends ProfileScopedRepository<Medication> {
  Future<List<Medication>> findByName(
    String name,
    String userId,
    String profileId,
  );
  Future<List<MedicationWithSchedules>> findWithSchedules(
    String userId,
    String profileId,
  );
  Future<MedicationWithSchedules?> findByIdWithSchedules(String id);
}

/// Repository interface for medication schedules
abstract class MedicationScheduleRepository
    extends Repository<MedicationSchedule> {
  Future<List<MedicationSchedule>> findByMedicationId(String medicationId);
  Future<void> deleteByMedicationId(String medicationId);
}

/// Repository interface for medication schedule times
abstract class MedicationScheduleTimeRepository
    extends Repository<MedicationScheduleTime> {
  Future<List<MedicationScheduleTime>> findByScheduleId(String scheduleId);
  Future<void> deleteByScheduleId(String scheduleId);
  Future<List<MedicationScheduleTime>> findUpcoming(
    String medicationId, {
    int horizonMs = 86400000,
  });
}

/// Repository interface for medication intake logs
abstract class MedicationIntakeLogRepository
    extends Repository<MedicationIntakeLog> {
  Future<List<MedicationIntakeLog>> findByScheduleTimeId(String scheduleTimeId);
  Future<List<MedicationIntakeLog>> findByMedicationId(
    String medicationId, {
    int? fromTs,
    int? toTs,
  });
  Future<List<MedicationIntakeLog>> findByDateRange(
    int fromTs,
    int toTs, {
    String? medicationId,
  });
}

/// Repository interface for health entries
abstract class HealthEntryRepository extends UserScopedRepository<HealthEntry> {
  Future<List<HealthEntry>> findByPersonId(String personId, String userId);
  Future<List<HealthEntry>> findByType(HealthEntryType type, String userId);
  Future<List<HealthEntry>> findByDateRange(
    int fromTs,
    int toTs,
    String userId,
  );
}

/// Repository interface for chat messages
abstract class MessageRepository extends UserScopedRepository<Message> {
  Future<List<Message>> findByPersonId(
    String personId,
    String userId, {
    int limit = 100,
  });
  Future<Message?> findLatest(String userId, {String? personId});
  Future<void> deleteByPersonId(String personId, String userId);
}

/// Repository interface for reports
abstract class ReportRepository extends UserScopedRepository<Report> {
  Future<List<Report>> findByType(String type, String userId);
  Future<List<Report>> findByDateRange(int fromTs, int toTs, String userId);
}

/// Repository interface for reminders
abstract class ReminderRepository extends UserScopedRepository<Reminder> {
  Future<List<Reminder>> findByMedicationId(String medicationId, String userId);
  Future<List<Reminder>> findActive(String userId);
  Future<void> deleteByMedicationId(String medicationId, String userId);
}

// Additional model classes that are needed but might not exist yet
class User {
  final String id;
  final String email;
  final String? name;
  final String provider; // 'google' or 'microsoft'
  final String? providerId;
  final int createdAt;
  final int updatedAt;
  final int? lastBackupAt;

  User({
    required this.id,
    required this.email,
    this.name,
    required this.provider,
    this.providerId,
    required this.createdAt,
    required this.updatedAt,
    this.lastBackupAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'name': name,
    'provider': provider,
    'provider_id': providerId,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'last_backup_at': lastBackupAt,
  };

  static User fromMap(Map<String, dynamic> map) => User(
    id: map['id'] as String,
    email: map['email'] as String,
    name: map['name'] as String?,
    provider: map['provider'] as String,
    providerId: map['provider_id'] as String?,
    createdAt: map['created_at'] as int,
    updatedAt: map['updated_at'] as int,
    lastBackupAt: map['last_backup_at'] as int?,
  );
}

class MedicationWithSchedules {
  final Medication medication;
  final List<MedicationSchedule> schedules;

  MedicationWithSchedules({required this.medication, required this.schedules});
}

class Report {
  final String id;
  final String userId;
  final String filePath;
  final String type;
  final Map<String, dynamic> data;
  final int uploadDate;

  Report({
    required this.id,
    required this.userId,
    required this.filePath,
    required this.type,
    required this.data,
    required this.uploadDate,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'file_path': filePath,
    'type': type,
    'data': data.toString(),
    'upload_date': uploadDate,
  };

  static Report fromMap(Map<String, dynamic> map) => Report(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    filePath: map['file_path'] as String,
    type: map['type'] as String,
    data: map['data'] is String
        ? {} // Parse JSON if needed
        : Map<String, dynamic>.from(map['data'] as Map),
    uploadDate: map['upload_date'] as int,
  );
}

class Reminder {
  final String id;
  final String userId;
  final String medicationId;
  final String title;
  final String time;
  final String? message;
  final String repeat;
  final String? days;
  final bool active;

  Reminder({
    required this.id,
    required this.userId,
    required this.medicationId,
    required this.title,
    required this.time,
    this.message,
    required this.repeat,
    this.days,
    required this.active,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'medication_id': medicationId,
    'title': title,
    'time': time,
    'message': message,
    'repeat': repeat,
    'days': days,
    'active': active ? 1 : 0,
  };

  static Reminder fromMap(Map<String, dynamic> map) => Reminder(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    medicationId: map['medication_id'] as String,
    title: map['title'] as String,
    time: map['time'] as String,
    message: map['message'] as String?,
    repeat: map['repeat'] as String,
    days: map['days'] as String?,
    active: (map['active'] as int? ?? 1) == 1,
  );
}

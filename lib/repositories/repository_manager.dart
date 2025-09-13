import 'local_database_service.dart';
import 'database_migration_service.dart';
import 'repository_interfaces.dart';
import 'medication_repositories.dart';
import 'reminder_repository.dart';
import 'health_entry_repository.dart';
import 'message_repository.dart';

/// Central manager for all repository instances
/// Provides a single point of access to all data repositories
/// Handles initialization and dependency injection
class RepositoryManager {
  static RepositoryManager? _instance;

  late final LocalDatabaseService _localDb;
  late final DatabaseMigrationService _migrationService;

  // Repository instances
  UserRepository? _userRepository;
  MedicationRepository? _medicationRepository;
  MedicationScheduleRepository? _medicationScheduleRepository;
  MedicationScheduleTimeRepository? _medicationScheduleTimeRepository;
  MedicationIntakeLogRepository? _medicationIntakeLogRepository;
  HealthEntryRepository? _healthEntryRepository;
  MessageRepository? _messageRepository;
  ReportRepository? _reportRepository;
  ReminderRepository? _reminderRepository;

  RepositoryManager._();

  /// Get the singleton instance
  static RepositoryManager get instance {
    _instance ??= RepositoryManager._();
    return _instance!;
  }

  /// Initialize the repository manager with database services
  Future<void> initialize() async {
    _localDb = LocalDatabaseService();
    await _localDb.initialize();

    _migrationService = DatabaseMigrationService(_localDb);
    await _migrationService.migrateFromLegacyDatabase();
  }

  /// Get the local database service
  LocalDatabaseService get localDb => _localDb;

  /// Get the migration service
  DatabaseMigrationService get migrationService => _migrationService;

  /// Get user repository
  UserRepository get userRepository {
    // Implementation will be created in later tasks
    throw UnimplementedError('UserRepository implementation not yet created');
  }

  /// Get medication repository
  MedicationRepository get medicationRepository {
    _medicationRepository ??= MedicationRepositoryImpl(localDb: _localDb);
    return _medicationRepository!;
  }

  /// Get medication schedule repository
  MedicationScheduleRepository get medicationScheduleRepository {
    _medicationScheduleRepository ??= MedicationScheduleRepositoryImpl(
      localDb: _localDb,
    );
    return _medicationScheduleRepository!;
  }

  /// Get medication schedule time repository
  MedicationScheduleTimeRepository get medicationScheduleTimeRepository {
    _medicationScheduleTimeRepository ??= MedicationScheduleTimeRepositoryImpl(
      localDb: _localDb,
    );
    return _medicationScheduleTimeRepository!;
  }

  /// Get medication intake log repository
  MedicationIntakeLogRepository get medicationIntakeLogRepository {
    _medicationIntakeLogRepository ??= MedicationIntakeLogRepositoryImpl(
      localDb: _localDb,
    );
    return _medicationIntakeLogRepository!;
  }

  /// Get health entry repository
  HealthEntryRepository get healthEntryRepository {
    _healthEntryRepository ??= HealthEntryRepositoryImpl(localDb: _localDb);
    return _healthEntryRepository!;
  }

  /// Get message repository
  MessageRepository get messageRepository {
    _messageRepository ??= MessageRepositoryImpl(localDb: _localDb);
    return _messageRepository!;
  }

  /// Get report repository
  ReportRepository get reportRepository {
    // Implementation will be created in future task
    throw UnimplementedError('ReportRepository implementation not yet created');
  }

  /// Get reminder repository
  ReminderRepository get reminderRepository {
    _reminderRepository ??= ReminderRepositoryImpl(localDb: _localDb);
    return _reminderRepository!;
  }

  /// Close all repositories and database connections
  Future<void> close() async {
    await _localDb.close();

    // Reset repository instances
    _userRepository = null;
    _medicationRepository = null;
    _medicationScheduleRepository = null;
    _medicationScheduleTimeRepository = null;
    _medicationIntakeLogRepository = null;
    _healthEntryRepository = null;
    _messageRepository = null;
    _reportRepository = null;
    _reminderRepository = null;
  }
}

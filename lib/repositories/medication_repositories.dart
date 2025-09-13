import '../models/medication_models.dart';
import '../repositories/base_repository_impl.dart';
import '../repositories/repository_interfaces.dart';
import '../repositories/local_database_service.dart';

/// Implementation of MedicationRepository using local SQLite database
class MedicationRepositoryImpl extends ProfileScopedRepositoryImpl<Medication>
    implements MedicationRepository {
  MedicationRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'medications');

  @override
  Map<String, dynamic> entityToMap(Medication entity) => entity.toDb();

  @override
  Medication mapToEntity(Map<String, dynamic> map) => Medication.fromDb(map);

  @override
  String? getDefaultOrderBy() => 'name ASC';

  @override
  Future<List<Medication>> findByName(
    String name,
    String userId,
    String profileId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND profile_id = ? AND name LIKE ?',
      whereArgs: [userId, profileId, '%$name%'],
      orderBy: 'name ASC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<MedicationWithSchedules>> findWithSchedules(
    String userId,
    String profileId,
  ) async {
    final medications = await findByProfileId(
      profileId,
      filters: {'user_id': userId},
    );
    final result = <MedicationWithSchedules>[];

    for (final medication in medications) {
      final schedules = await _getSchedulesForMedication(medication.id);
      result.add(
        MedicationWithSchedules(medication: medication, schedules: schedules),
      );
    }

    return result;
  }

  @override
  Future<MedicationWithSchedules?> findByIdWithSchedules(String id) async {
    final medication = await findById(id);
    if (medication == null) return null;

    final schedules = await _getSchedulesForMedication(id);
    return MedicationWithSchedules(
      medication: medication,
      schedules: schedules,
    );
  }

  /// Get schedules for a medication (helper method)
  Future<List<MedicationSchedule>> _getSchedulesForMedication(
    String medicationId,
  ) async {
    final rows = await database.query(
      'medication_schedules',
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      orderBy: 'start_date ASC',
    );

    return rows.map((row) => MedicationSchedule.fromDb(row)).toList();
  }
}

/// Implementation of MedicationScheduleRepository using local SQLite database
class MedicationScheduleRepositoryImpl
    extends BaseRepositoryImpl<MedicationSchedule>
    implements MedicationScheduleRepository {
  MedicationScheduleRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'medication_schedules');

  @override
  Map<String, dynamic> entityToMap(MedicationSchedule entity) => entity.toDb();

  @override
  MedicationSchedule mapToEntity(Map<String, dynamic> map) =>
      MedicationSchedule.fromDb(map);

  @override
  String? getDefaultOrderBy() => 'start_date ASC';

  @override
  Future<List<MedicationSchedule>> findByMedicationId(
    String medicationId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      orderBy: 'start_date ASC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<void> deleteByMedicationId(String medicationId) async {
    await database.delete(
      tableName,
      where: 'medication_id = ?',
      whereArgs: [medicationId],
    );
  }
}

/// Implementation of MedicationScheduleTimeRepository using local SQLite database
class MedicationScheduleTimeRepositoryImpl
    extends BaseRepositoryImpl<MedicationScheduleTime>
    implements MedicationScheduleTimeRepository {
  MedicationScheduleTimeRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'medication_schedule_times');

  @override
  Map<String, dynamic> entityToMap(MedicationScheduleTime entity) =>
      entity.toDb();

  @override
  MedicationScheduleTime mapToEntity(Map<String, dynamic> map) =>
      MedicationScheduleTime.fromDb(map);

  @override
  String? getDefaultOrderBy() => 'sort_order ASC, time_local ASC';

  @override
  Future<List<MedicationScheduleTime>> findByScheduleId(
    String scheduleId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'schedule_id = ?',
      whereArgs: [scheduleId],
      orderBy: 'sort_order ASC, time_local ASC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<void> deleteByScheduleId(String scheduleId) async {
    await database.delete(
      tableName,
      where: 'schedule_id = ?',
      whereArgs: [scheduleId],
    );
  }

  @override
  Future<List<MedicationScheduleTime>> findUpcoming(
    String medicationId, {
    int horizonMs = 86400000,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = now + horizonMs;

    final rows = await database.rawQuery(
      '''
      SELECT mst.*, ms.schedule, ms.reminder_enabled 
      FROM medication_schedule_times mst
      JOIN medication_schedules ms ON mst.schedule_id = ms.id
      WHERE ms.medication_id = ? 
        AND mst.next_trigger_ts IS NOT NULL 
        AND mst.next_trigger_ts BETWEEN ? AND ?
      ORDER BY mst.next_trigger_ts ASC 
      LIMIT 10
    ''',
      [medicationId, now, until],
    );

    return rows.map(mapToEntity).toList();
  }
}

/// Implementation of MedicationIntakeLogRepository using local SQLite database
class MedicationIntakeLogRepositoryImpl
    extends BaseRepositoryImpl<MedicationIntakeLog>
    implements MedicationIntakeLogRepository {
  MedicationIntakeLogRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'medication_intake_logs');

  @override
  Map<String, dynamic> entityToMap(MedicationIntakeLog entity) => entity.toDb();

  @override
  MedicationIntakeLog mapToEntity(Map<String, dynamic> map) =>
      MedicationIntakeLog.fromDb(map);

  @override
  String? getDefaultOrderBy() => 'taken_ts DESC';

  @override
  Future<List<MedicationIntakeLog>> findByScheduleTimeId(
    String scheduleTimeId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'schedule_time_id = ?',
      whereArgs: [scheduleTimeId],
      orderBy: 'taken_ts DESC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<MedicationIntakeLog>> findByMedicationId(
    String medicationId, {
    int? fromTs,
    int? toTs,
  }) async {
    final where = StringBuffer('ms.medication_id = ?');
    final args = <Object?>[medicationId];

    if (fromTs != null) {
      where.write(' AND mil.taken_ts >= ?');
      args.add(fromTs);
    }

    if (toTs != null) {
      where.write(' AND mil.taken_ts <= ?');
      args.add(toTs);
    }

    final rows = await database.rawQuery('''
      SELECT mil.* FROM medication_intake_logs mil
      JOIN medication_schedule_times mst ON mil.schedule_time_id = mst.id
      JOIN medication_schedules ms ON mst.schedule_id = ms.id
      WHERE ${where.toString()} 
      ORDER BY mil.taken_ts DESC
    ''', args);

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<MedicationIntakeLog>> findByDateRange(
    int fromTs,
    int toTs, {
    String? medicationId,
  }) async {
    String query;
    List<Object?> args;

    if (medicationId != null) {
      query = '''
        SELECT mil.* FROM medication_intake_logs mil
        JOIN medication_schedule_times mst ON mil.schedule_time_id = mst.id
        JOIN medication_schedules ms ON mst.schedule_id = ms.id
        WHERE mil.taken_ts BETWEEN ? AND ? AND ms.medication_id = ?
        ORDER BY mil.taken_ts DESC
      ''';
      args = [fromTs, toTs, medicationId];
    } else {
      query = '''
        SELECT * FROM medication_intake_logs
        WHERE taken_ts BETWEEN ? AND ?
        ORDER BY taken_ts DESC
      ''';
      args = [fromTs, toTs];
    }

    final rows = await database.rawQuery(query, args);
    return rows.map(mapToEntity).toList();
  }
}

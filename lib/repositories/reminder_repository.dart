import '../repositories/base_repository_impl.dart';
import '../repositories/repository_interfaces.dart';
import '../repositories/local_database_service.dart';

/// Implementation of ReminderRepository using local SQLite database
class ReminderRepositoryImpl extends UserScopedRepositoryImpl<Reminder>
    implements ReminderRepository {
  ReminderRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'reminders');

  @override
  Map<String, dynamic> entityToMap(Reminder entity) => entity.toMap();

  @override
  Reminder mapToEntity(Map<String, dynamic> map) => Reminder.fromMap(map);

  @override
  String? getDefaultOrderBy() => 'time ASC';

  @override
  Future<List<Reminder>> findByMedicationId(
    String medicationId,
    String userId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'medication_id = ? AND user_id = ?',
      whereArgs: [medicationId, userId],
      orderBy: 'time ASC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<Reminder>> findActive(String userId) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND active = 1',
      whereArgs: [userId],
      orderBy: 'time ASC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<void> deleteByMedicationId(String medicationId, String userId) async {
    await database.delete(
      tableName,
      where: 'medication_id = ? AND user_id = ?',
      whereArgs: [medicationId, userId],
    );
  }
}

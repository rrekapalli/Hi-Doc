import 'dart:convert';

import '../models/health_entry.dart';
import '../repositories/base_repository_impl.dart';
import '../repositories/repository_interfaces.dart';
import '../repositories/local_database_service.dart';

/// Implementation of HealthEntryRepository using local SQLite database
class HealthEntryRepositoryImpl extends UserScopedRepositoryImpl<HealthEntry>
    implements HealthEntryRepository {
  HealthEntryRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'health_entries');

  @override
  Map<String, dynamic> entityToMap(HealthEntry entity) => {
    'id': entity.id,
    'person_id': entity.personId,
    'user_id': null, // Will be set by the caller
    'timestamp': entity.timestamp.millisecondsSinceEpoch,
    'type': entity.type.name,
    'data': entity.toJson(),
  };

  @override
  HealthEntry mapToEntity(Map<String, dynamic> map) {
    final dataJson = map['data'];
    final data = dataJson is String
        ? _parseJsonString(dataJson)
        : Map<String, dynamic>.from(dataJson as Map);

    return HealthEntry.fromJson(data);
  }

  @override
  String? getDefaultOrderBy() => 'timestamp DESC';

  /// Parse JSON string data
  Map<String, dynamic> _parseJsonString(String jsonString) {
    try {
      // Handle the case where data might be stored as JSON string
      if (jsonString.startsWith('{')) {
        return Map<String, dynamic>.from(jsonDecode(jsonString));
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  @override
  Future<List<HealthEntry>> findByPersonId(
    String personId,
    String userId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND person_id = ?',
      whereArgs: [userId, personId],
      orderBy: 'timestamp DESC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<HealthEntry>> findByType(
    HealthEntryType type,
    String userId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND type = ?',
      whereArgs: [userId, type.name],
      orderBy: 'timestamp DESC',
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<List<HealthEntry>> findByDateRange(
    int fromTs,
    int toTs,
    String userId,
  ) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND timestamp BETWEEN ? AND ?',
      whereArgs: [userId, fromTs, toTs],
      orderBy: 'timestamp DESC',
    );

    return rows.map(mapToEntity).toList();
  }

  /// Enhanced create method that automatically sets user_id
  Future<String> createForUser(HealthEntry entity, String userId) async {
    final map = entityToMap(entity);
    map['user_id'] = userId;
    map['id'] = entity.id;

    await database.insert(tableName, map);

    return entity.id;
  }
}

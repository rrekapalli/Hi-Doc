import 'package:uuid/uuid.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'base_repository.dart';
import 'local_database_service.dart';

/// Base implementation for repositories using local SQLite database
/// Provides common CRUD operations and utility methods
abstract class BaseRepositoryImpl<T> implements Repository<T> {
  final LocalDatabaseService localDb;
  final String tableName;
  final Uuid _uuid = const Uuid();

  BaseRepositoryImpl({required this.localDb, required this.tableName});

  /// Get the database instance
  Database get database => localDb.database;

  /// Convert entity to database map
  Map<String, dynamic> entityToMap(T entity);

  /// Convert database map to entity
  T mapToEntity(Map<String, dynamic> map);

  /// Generate a new UUID for entities
  String generateId() => _uuid.v4();

  @override
  Future<String> create(T entity) async {
    final map = entityToMap(entity);
    final id = map['id'] as String? ?? generateId();
    map['id'] = id;

    await database.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return id;
  }

  @override
  Future<T?> findById(String id) async {
    final rows = await database.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return mapToEntity(rows.first);
  }

  @override
  Future<List<T>> findAll({Map<String, dynamic>? filters}) async {
    final whereClause = _buildWhereClause(filters);
    final whereArgs = _buildWhereArgs(filters);

    final rows = await database.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: getDefaultOrderBy(),
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<void> update(String id, T entity) async {
    final map = entityToMap(entity);
    map['id'] = id; // Ensure ID is correct
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await database.update(tableName, map, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> delete(String id) async {
    await database.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<bool> exists(String id) async {
    final rows = await database.query(
      tableName,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  @override
  Future<int> count({Map<String, dynamic>? filters}) async {
    final whereClause = _buildWhereClause(filters);
    final whereArgs = _buildWhereArgs(filters);

    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName${whereClause != null ? ' WHERE $whereClause' : ''}',
      whereArgs,
    );

    return result.first['count'] as int;
  }

  @override
  Future<List<T>> findPaged({
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
    String? orderBy,
  }) async {
    final offset = (page - 1) * limit;
    final whereClause = _buildWhereClause(filters);
    final whereArgs = _buildWhereArgs(filters);

    final rows = await database.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy ?? getDefaultOrderBy(),
      limit: limit,
      offset: offset,
    );

    return rows.map(mapToEntity).toList();
  }

  /// Build WHERE clause from filters map
  String? _buildWhereClause(Map<String, dynamic>? filters) {
    if (filters == null || filters.isEmpty) return null;

    final conditions = <String>[];

    for (final key in filters.keys) {
      final value = filters[key];

      if (value == null) {
        conditions.add('$key IS NULL');
      } else if (value is List) {
        if (value.isNotEmpty) {
          final placeholders = value.map((_) => '?').join(', ');
          conditions.add('$key IN ($placeholders)');
        }
      } else {
        conditions.add('$key = ?');
      }
    }

    return conditions.isEmpty ? null : conditions.join(' AND ');
  }

  /// Build WHERE arguments from filters map
  List<Object?>? _buildWhereArgs(Map<String, dynamic>? filters) {
    if (filters == null || filters.isEmpty) return null;

    final args = <Object?>[];

    for (final value in filters.values) {
      if (value == null) {
        // NULL values don't need parameters
        continue;
      } else if (value is List) {
        if (value.isNotEmpty) {
          args.addAll(value);
        }
      } else {
        args.add(value);
      }
    }

    return args.isEmpty ? null : args;
  }

  /// Get default ORDER BY clause for the repository
  /// Subclasses can override this to provide table-specific ordering
  String? getDefaultOrderBy() => null;

  /// Execute operations within a transaction
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    return localDb.transaction(action);
  }

  /// Execute batch operations
  Future<List<Object?>> batch(void Function(Batch batch) operations) async {
    return localDb.batch(operations);
  }
}

/// Base implementation for user-scoped repositories
abstract class UserScopedRepositoryImpl<T> extends BaseRepositoryImpl<T>
    implements UserScopedRepository<T> {
  UserScopedRepositoryImpl({
    required LocalDatabaseService localDb,
    required String tableName,
  }) : super(localDb: localDb, tableName: tableName);

  @override
  Future<List<T>> findByUserId(
    String userId, {
    Map<String, dynamic>? filters,
  }) async {
    final combinedFilters = <String, dynamic>{'user_id': userId, ...?filters};
    return findAll(filters: combinedFilters);
  }

  @override
  Future<int> countByUserId(
    String userId, {
    Map<String, dynamic>? filters,
  }) async {
    final combinedFilters = <String, dynamic>{'user_id': userId, ...?filters};
    return count(filters: combinedFilters);
  }

  @override
  Future<void> deleteByUserId(String userId) async {
    await database.delete(tableName, where: 'user_id = ?', whereArgs: [userId]);
  }
}

/// Base implementation for profile-scoped repositories
abstract class ProfileScopedRepositoryImpl<T>
    extends UserScopedRepositoryImpl<T>
    implements ProfileScopedRepository<T> {
  ProfileScopedRepositoryImpl({
    required LocalDatabaseService localDb,
    required String tableName,
  }) : super(localDb: localDb, tableName: tableName);

  @override
  Future<List<T>> findByProfileId(
    String profileId, {
    Map<String, dynamic>? filters,
  }) async {
    final combinedFilters = <String, dynamic>{
      'profile_id': profileId,
      ...?filters,
    };
    return findAll(filters: combinedFilters);
  }

  @override
  Future<int> countByProfileId(
    String profileId, {
    Map<String, dynamic>? filters,
  }) async {
    final combinedFilters = <String, dynamic>{
      'profile_id': profileId,
      ...?filters,
    };
    return count(filters: combinedFilters);
  }

  @override
  Future<void> deleteByProfileId(String profileId) async {
    await database.delete(
      tableName,
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }
}

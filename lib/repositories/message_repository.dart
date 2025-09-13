import 'dart:convert';

import '../models/message.dart';
import '../repositories/base_repository_impl.dart';
import '../repositories/repository_interfaces.dart';
import '../repositories/local_database_service.dart';

/// Implementation of MessageRepository using local SQLite database
class MessageRepositoryImpl extends UserScopedRepositoryImpl<Message>
    implements MessageRepository {
  MessageRepositoryImpl({required LocalDatabaseService localDb})
    : super(localDb: localDb, tableName: 'messages');

  @override
  Map<String, dynamic> entityToMap(Message entity) => {
    'id': entity.id,
    'user_id': null, // Will be set by the caller
    'person_id': null, // Will be set by the caller for group member messages
    'role': entity.role.name,
    'content': entity.content,
    'created_at': entity.createdAt.millisecondsSinceEpoch,
    'data': jsonEncode(entity.toJson()),
  };

  @override
  Message mapToEntity(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      role: MessageRole.values.firstWhere(
        (role) => role.name == map['role'],
        orElse: () => MessageRole.assistant,
      ),
      content: map['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  @override
  String? getDefaultOrderBy() => 'created_at ASC';

  @override
  Future<List<Message>> findByPersonId(
    String personId,
    String userId, {
    int limit = 100,
  }) async {
    final rows = await database.query(
      tableName,
      where: 'user_id = ? AND person_id = ?',
      whereArgs: [userId, personId],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows.map(mapToEntity).toList();
  }

  @override
  Future<Message?> findLatest(String userId, {String? personId}) async {
    final whereClause = personId != null
        ? 'user_id = ? AND person_id = ?'
        : 'user_id = ?';
    final whereArgs = personId != null ? [userId, personId] : [userId];

    final rows = await database.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: 1,
    );

    return rows.isNotEmpty ? mapToEntity(rows.first) : null;
  }

  @override
  Future<void> deleteByPersonId(String personId, String userId) async {
    await database.delete(
      tableName,
      where: 'user_id = ? AND person_id = ?',
      whereArgs: [userId, personId],
    );
  }

  /// Enhanced create method that automatically sets user_id and person_id
  Future<String> createForUser(
    Message entity,
    String userId, {
    String? personId,
  }) async {
    final map = entityToMap(entity);
    map['user_id'] = userId;
    map['person_id'] = personId;
    map['id'] = entity.id;

    await database.insert(tableName, map);

    return entity.id;
  }
}

import '../models/message.dart';
import '../repositories/repository_manager.dart';

/// Bridge service for message operations
/// Provides enhanced methods that handle user_id and person_id automatically
/// This bridges the gap between the generic repository interface and specific chat needs
class MessageRepositoryBridge {
  final RepositoryManager _repoManager;

  MessageRepositoryBridge(this._repoManager);

  /// Create a message with user and person context
  Future<String> createMessageForUser(
    Message message,
    String userId, {
    String? personId,
  }) async {
    // Create a custom map with user context
    final messageRepo =
        _repoManager.messageRepository as dynamic; // Access concrete type

    final map = <String, dynamic>{
      'id': message.id,
      'user_id': userId,
      'person_id': personId,
      'role': message.role.name,
      'content': message.content,
      'created_at': message.createdAt.millisecondsSinceEpoch,
    };

    await messageRepo.database.insert('messages', map);
    return message.id;
  }

  /// Get messages for user with optional person filter
  Future<List<Message>> getMessagesForUser(
    String userId, {
    String? personId,
    int limit = 100,
  }) async {
    return await _repoManager.messageRepository.findByPersonId(
      personId ?? '',
      userId,
      limit: limit,
    );
  }

  /// Get all messages for a user (across all persons/profiles)
  Future<List<Message>> getAllMessagesForUser(
    String userId, {
    int limit = 100,
  }) async {
    return await _repoManager.messageRepository.findByUserId(userId);
  }

  /// Delete messages by person for a user
  Future<void> deleteMessagesByPerson(String personId, String userId) async {
    await _repoManager.messageRepository.deleteByPersonId(personId, userId);
  }

  /// Get latest message for user/person
  Future<Message?> getLatestMessage(String userId, {String? personId}) async {
    return await _repoManager.messageRepository.findLatest(
      userId,
      personId: personId,
    );
  }
}

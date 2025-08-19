class Conversation {
  final String id;
  final String? title;
  final String type;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? memberNames;

  Conversation({
    required this.id,
    this.title,
    required this.type,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.memberNames,
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      title: map['title'] as String?,
      type: map['type'] as String,
      isDefault: map['is_default'] == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_at'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
        : null,
      unreadCount: map['unread_count'] as int? ?? 0,
      memberNames: map['member_names'] as String?,
    );
  }
}

class ConversationMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String role;
  final String content;
  final String contentType;
  final DateTime createdAt;
  final bool isMe;
  final String? interpretationJson;
  final int processed;
  final String? storedRecordId;

  ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.role,
    required this.content,
    required this.contentType,
    required this.createdAt,
    required this.isMe,
    this.interpretationJson,
    this.processed = 0,
    this.storedRecordId,
  });

  factory ConversationMessage.fromMap(Map<String, dynamic> map) {
    return ConversationMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String? ?? 'Unknown',
      role: map['role'] as String,
      content: map['content'] as String,
      contentType: map['content_type'] as String? ?? 'text',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isMe: map['is_me'] == 1,
      interpretationJson: map['interpretation_json'] as String?,
      processed: map['processed'] as int? ?? 0,
      storedRecordId: map['stored_record_id'] as String?,
    );
  }
}

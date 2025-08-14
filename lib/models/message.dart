enum MessageRole { user, assistant, system }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  static int _counter = 0;
  static String _genId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  Message({
    required this.id,
    required this.role,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Optional helpers (remove if unused)
  Message copyWith({String? id, MessageRole? role, String? content, DateTime? createdAt}) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Message.user(String text, {String? id}) =>
      Message(id: id ?? _genId(), role: MessageRole.user, content: text);

  factory Message.assistant(String text, {String? id}) =>
      Message(id: id ?? _genId(), role: MessageRole.assistant, content: text);

  // --- JSON helpers added below ---
  static MessageRole _roleFromString(String v) {
    switch (v.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
      case 'ai':
      case 'bot':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.assistant; // fallback
    }
  }

  static String _roleToString(MessageRole r) {
    switch (r) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': _roleToString(role),
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id']?.toString() ?? '',
        role: _roleFromString(json['role']?.toString() ?? 'assistant'),
        content: json['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );

  static List<Message> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Message.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }
}

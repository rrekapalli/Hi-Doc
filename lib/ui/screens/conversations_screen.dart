import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/database_service.dart';
import '../common/hi_doc_app_bar.dart';
import './conversation_detail_screen.dart';
import 'user_settings_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late Future<List<Map<String, dynamic>>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  void _loadConversations() {
    final db = context.read<DatabaseService>();
    _conversationsFuture = db.getConversations();
  }

  void _createNewConversation() {
    // TODO: Show dialog to select users and create conversation
  }

  String _getConversationTitle(Map<String, dynamic> conversation) {
    return conversation['title'] ?? 'Chat with ${conversation['member_names']}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Messages',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading conversations: ${snapshot.error}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            );
          }

          final conversations = snapshot.data ?? [];
          
          if (conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: theme.colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onBackground.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _createNewConversation,
                    icon: const Icon(Icons.add),
                    label: const Text('Start a new chat'),
                  ),
                ],
              ),
            );
          }

          // Sort conversations: "Me" first, then by last message time
          final sortedConversations = List.of(conversations)..sort((a, b) {
            if ((a['is_default'] ?? 0) == 1) return -1;
            if ((b['is_default'] ?? 0) == 1) return 1;
            
            final aTime = a['last_message_at'] as int? ?? 0;
            final bTime = b['last_message_at'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedConversations.length,
            itemBuilder: (context, index) {
              final conversation = sortedConversations[index];
              final isDefault = (conversation['is_default'] ?? 0) == 1;
              final lastMessageContent = conversation['last_message'] as String?;
              final lastMessageAt = conversation['last_message_at'] as int?;
              final unreadCount = conversation['unread_count'] as int? ?? 0;
              final lastMessageTime = lastMessageAt != null 
                ? DateTime.fromMillisecondsSinceEpoch(lastMessageAt)
                : null;

              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConversationDetailScreen(
                      conversationId: conversation['id'] as String,
                      title: _getConversationTitle(conversation),
                      conversationType: conversation['type'] as String? ?? 'direct',
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Avatar or group icon
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isDefault 
                          ? theme.colorScheme.primary 
                          : theme.colorScheme.primary.withOpacity(0.1),
                        child: Icon(
                          isDefault
                            ? Icons.person_pin
                            : conversation['type'] == 'group' 
                              ? Icons.group
                              : Icons.person,
                          color: isDefault 
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Conversation details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _getConversationTitle(conversation),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: unreadCount > 0 
                                        ? FontWeight.bold 
                                        : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (lastMessageTime != null)
                                  Text(
                                    timeago.format(lastMessageTime),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onBackground.withOpacity(0.5),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    lastMessageContent ?? 'No messages yet',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onBackground.withOpacity(0.7),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      unreadCount.toString(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewConversation,
        child: const Icon(Icons.chat),
      ),
    );
  }
}

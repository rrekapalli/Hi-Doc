import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../screens/user_settings_screen.dart';
import '../common/hi_doc_app_bar.dart';
import '../../models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
  // Set a default profile ID for the main chat screen
  chatProvider.setCurrentProfile('default-profile');
  chatProvider.loadMessages('default-profile');
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Chat',
        actions: [
          // Debug button for testing message persistence
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () async {
              final chat = context.read<ChatProvider>();
              await chat.debugMessageCounts();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Check console for message counts'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            tooltip: 'Debug Message Counts',
          ),
          // Clear messages button for testing
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Messages'),
                  content: const Text('This will delete all chat messages. Are you sure?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && mounted) {
                final chat = context.read<ChatProvider>();
                await chat.clearAllMessages();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All messages cleared'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            tooltip: 'Clear All Messages',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: chat.messages.length,
                itemBuilder: (ctx, i) {
                  final msg = chat.messages[chat.messages.length - 1 - i];
                  final loading = chat.isLoading(msg.id);
                  return _buildChatBubble(msg, loading, context);
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Type your health update...',
                          hintStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: _submit,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => _submit(_controller.text),
                      icon: Icon(
                        Icons.send_rounded,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      tooltip: 'Send message',
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool loading, BuildContext context) {
    final isUser = msg.isUser;
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: IntrinsicWidth(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isUser 
                    ? const Color(0xFFE3F2FD) // Light blue for user messages
                    : const Color(0xFFF5F5F5), // Light gray for AI messages
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.text,
                      style: TextStyle(
                        color: isUser 
                          ? const Color(0xFF1565C0) // Dark blue for user text
                          : const Color(0xFF424242), // Dark gray for AI text
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isUser 
                                  ? const Color(0xFF1565C0).withValues(alpha: 0.7)
                                  : const Color(0xFF666666),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Analyzing...',
                            style: TextStyle(
                              fontSize: 11,
                              color: isUser 
                                ? const Color(0xFF1565C0).withValues(alpha: 0.7)
                                : const Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (msg.parsedEntry != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 12,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Health data recorded',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (msg.aiErrorReason != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 12,
                              color: Colors.orange[700],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Message stored',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Trend analysis buttons
                    if (msg.showTrendButtons && msg.trendType != null && msg.trendCategory != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => _handleTrendResponse(msg.id, true, msg.trendType!, msg.trendCategory!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: const Size(60, 32),
                            ),
                            child: const Text('Yes', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _handleTrendResponse(msg.id, false, msg.trendType!, msg.trendCategory!),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: const Size(60, 32),
                            ),
                            child: const Text('No', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                    // Timestamp and status indicator
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(msg.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isUser 
                              ? const Color(0xFF1565C0).withValues(alpha: 0.5)
                              : const Color(0xFF666666).withValues(alpha: 0.7),
                          ),
                        ),
                        if (!loading && isUser) ...[
                          const SizedBox(width: 4),
                          _buildStatusIcon(msg, theme),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 12,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.person_outline,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildStatusIcon(ChatMessage msg, ThemeData theme) {
    if (msg.parseSource == 'ai') {
      return Icon(
        Icons.smart_toy,
        size: 12,
        color: const Color(0xFF1565C0).withValues(alpha: 0.6),
      );
    } else if (msg.parseFailed) {
      return Icon(
        Icons.check,
        size: 12,
        color: const Color(0xFF1565C0).withValues(alpha: 0.4),
      );
    } else {
      return Icon(
        Icons.done_all,
        size: 12,
        color: const Color(0xFF1565C0).withValues(alpha: 0.6),
      );
    }
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    context.read<ChatProvider>().sendMessage(value.trim());
    _controller.clear();
  }

  void _handleTrendResponse(String messageId, bool showTrend, String type, String category) {
    context.read<ChatProvider>().handleTrendResponse(messageId, showTrend, type, category);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}





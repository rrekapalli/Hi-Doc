import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../common/hi_doc_app_bar.dart';
import '../../models/chat_message.dart';

class ConversationDetailScreen extends StatefulWidget {
  final String conversationId;
  final String title;
  final String conversationType;
  final bool embedded; // when true, render without Scaffold/AppBar

  const ConversationDetailScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.conversationType = 'direct',
    this.embedded = false,
  });

  @override
  State<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      if (chatProvider.currentConversationId != widget.conversationId) {
        chatProvider.setCurrentConversation(widget.conversationId);
        chatProvider.loadMessages(widget.conversationId);
      } else {
        // If same conversation, ensure messages are loaded (only if empty)
        if (chatProvider.messages.isEmpty) {
          chatProvider.loadMessages(widget.conversationId);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ConversationDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setCurrentConversation(widget.conversationId);
      chatProvider.loadMessages(widget.conversationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    final content = Column(
      children: [
        Expanded(
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
        _buildComposer(context),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: widget.title,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug Message Counts',
            onPressed: () async {
              final chat = context.read<ChatProvider>();
              await chat.debugMessageCounts();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Check console for message counts'), duration: Duration(seconds: 2)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear All Messages',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Messages'),
                  content: const Text('This will delete all chat messages. Are you sure?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear All')),
                  ],
                ),
              );
              if (confirmed == true && mounted) {
                final chat = context.read<ChatProvider>();
                await chat.clearAllMessages();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All messages cleared'), duration: Duration(seconds: 2)),
                );
              }
            },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Type your health update...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _submit(_controller.text),
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send message',
            )
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool loading, BuildContext context) {
    final isUser = msg.isUser;
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final maxBubbleWidth = box.maxWidth * 0.72;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.smart_toy_outlined, size: 14, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: isUser ? const Color(0xFF1565C0) : const Color(0xFF424242),
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                          if (loading)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  ),
                                  SizedBox(width: 6),
                                  Text('Analyzing...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          if (msg.parsedEntry != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline, size: 12, color: Colors.green[700]),
                                  const SizedBox(width: 3),
                                  Text('Health data recorded', style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          if (msg.aiErrorReason != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.info_outline, size: 12, color: Colors.orange),
                                  const SizedBox(width: 3),
                                  const Text(
                                    'Message stored',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(msg.timestamp),
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                ),
                                if (!loading && isUser) ...[
                                  const SizedBox(width: 4),
                                  _buildStatusIcon(msg, theme),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 6),
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.person_outline, size: 14, color: theme.colorScheme.primary),
              ),
            ],
          ],
        ),
      );
    });
  }

  String _formatTime(DateTime timestamp) {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildStatusIcon(ChatMessage msg, ThemeData theme) {
    if (msg.parseSource == 'ai') {
      return const Icon(Icons.smart_toy, size: 12, color: Color(0xFF1565C0));
    } else if (msg.parseFailed) {
      return Icon(Icons.check, size: 12, color: const Color(0xFF1565C0).withOpacity(0.4));
    } else {
      return const Icon(Icons.done_all, size: 12, color: Color(0xFF1565C0));
    }
  }

  void _submit(String value) {
    if (value.trim().isEmpty) return;
    context.read<ChatProvider>().sendMessage(value.trim());
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

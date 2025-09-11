import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../providers/chat_provider.dart';
import '../common/hi_doc_app_bar.dart';
import '../../models/chat_message.dart';

class ProfileConversationsScreen extends StatefulWidget {
  final String profileId;
  final String title;
  final String profileType;
  final bool embedded; // when true, render without Scaffold/AppBar

  const ProfileConversationsScreen({
    super.key,
    required this.profileId,
    required this.title,
    this.profileType = 'direct',
    this.embedded = false,
  });

  @override
  State<ProfileConversationsScreen> createState() =>
      _ProfileConversationsScreenState();
}

class _ProfileConversationsScreenState
    extends State<ProfileConversationsScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      if (chatProvider.currentProfileId != widget.profileId) {
        chatProvider.setCurrentProfile(widget.profileId);
        chatProvider.loadMessages(widget.profileId);
      } else {
        if (chatProvider.messages.isEmpty) {
          chatProvider.loadMessages(widget.profileId);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProfileConversationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.setCurrentProfile(widget.profileId);
      chatProvider.loadMessages(widget.profileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    Widget messagesBody;
    if (chat.loadingMessages && chat.messages.isEmpty) {
      messagesBody = const Center(child: CircularProgressIndicator());
    } else if (!chat.loadingMessages && chat.messages.isEmpty) {
      messagesBody = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No messages yet. Share a health update to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
        ),
      );
    } else {
      messagesBody = ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: chat.messages.length,
        itemBuilder: (ctx, i) {
          final msg = chat.messages[chat.messages.length - 1 - i];
          final loading = chat.isLoading(msg.id);
          return _buildChatBubble(msg, loading, context);
        },
      );
    }

    final content = Column(
      children: [
        Expanded(child: messagesBody),
        _buildComposer(context),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: HiDocAppBar(pageTitle: widget.title),
      body: content,
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool loading, BuildContext context) {
    final isUser = msg.isUser;
    final theme = Theme.of(context);
    // Adaptive width: only cap the maximum width; let content drive actual size.
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: IntrinsicWidth(
              // shrink-to-fit width up to maxWidth
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isUser
                      ? const Color(0xFFE3F2FD)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Check if it's an AI response and contains HTML
                      if (isUser || !_containsHtml(msg.text))
                        // Plain text for user messages or non-HTML AI responses
                        Text(
                          msg.text,
                          style: TextStyle(
                            color: isUser
                                ? const Color(0xFF1565C0)
                                : const Color(0xFF424242),
                            fontSize: 14,
                            height: 1.3,
                          ),
                          softWrap: true,
                        )
                      else
                        // HTML content for AI responses
                        Html(
                          data: msg.text,
                          style: {
                            "body": Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                              fontSize: FontSize(14),
                              color: const Color(0xFF424242),
                              lineHeight: LineHeight(1.3),
                            ),
                            "h2": Style(
                              color: const Color(0xFF1565C0),
                              fontSize: FontSize(16),
                              fontWeight: FontWeight.bold,
                              margin: Margins.only(top: 12, bottom: 8),
                            ),
                            "h3": Style(
                              color: const Color(0xFF1565C0),
                              fontSize: FontSize(15),
                              fontWeight: FontWeight.w600,
                              margin: Margins.only(top: 10, bottom: 6),
                            ),
                            "p": Style(margin: Margins.only(bottom: 8)),
                            "strong": Style(fontWeight: FontWeight.bold),
                            "em": Style(fontStyle: FontStyle.italic),
                            "ul": Style(
                              margin: Margins.only(bottom: 8),
                              padding: HtmlPaddings.only(left: 16),
                            ),
                            "li": Style(margin: Margins.only(bottom: 4)),
                            ".medical-response": Style(
                              backgroundColor: const Color(0xFFF8F9FA),
                              padding: HtmlPaddings.all(12),
                              margin: Margins.only(bottom: 8),
                            ),
                            ".ranges-box": Style(
                              backgroundColor: const Color(0xFFE3F2FD),
                              border: Border(
                                left: BorderSide(
                                  color: const Color(0xFF2196F3),
                                  width: 4,
                                ),
                              ),
                              padding: HtmlPaddings.all(12),
                              margin: Margins.only(top: 8, bottom: 8),
                            ),
                            ".alert-box": Style(
                              backgroundColor: const Color(0xFFFFF3E0),
                              border: Border(
                                left: BorderSide(
                                  color: const Color(0xFFFF9800),
                                  width: 4,
                                ),
                              ),
                              padding: HtmlPaddings.all(12),
                              margin: Margins.only(top: 8, bottom: 8),
                            ),
                            ".warning-box": Style(
                              backgroundColor: const Color(0xFFFFEBEE),
                              border: Border(
                                left: BorderSide(
                                  color: const Color(0xFFF44336),
                                  width: 4,
                                ),
                              ),
                              padding: HtmlPaddings.all(12),
                              margin: Margins.only(top: 8, bottom: 8),
                            ),
                            ".disclaimer": Style(
                              backgroundColor: const Color(0xFFF5F5F5),
                              border: Border.all(
                                color: const Color(0xFFDDDDDD),
                              ),
                              padding: HtmlPaddings.all(12),
                              margin: Margins.only(top: 16),
                              fontSize: FontSize(12),
                            ),
                            ".side-effects-list li": Style(
                              backgroundColor: Colors.white,
                              border: Border(
                                left: BorderSide(
                                  color: const Color(0xFF4CAF50),
                                  width: 3,
                                ),
                              ),
                              padding: HtmlPaddings.all(8),
                              margin: Margins.only(bottom: 6),
                            ),
                          },
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Analyzing...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (msg.parsedEntry != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
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
                      if (msg.aiErrorReason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 12,
                                color: Colors.orange,
                              ),
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
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
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
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildStatusIcon(ChatMessage msg, ThemeData theme) {
    if (msg.parseSource == 'ai') {
      return const Icon(Icons.smart_toy, size: 12, color: Color(0xFF1565C0));
    } else if (msg.parseFailed) {
      return Icon(
        Icons.check,
        size: 12,
        color: const Color(0xFF1565C0).withValues(alpha: 0.4),
      );
    } else {
      return const Icon(Icons.done_all, size: 12, color: Color(0xFF1565C0));
    }
  }

  /// Helper method to detect if text contains HTML content
  bool _containsHtml(String text) {
    return text.contains('<') &&
        text.contains('>') &&
        (text.contains('<div') ||
            text.contains('<h') ||
            text.contains('<p') ||
            text.contains('<ul') ||
            text.contains('<li') ||
            text.contains('<strong') ||
            text.contains('<em') ||
            text.contains('class='));
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

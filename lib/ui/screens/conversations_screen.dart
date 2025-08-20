import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/database_service.dart';
import '../common/hi_doc_app_bar.dart';
import '../common/contact_search_dialog.dart';
import './conversation_detail_screen.dart';
import 'user_settings_screen.dart';
import '../../providers/chat_provider.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late Future<List<Map<String, dynamic>>> _conversationsFuture;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allConversations = [];
  List<Map<String, dynamic>> _filteredConversations = [];
  bool _isSearching = false;
  String? _selectedId; // for split view
  bool _initialSelectionScheduled = false; // guard to avoid repeated scheduling

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadConversations() {
    final db = context.read<DatabaseService>();
    _conversationsFuture = db.getConversations();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredConversations = _allConversations;
        _isSearching = false;
      });
    } else {
      setState(() {
        _filteredConversations = _allConversations.where((conversation) {
          final title = _getConversationTitle(conversation).toLowerCase();
          final memberNames = (conversation['member_names'] as String?)?.toLowerCase() ?? '';
          final lastMessage = (conversation['last_message'] as String?)?.toLowerCase() ?? '';
          
          return title.contains(query) || 
                 memberNames.contains(query) || 
                 lastMessage.contains(query);
      }).toList();
        _isSearching = true;
      });
    }
  }

  void _createNewConversation() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const ContactSearchDialog(),
    );
    
    if (result != null && mounted) {
      // Refresh the conversations list
      _loadConversations();
      setState(() {});
      
      // Navigate to the new conversation
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(
            conversationId: result['conversationId'] as String,
            title: result['title'] as String,
            conversationType: result['type'] as String,
          ),
        ),
      );
    }
  }

  String _getConversationTitle(Map<String, dynamic> conversation) {
    return conversation['title'] ?? 'Chat with ${conversation['member_names']}';
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> conversations) {
    final sortedConversations = List.of(conversations)..sort((a, b) {
      if ((a['is_default'] ?? 0) == 1) return -1;
      if ((b['is_default'] ?? 0) == 1) return 1;
      final aTime = a['last_message_at'] as int? ?? 0;
      final bTime = b['last_message_at'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
    return sortedConversations;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
  return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Messages',
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  _filteredConversations = _allConversations;
                  _isSearching = false;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          if (_isSearching)
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search existing conversations...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          
          // Responsive: on wide screens show split view (30/70)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900; // web/desktop threshold
                if (!wide) {
                  return _isSearching ? _buildSearchResults() : _buildConversationsList();
                }

                return Row(
                  children: [
                    // Left pane: conversations list (30%)
                    SizedBox(
                      width: constraints.maxWidth * 0.30,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border(
                            right: BorderSide(color: theme.dividerColor.withOpacity(.5)),
                          ),
                        ),
                        child: _buildSplitConversationsList(),
                      ),
                    ),
                    // Right pane: conversation detail (70%)
                    Expanded(
                      child: _buildSplitDetailPane(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewConversation,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildSearchResults() {
    final theme = Theme.of(context);
    
    if (_filteredConversations.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onBackground.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords or tap + to start a new chat',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onBackground.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    return _buildConversationsListView(_filteredConversations);
  }

  Widget _buildConversationsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _conversationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading conversations: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final conversations = snapshot.data ?? [];
        _allConversations = conversations;
        
        if (!_isSearching) {
          _filteredConversations = conversations;
        }
        
        if (conversations.isEmpty) {
          return _buildEmptyState();
        }

        return _buildConversationsListView(conversations);
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
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

  Widget _buildConversationsListView(List<Map<String, dynamic>> conversations) {
    // Sort conversations: "Me" first, then by last message time
    final sortedConversations = _sorted(conversations);

  return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedConversations.length,
      itemBuilder: (context, index) {
        final conversation = sortedConversations[index];
    return _buildConversationTile(conversation);
      },
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final theme = Theme.of(context);
    final isDefault = (conversation['is_default'] ?? 0) == 1;
    final lastMessageContent = conversation['last_message'] as String?;
    final lastMessageAt = conversation['last_message_at'] as int?;
    final unreadCount = conversation['unread_count'] as int? ?? 0;
    final lastMessageTime = lastMessageAt != null 
      ? DateTime.fromMillisecondsSinceEpoch(lastMessageAt)
      : null;
    final isSelected = _selectedId == conversation['id'];

    return InkWell(
      onTap: () {
        final wide = MediaQuery.of(context).size.width >= 900;
        if (wide) {
          final id = conversation['id'] as String;
          setState(() {
            _selectedId = id;
          });
          // In split view, the detail pane will load messages using its own initState
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationDetailScreen(
                conversationId: conversation['id'] as String,
                title: _getConversationTitle(conversation),
                conversationType: conversation['type'] as String? ?? 'direct',
              ),
            ),
          );
        }
      },
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
                            fontWeight: (unreadCount > 0 || isSelected)
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
  }

  // Split view helpers
  Widget _buildSplitConversationsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _conversationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final conversations = snapshot.data ?? [];
        _allConversations = conversations;
        if (!_isSearching) _filteredConversations = conversations;

        // Default selection: visible first item (sorted)
        if (!_initialSelectionScheduled && _selectedId == null && conversations.isNotEmpty) {
          _initialSelectionScheduled = true;
          final sorted = _sorted(conversations);
          final initialId = sorted.first['id'] as String;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedId = initialId;
            });
            // The right pane's ConversationDetailScreen will handle loading
          });
        }
        if (conversations.isEmpty) {
          return _buildEmptyState();
        }
        return _buildConversationsListView(conversations);
      },
    );
  }

  Widget _buildSplitDetailPane() {
    if (_selectedId == null) {
      return Center(
        child: Text(
          'Select a conversation',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    // Find the selected conversation's title/type for header
    final conv = _allConversations.firstWhere(
      (c) => c['id'] == _selectedId,
      orElse: () => {'title': 'Conversation', 'type': 'direct'},
    );
    return ConversationDetailScreen(
      conversationId: _selectedId!,
      title: _getConversationTitle(conv),
      conversationType: conv['type'] as String? ?? 'direct',
      embedded: true,
    );
  }
}

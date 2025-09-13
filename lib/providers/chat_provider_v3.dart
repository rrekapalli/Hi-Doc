import 'package:flutter/foundation.dart';
import 'dart:async';
import '../repositories/repository_manager.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/message_repository_bridge.dart';
import '../services/enhanced_ai_service.dart';
import '../services/ai_service_client.dart';
import 'settings_provider.dart';

/// Enhanced ChatProvider with AI rate limiting and external service integration
/// This version includes proper AI service integration with rate limiting and health data parsing
class ChatProviderV3 extends ChangeNotifier {
  final MessageRepositoryBridge _messageBridge;
  final EnhancedAIService _aiService;
  final AuthService? authService;
  SettingsProvider? settings;

  List<Message> _messages = [];
  final Set<String> _loading = {};
  String? _currentProfileId;
  String? _currentUserId;
  bool _loadingMessages = false;

  // AI usage tracking
  Map<String, int> _usageStats = {};
  bool _lastRequestRateLimited = false;

  List<Message> get messages => List.unmodifiable(_messages);
  String? get currentProfileId => _currentProfileId;
  String? get currentUserId => _currentUserId;
  bool get loadingMessages => _loadingMessages;
  Map<String, int> get usageStats => Map.unmodifiable(_usageStats);
  bool get isRateLimited => _lastRequestRateLimited;

  ChatProviderV3({
    required RepositoryManager repoManager,
    this.authService,
    String? openAiApiKey,
    String? anthropicApiKey,
    String? customBackendUrl,
  }) : _messageBridge = MessageRepositoryBridge(repoManager),
       _aiService = EnhancedAIService(
         repoManager: repoManager,
         openAiApiKey: openAiApiKey,
         anthropicApiKey: anthropicApiKey,
         customBackendUrl: customBackendUrl,
       );

  void attachSettings(SettingsProvider s) {
    settings = s;
  }

  bool isLoading(String id) => _loading.contains(id);

  void setCurrentProfile(String profileId) {
    _currentProfileId = profileId;
    _loadMessages(); // Load messages for the new profile
  }

  void setCurrentUser(String userId) {
    _currentUserId = userId;
    _loadUsageStats(); // Load usage stats for the new user
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentUserId == null) {
      if (kDebugMode) {
        debugPrint('Error: No user ID available');
      }
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();

    if (kDebugMode) {
      debugPrint('Processing user message: $text');
    }

    try {
      // Create user message
      final userMessage = Message.user(text, id: id);
      _messages.add(userMessage);
      notifyListeners();

      // Store message in repository
      await _messageBridge.createMessageForUser(
        userMessage,
        _currentUserId!,
        personId: _currentProfileId,
      );

      // Process message asynchronously to avoid blocking UI
      unawaited(_processMessageWithAI(text, id));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to add message to chat: $e');
      }
      return;
    }
  }

  Future<void> _processMessageWithAI(String text, String messageId) async {
    if (_currentUserId == null) return;

    _loading.add(messageId);
    notifyListeners();

    try {
      // Convert recent messages to conversation history
      final conversationHistory = _messages
          .where((msg) => msg.id != messageId) // Exclude current message
          .take(10) // Limit context to last 10 messages
          .map(
            (msg) => ChatMessage(
              role: msg.role == MessageRole.user ? 'user' : 'assistant',
              content: msg.content,
            ),
          )
          .toList()
          .reversed
          .toList(); // Most recent first

      // Send to AI service with rate limiting
      final aiResult = await _aiService.processChatMessage(
        message: text,
        userId: _currentUserId!,
        profileId: _currentProfileId,
        conversationHistory: conversationHistory.isEmpty
            ? null
            : conversationHistory,
      );

      // Update rate limiting status
      _lastRequestRateLimited = aiResult.isRateLimited;

      // Refresh usage stats
      if (_currentUserId != null) {
        await _loadUsageStats();
      }

      String aiResponseText;

      if (aiResult.success) {
        aiResponseText = aiResult.response!;

        // If health data was parsed, add a note about it
        if (aiResult.healthEntry != null) {
          aiResponseText +=
              '\n\n📊 I\'ve recorded this health information for you.';
        }

        if (kDebugMode) {
          debugPrint(
            '[ChatProviderV3] AI response tokens used: ${aiResult.tokensUsed}',
          );
        }
      } else if (aiResult.isRateLimited) {
        aiResponseText =
            aiResult.errorMessage ??
            'You have reached your monthly AI request limit. Your usage will reset next month.';
      } else if (aiResult.isConfigurationError) {
        aiResponseText =
            'AI services are currently unavailable. Please try again later or contact support.';
      } else {
        aiResponseText =
            aiResult.errorMessage ??
            'I apologize, but I encountered an issue processing your message. Please try again.';
      }

      final aiMessage = Message.assistant(
        aiResponseText,
        id: '${messageId}_ai',
      );
      _messages.add(aiMessage);

      // Store AI response in repository
      await _messageBridge.createMessageForUser(
        aiMessage,
        _currentUserId!,
        personId: _currentProfileId,
      );

      _loading.remove(messageId);
      notifyListeners();
    } catch (e) {
      final errorMessage = Message.assistant(
        'I apologize, but I encountered an unexpected error. Please try again.',
        id: '${messageId}_error',
      );

      _messages.add(errorMessage);

      try {
        await _messageBridge.createMessageForUser(
          errorMessage,
          _currentUserId!,
          personId: _currentProfileId,
        );
      } catch (storeError) {
        if (kDebugMode) {
          debugPrint(
            '[ChatProviderV3] Failed to store error message: $storeError',
          );
        }
      }

      _loading.remove(messageId);
      notifyListeners();
    }
  }

  /// Load usage statistics for current user
  Future<void> _loadUsageStats() async {
    if (_currentUserId == null) return;

    try {
      _usageStats = await _aiService.getUsageStats(_currentUserId!);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProviderV3] Failed to load usage stats: $e');
      }
    }
  }

  /// Check if user can make AI requests
  Future<bool> canMakeAIRequest() async {
    if (_currentUserId == null) return false;
    return await _aiService.canMakeRequest(_currentUserId!);
  }

  /// Get remaining AI requests for current user
  Future<int> getRemainingRequests() async {
    if (_currentUserId == null) return 0;
    return await _aiService.getRemainingRequests(_currentUserId!);
  }

  /// Generate health insights for current user
  Future<void> generateHealthInsights({int daysBack = 30}) async {
    if (_currentUserId == null) return;

    final insightsId = 'insights_${DateTime.now().microsecondsSinceEpoch}';
    _loading.add(insightsId);
    notifyListeners();

    try {
      final aiResult = await _aiService.generateHealthInsights(
        userId: _currentUserId!,
        profileId: _currentProfileId,
        daysBack: daysBack,
      );

      String insightsText;

      if (aiResult.success) {
        insightsText =
            '📊 **Health Insights (Last $daysBack days)**\n\n${aiResult.response!}';
      } else if (aiResult.isRateLimited) {
        insightsText =
            aiResult.errorMessage ??
            'Cannot generate insights - monthly AI limit reached.';
      } else {
        insightsText =
            aiResult.errorMessage ??
            'Unable to generate health insights at this time.';
      }

      final insightsMessage = Message.assistant(insightsText, id: insightsId);
      _messages.add(insightsMessage);

      // Store insights message
      await _messageBridge.createMessageForUser(
        insightsMessage,
        _currentUserId!,
        personId: _currentProfileId,
      );

      // Refresh usage stats
      await _loadUsageStats();

      _loading.remove(insightsId);
      notifyListeners();
    } catch (e) {
      final errorMessage = Message.assistant(
        'Failed to generate health insights. Please try again later.',
        id: '${insightsId}_error',
      );

      _messages.add(errorMessage);
      _loading.remove(insightsId);
      notifyListeners();
    }
  }

  Future<void> _loadMessages() async {
    if (_currentUserId == null || _loadingMessages) return;

    _loadingMessages = true;
    notifyListeners();

    try {
      final loadedMessages = _currentProfileId != null
          ? await _messageBridge.getMessagesForUser(
              _currentUserId!,
              personId: _currentProfileId!,
              limit: 100,
            )
          : await _messageBridge.getAllMessagesForUser(
              _currentUserId!,
              limit: 100,
            );

      _messages = loadedMessages;
      _loadingMessages = false;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProviderV3] Failed to load messages: $e');
      }
      _loadingMessages = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages([String? profileId]) async {
    final targetProfileId = profileId ?? _currentProfileId;
    if (targetProfileId != null) {
      setCurrentProfile(targetProfileId);
    } else {
      await _loadMessages();
    }
  }

  /// Clear all messages for current profile
  Future<void> clearMessages() async {
    if (_currentUserId == null) return;

    try {
      if (_currentProfileId != null) {
        await _messageBridge.deleteMessagesByPerson(
          _currentProfileId!,
          _currentUserId!,
        );
      }

      _messages.clear();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProviderV3] Failed to clear messages: $e');
      }
    }
  }

  /// Get latest message for current user/profile
  Future<Message?> getLatestMessage() async {
    if (_currentUserId == null) return null;

    try {
      return await _messageBridge.getLatestMessage(
        _currentUserId!,
        personId: _currentProfileId,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatProviderV3] Failed to get latest message: $e');
      }
      return null;
    }
  }

  /// Check if AI service is properly configured
  bool get isAIConfigured => _aiService.isConfigured;

  /// Get available AI providers
  List<AIProvider> get availableAIProviders => _aiService.availableProviders;

  @override
  void dispose() {
    _messages.clear();
    _loading.clear();
    super.dispose();
  }
}

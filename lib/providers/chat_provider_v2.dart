import 'package:flutter/foundation.dart';
import 'dart:async';
import '../repositories/repository_manager.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/message_repository_bridge.dart';
import 'settings_provider.dart';

/// ChatProvider using repository pattern for local-first operations
/// This replaces the backend-dependent ChatProvider with local SQLite storage
class ChatProviderV2 extends ChangeNotifier {
  final MessageRepositoryBridge _messageBridge;
  final AuthService? authService;
  SettingsProvider? settings;

  List<Message> _messages = [];
  final Set<String> _loading = {};
  String? _currentProfileId;
  String? _currentUserId;
  bool _loadingMessages = false;

  List<Message> get messages => List.unmodifiable(_messages);
  String? get currentProfileId => _currentProfileId;
  String? get currentUserId => _currentUserId;
  bool get loadingMessages => _loadingMessages;

  ChatProviderV2({required RepositoryManager repoManager, this.authService})
    : _messageBridge = MessageRepositoryBridge(repoManager);

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
      // For now, create a simple AI response since we're focusing on local storage
      // Later tasks will implement the full AI service
      final aiResponse = await _generateSimpleAIResponse(text);

      final aiMessage = Message.assistant(aiResponse, id: '${messageId}_ai');
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
        'Sorry, I had trouble processing that message. Please try again.',
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
          debugPrint('Failed to store error message: $storeError');
        }
      }

      _loading.remove(messageId);
      notifyListeners();
    }
  }

  /// Simple AI response generator for now
  /// This will be replaced with proper AI service integration in later tasks
  Future<String> _generateSimpleAIResponse(String userMessage) async {
    // Simple keyword-based responses for demonstration
    final lowercaseMessage = userMessage.toLowerCase();

    if (lowercaseMessage.contains('glucose') ||
        lowercaseMessage.contains('blood sugar')) {
      return 'I can help you track your glucose levels. What was your reading?';
    } else if (lowercaseMessage.contains('blood pressure')) {
      return 'I can record your blood pressure reading. Please share your systolic/diastolic values.';
    } else if (lowercaseMessage.contains('weight')) {
      return 'I can log your weight. What is your current weight?';
    } else if (lowercaseMessage.contains('medication') ||
        lowercaseMessage.contains('med')) {
      return 'I can help you track your medications. Which medication would you like to record or ask about?';
    } else {
      return 'I understand. I\'m here to help you track your health data. Feel free to share any health information you\'d like to record.';
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
        debugPrint('Failed to load messages: $e');
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
        debugPrint('Failed to clear messages: $e');
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
        debugPrint('Failed to get latest message: $e');
      }
      return null;
    }
  }

  @override
  void dispose() {
    _messages.clear();
    _loading.clear();
    super.dispose();
  }
}

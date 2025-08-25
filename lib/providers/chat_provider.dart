import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../services/database_service.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import 'settings_provider.dart';
import '../models/chat_message.dart';
import '../models/health_entry.dart';
import '../config/app_config.dart';

class ChatProvider extends ChangeNotifier {
  final DatabaseService db;
  final AuthService? authService;
  SettingsProvider? settings;
  final AiService _ai = AiService();
  final List<ChatMessage> _messages = [];
  final Set<String> _loading = {};
  String? _currentConversationId;

  List<ChatMessage> get messages => _currentConversationId == null 
    ? List.unmodifiable(_messages)
    : List.unmodifiable(_messages.where((m) => m.conversationId == _currentConversationId).toList());

  String? get currentConversationId => _currentConversationId;

  ChatProvider({required this.db, this.authService});

  void attachSettings(SettingsProvider s) {
    settings = s;
  }

  bool isLoading(String id) => _loading.contains(id);

  void setCurrentConversation(String conversationId) {
    _currentConversationId = conversationId;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentConversationId == null) {
      if (kDebugMode) {
        debugPrint('Error: No conversation selected');
      }
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();

    if (kDebugMode) {
      debugPrint('Processing user message: $text');
    }

    try {
      _messages.add(ChatMessage(
          id: id, 
          text: text, 
          isUser: true, 
          conversationId: _currentConversationId!,
          timestamp: DateTime.now()));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to add message to chat: $e');
      }
      return;
    }

    // Process message asynchronously to avoid blocking UI
    unawaited(_processMessageWithAI(text, id));
  }

  Future<void> _processMessageWithAI(String text, String messageId) async {
    _loading.add(messageId);
    notifyListeners();

    try {
      final token = await authService?.getIdToken();
      final aiResult = await _ai.interpretAndStore(text, bearerToken: token, conversationId: _currentConversationId);

      if (aiResult != null && aiResult.entry != null) {
        if (kDebugMode) {
          debugPrint('Health data processed successfully: ${aiResult.entry?.type}');
        }

        try {
          _messages.add(ChatMessage(
              id: '${messageId}_ai',
              text: aiResult.reply ?? 'Health data recorded successfully',
              isUser: false,
              conversationId: _currentConversationId!,
              timestamp: DateTime.now(),
              parsedEntry: aiResult.entry,
              aiRefined: true,
              backendPersisted: aiResult.persisted,
              parseSource: 'ai'));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Failed to add AI response to chat: $e');
          }
        }

        if (aiResult.entry!.type == HealthEntryType.vital) {
          final vitalType = aiResult.entry!.vital?.vitalType.toString().split('.').last;
          final category = 'vital';

          _messages.add(ChatMessage(
            id: '${messageId}_trend_prompt',
            text: 'Would you like to see your ${vitalType?.toLowerCase()} trend?',
            isUser: false,
            conversationId: _currentConversationId!,
            timestamp: DateTime.now(),
            showTrendButtons: true,
            trendType: vitalType,
            trendCategory: category,
          ));
        }
      } else {
        _messages.add(ChatMessage(
          id: '${messageId}_ai',
          text: aiResult?.reply ?? 'I understand. Let me know if you have any health data to record.',
          isUser: false,
          conversationId: _currentConversationId!,
          timestamp: DateTime.now(),
        ));
      }

      _loading.remove(messageId);
      notifyListeners();

    } catch (e) {
      _messages.add(ChatMessage(
        id: '${messageId}_ai',
        text: 'Sorry, I had trouble processing that message. Please try again.',
        isUser: false,
        conversationId: _currentConversationId!,
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));

      _loading.remove(messageId);
      notifyListeners();
    }
  }

  Future<void> loadMessages([String? conversationId]) async {
    // If no conversation ID provided, use the current one
    final targetConversationId = conversationId ?? _currentConversationId;
    if (targetConversationId == null) {
      if (kDebugMode) {
        debugPrint('No conversation ID provided for loading messages');
      }
      return;
    }
    
    try {
      // Get authentication headers
      final token = await authService?.getIdToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };

      final response = await http.get(
          Uri.parse(
              '${AppConfig.backendBaseUrl}/api/messages?conversation_id=$targetConversationId&limit=100'),
          headers: headers);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = json['items'] as List;

        // Clear existing messages for this conversation
        _messages.removeWhere((msg) => msg.conversationId == targetConversationId);

        // Batch process all messages before notifying listeners
        final newMessages = <ChatMessage>[];
        
        for (final item in items.reversed) {
          final role = item['role'] as String?;
          final content = item['content'] as String?;
          final messageId = item['id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          final processed = item['processed'] as int? ?? 0;
          final interpretationJson = item['interpretation_json'] as String?;
          // Get conversation_id from backend data, fallback to targetConversationId
          final msgConversationId = item['conversation_id'] as String? ?? targetConversationId;

          if (content != null && content.isNotEmpty) {
            if (role == 'user') {
              final createdAt = item['created_at'] as int?;
              final timestamp = createdAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                  : DateTime.now();

              newMessages.add(ChatMessage(
                id: messageId,
                text: content,
                isUser: true,
                conversationId: msgConversationId,
                timestamp: timestamp,
              ));

              if (processed == 1 && interpretationJson != null) {
                try {
                  final interpretation =
                      jsonDecode(interpretationJson) as Map<String, dynamic>;
                  final reply = interpretation['reply'] as String?;
                  final parsed = interpretation['parsed'] as bool? ?? false;

                  if (reply != null && reply.isNotEmpty) {
                    newMessages.add(ChatMessage(
                      id: '${messageId}_ai',
                      text: reply,
                      isUser: false,
                      conversationId: msgConversationId,
                      timestamp: timestamp.add(const Duration(seconds: 1)),
                      aiRefined: parsed,
                      parseSource: parsed ? 'ai' : null,
                    ));
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('Error parsing interpretation JSON: $e');
                  }
                }
              }
            }
          }
        }

        // Add all messages at once and notify listeners only once
        _messages.addAll(newMessages);
        
        if (kDebugMode) {
          debugPrint('Successfully loaded ${_messages.where((m) => m.conversationId == targetConversationId).length} messages from backend for conversation: $targetConversationId');
        }
        notifyListeners();
      } else {
        if (kDebugMode) {
          debugPrint('Failed to load messages from backend: ${response.statusCode}');
        }
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load messages: $e');
      }
      notifyListeners();
    }
  }

  Future<void> debugMessageCounts() async {
    if (kDebugMode) {
      final localCount = _messages.length;
      debugPrint('Local messages: $localCount (backend messages in Data screen)');
    }
  }

  Future<void> clearAllMessages() async {
    try {
      if (_currentConversationId != null) {
        // Clear messages for current conversation only
        _messages.removeWhere((msg) => msg.conversationId == _currentConversationId);
        if (kDebugMode) {
          debugPrint('Successfully cleared messages for conversation: $_currentConversationId');
        }
      } else {
        // Clear all messages if no specific conversation
        _messages.clear();
        if (kDebugMode) {
          debugPrint('Successfully cleared all local messages');
        }
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to clear messages: $e');
      }
    }
  }

  Future<void> handleTrendResponse(
      String messageId, bool showTrend, String type, String category) async {
    if (_currentConversationId == null) return;
    
    if (!showTrend) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_no',
        text: 'Understood. Let me know if you need anything else!',
        isUser: false,
        conversationId: _currentConversationId!,
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    _loading.add('${messageId}_trend');
    notifyListeners();

    try {
      final resp = await http.post(
          Uri.parse('${AppConfig.backendBaseUrl}/api/ai/analyze-trend'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'type': type,
            'category': category,
          }));

      if (resp.statusCode == 200) {
        _messages.add(ChatMessage(
          id: '${messageId}_trend_analysis',
          text: resp.body,
          isUser: false,
          conversationId: _currentConversationId!,
          timestamp: DateTime.now(),
        ));
      } else {
        _messages.add(ChatMessage(
          id: '${messageId}_trend_error',
          text: 'Sorry, I had trouble generating the trend analysis.',
          isUser: false,
          conversationId: _currentConversationId!,
          timestamp: DateTime.now(),
          parseFailed: true,
        ));
      }
    } catch (e) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_error',
        text: 'Sorry, there was an error analyzing the trend.',
        isUser: false,
        conversationId: _currentConversationId!,
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));
    }

    _loading.remove('${messageId}_trend');
    notifyListeners();
  }
}

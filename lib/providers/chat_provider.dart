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
  String? _currentProfileId;
  bool _loadingMessages = false; // track initial/history load

  List<ChatMessage> get messages => _currentProfileId == null 
    ? List.unmodifiable(_messages)
    : List.unmodifiable(_messages.where((m) => m.profileId == _currentProfileId).toList());

  String? get currentProfileId => _currentProfileId;
  bool get loadingMessages => _loadingMessages;

  ChatProvider({required this.db, this.authService});

  void attachSettings(SettingsProvider s) {
    settings = s;
  }

  bool isLoading(String id) => _loading.contains(id);

  void setCurrentProfile(String profileId) {
    _currentProfileId = profileId;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentProfileId == null) {
      if (kDebugMode) {
        debugPrint('Error: No profile selected');
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
          profileId: _currentProfileId!,
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
  final aiResult = await _ai.interpretAndStore(text, bearerToken: token, profileId: _currentProfileId);

      if (aiResult != null && aiResult.entry != null) {
        if (kDebugMode) {
          debugPrint('Health data processed successfully: ${aiResult.entry?.type}');
        }

        try {
          _messages.add(ChatMessage(
              id: '${messageId}_ai',
              text: aiResult.reply ?? 'Health data recorded successfully',
              isUser: false,
              profileId: _currentProfileId!,
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
            profileId: _currentProfileId!,
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
          profileId: _currentProfileId!,
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
  profileId: _currentProfileId!,
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));

      _loading.remove(messageId);
      notifyListeners();
    }
  }

  Future<void> loadMessages([String? profileId]) async {
  final targetProfileId = profileId ?? _currentProfileId;
    if (targetProfileId == null) {
      if (kDebugMode) debugPrint('No profile ID provided for loading messages');
      return;
    }
  if (_loadingMessages) return; // prevent duplicate concurrent loads
  _loadingMessages = true;
  notifyListeners();
    
    try {
      // Get authentication headers
      final token = await authService?.getIdToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };

      final response = await http.get(
          Uri.parse(
              '${AppConfig.backendBaseUrl}/api/messages?profile_id=$targetProfileId&limit=100'),
          headers: headers);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = json['items'] as List;

  // Clear existing messages for this profile
  _messages.removeWhere((msg) => msg.profileId == targetProfileId);

        // Batch process all messages before notifying listeners
        final newMessages = <ChatMessage>[];
        
        for (final item in items.reversed) {
          final role = item['role'] as String?;
          final content = item['content'] as String?;
          final messageId = item['id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          final processed = item['processed'] as int? ?? 0;
          final interpretationJson = item['interpretation_json'] as String?;
          // Get profile_id from backend data (fallback legacy key)
          final msgConversationId = item['profile_id'] as String? ?? targetProfileId;

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
                profileId: msgConversationId,
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
                      profileId: msgConversationId,
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
          debugPrint('Successfully loaded ${_messages.where((m) => m.profileId == targetProfileId).length} messages from backend for profile: $targetProfileId');
        }
        notifyListeners();
      } else {
        if (kDebugMode) {
          debugPrint('Failed to load messages from backend: ${response.statusCode}');
        }
        _loadingMessages = false;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load messages: $e');
      }
      _loadingMessages = false;
      notifyListeners();
      return;
    }
    _loadingMessages = false;
    notifyListeners();
  }

  Future<void> debugMessageCounts() async {
    if (kDebugMode) {
      final localCount = _messages.length;
      debugPrint('Local messages: $localCount (backend messages in Data screen)');
    }
  }

  Future<void> clearAllMessages() async {
    try {
  if (_currentProfileId != null) {
    // Clear messages for current profile only
  _messages.removeWhere((msg) => msg.profileId == _currentProfileId);
        if (kDebugMode) {
          debugPrint('Successfully cleared messages for profile: $_currentProfileId');
        }
      } else {
  // Clear all messages if no specific profile
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
  if (_currentProfileId == null) return;
    
    if (!showTrend) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_no',
        text: 'Understood. Let me know if you need anything else!',
        isUser: false,
  profileId: _currentProfileId!,
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
          profileId: _currentProfileId!,
          timestamp: DateTime.now(),
        ));
      } else {
        _messages.add(ChatMessage(
          id: '${messageId}_trend_error',
          text: 'Sorry, I had trouble generating the trend analysis.',
          isUser: false,
          profileId: _currentProfileId!,
          timestamp: DateTime.now(),
          parseFailed: true,
        ));
      }
    } catch (e) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_error',
        text: 'Sorry, there was an error analyzing the trend.',
        isUser: false,
  profileId: _currentProfileId!,
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));
    }

    _loading.remove('${messageId}_trend');
    notifyListeners();
  }
}

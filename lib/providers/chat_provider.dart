import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/database_service.dart';
import '../services/ai_service.dart';
import 'settings_provider.dart';
import '../models/chat_message.dart';
import '../models/health_entry.dart';
import '../config/app_config.dart';

class ChatProvider extends ChangeNotifier {
  final DatabaseService db;
  SettingsProvider? settings;
  final AiService _ai = AiService();
  final List<ChatMessage> _messages = [];
  final Set<String> _loading = {};

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  ChatProvider({required this.db});

  void attachSettings(SettingsProvider s) {
    settings = s;
  }

  bool isLoading(String id) => _loading.contains(id);

  Future<void> sendMessage(String text) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    debugPrint('Processing user message: $text');

    try {
      _messages.add(ChatMessage(
          id: id, text: text, isUser: true, timestamp: DateTime.now()));
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to add message to chat: $e');
      return;
    }

    _processMessageWithAI(text, id);
  }

  Future<void> _processMessageWithAI(String text, String messageId) async {
    _loading.add(messageId);
    notifyListeners();

    try {
      final aiResult = await _ai.interpretAndStore(text);

      if (aiResult != null && aiResult.entry != null) {
        debugPrint('Health data processed successfully: ${aiResult.entry?.type}');

        try {
          _messages.add(ChatMessage(
              id: '${messageId}_ai',
              text: aiResult.reply ?? 'Health data recorded successfully',
              isUser: false,
              timestamp: DateTime.now(),
              parsedEntry: aiResult.entry,
              aiRefined: true,
              backendPersisted: aiResult.persisted,
              parseSource: 'ai'));
        } catch (e) {
          debugPrint('Failed to add AI response to chat: $e');
        }

        if (aiResult.entry!.type == HealthEntryType.vital) {
          final vitalType = aiResult.entry!.vital?.vitalType.toString().split('.').last;
          final category = 'vital';

          _messages.add(ChatMessage(
            id: '${messageId}_trend_prompt',
            text: 'Would you like to see your ${vitalType?.toLowerCase()} trend?',
            isUser: false,
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
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));

      _loading.remove(messageId);
      notifyListeners();
    }
  }

  Future<void> loadMessages() async {
    try {
      final response = await http.get(
          Uri.parse(
              '${AppConfig.backendBaseUrl}/api/admin/table/messages?page=1&limit=100'),
          headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = json['items'] as List;

        for (final item in items.reversed) {
          final role = item['role'] as String?;
          final content = item['content'] as String?;
          final messageId = item['id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          final processed = item['processed'] as int? ?? 0;
          final interpretationJson = item['interpretation_json'] as String?;

          if (content != null && content.isNotEmpty) {
            if (role == 'user') {
              final createdAt = item['created_at'] as int?;
              final timestamp = createdAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                  : DateTime.now();

              _messages.add(ChatMessage(
                id: messageId,
                text: content,
                isUser: true,
                timestamp: timestamp,
              ));

              if (processed == 1 && interpretationJson != null) {
                try {
                  final interpretation =
                      jsonDecode(interpretationJson) as Map<String, dynamic>;
                  final reply = interpretation['reply'] as String?;
                  final parsed = interpretation['parsed'] as bool? ?? false;

                  if (reply != null && reply.isNotEmpty) {
                    _messages.add(ChatMessage(
                      id: '${messageId}_ai',
                      text: reply,
                      isUser: false,
                      timestamp: timestamp.add(const Duration(seconds: 1)),
                      aiRefined: parsed,
                      parseSource: parsed ? 'ai' : null,
                    ));
                  }
                } catch (e) {
                  debugPrint('Error parsing interpretation JSON: $e');
                }
              }
            }
          }
        }

        debugPrint('Successfully loaded ${_messages.length} messages from backend');
        notifyListeners();
      } else {
        debugPrint('Failed to load messages from backend: ${response.statusCode}');
        _messages.clear();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load messages: $e');
      _messages.clear();
      notifyListeners();
    }
  }

  Future<void> debugMessageCounts() async {
    final localCount = _messages.length;
    debugPrint('Local messages: $localCount (backend messages in Data screen)');
  }

  Future<void> clearAllMessages() async {
    try {
      _messages.clear();
      notifyListeners();
      debugPrint('Successfully cleared local messages');
    } catch (e) {
      debugPrint('Failed to clear messages: $e');
    }
  }

  Future<void> handleTrendResponse(
      String messageId, bool showTrend, String type, String category) async {
    if (!showTrend) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_no',
        text: 'Understood. Let me know if you need anything else!',
        isUser: false,
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
          timestamp: DateTime.now(),
        ));
      } else {
        _messages.add(ChatMessage(
          id: '${messageId}_trend_error',
          text: 'Sorry, I had trouble generating the trend analysis.',
          isUser: false,
          timestamp: DateTime.now(),
          parseFailed: true,
        ));
      }
    } catch (e) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_error',
        text: 'Sorry, there was an error analyzing the trend.',
        isUser: false,
        timestamp: DateTime.now(),
        parseFailed: true,
        aiErrorReason: e.toString(),
      ));
    }

    _loading.remove('${messageId}_trend');
    notifyListeners();
  }
}

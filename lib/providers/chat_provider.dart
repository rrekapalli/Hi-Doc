import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/database_service.dart';
import 'settings_provider.dart';
import '../services/ai_service.dart';
import '../models/health_entry.dart';
import '../models/health_data_entry.dart';

import '../config/app_config.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final HealthEntry? parsedEntry;
  final HealthDataEntry? healthDataEntry; // New health data entry
  final bool parseFailed;
  final bool aiRefined;
  final bool backendPersisted;
  final String? aiErrorReason;
  final String? parseSource; // 'local','heuristic','ai'
  final bool showTrendButtons; // Show Yes/No buttons for trend analysis
  final String? trendType; // Type for trend analysis
  final String? trendCategory; // Category for trend analysis
  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.parsedEntry,
    this.healthDataEntry,
    this.parseFailed = false,
    this.aiRefined = false,
    this.backendPersisted = false,
    this.aiErrorReason,
    this.parseSource,
    this.showTrendButtons = false,
    this.trendType,
    this.trendCategory,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatProvider extends ChangeNotifier {
  final DatabaseService db;
  SettingsProvider? settings; // optional injection later
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

    print('Sending message: $text (ID: $id)');

    // 1. Add to local chat display immediately
    _messages.add(ChatMessage(
        id: id, text: text, isUser: true, timestamp: DateTime.now()));
    notifyListeners();

    // 2. Store message and process with AI via backend (this handles both storage and AI processing)
    _processMessageWithAI(text, id);
  }

  Future<void> _processMessageWithAI(String text, String messageId) async {
    _loading.add(messageId);
    notifyListeners();

    try {
      print('Processing message with new health workflow: $text');

      // Use existing interpret-store endpoint which handles message storage properly
      final aiResult = await _ai.interpretAndStore(text);

      if (aiResult != null && aiResult.entry != null) {
        print('Health data processing successful');

        // Add AI response with health data recorded
        _messages.add(ChatMessage(
            id: '${messageId}_ai',
            text: aiResult.reply ?? 'Health data recorded successfully',
            isUser: false,
            timestamp: DateTime.now(),
            parsedEntry: aiResult.entry,
            aiRefined: true,
            backendPersisted: aiResult.persisted,
            parseSource: 'ai'));

        // Add trend analysis question with Yes/No buttons for health-related entries
        if (aiResult.entry!.type == HealthEntryType.vital) {
          final vitalType = aiResult.entry!.vital?.vitalType.toString().toUpperCase() ?? 'UNKNOWN';

          final trendQuestion = await _ai.askForTrendAnalysis(vitalType, 'HEALTH_PARAMS');

          _messages.add(ChatMessage(
            id: '${messageId}_trend_question',
            text: trendQuestion,
            isUser: false,
            timestamp: DateTime.now().add(const Duration(milliseconds: 500)),
            showTrendButtons: true,
            trendType: vitalType,
            trendCategory: 'HEALTH_PARAMS',
          ));
        }

        print('Health entry processed and trend question added');
      } else {
        print('Health data processing failed or no entry extracted');

        _messages.add(ChatMessage(
            id: '${messageId}_stored',
            text: aiResult?.reply ?? 'Message stored',
            isUser: false,
            timestamp: DateTime.now(),
            parseFailed: aiResult?.reasoning != null,
            aiErrorReason: aiResult?.reasoning));
      }
    } catch (e) {
      print('Error processing message with AI: $e');

      _messages.add(ChatMessage(
          id: '${messageId}_error',
          text: 'Message stored (AI unavailable)',
          isUser: false,
          timestamp: DateTime.now(),
          parseFailed: true,
          aiErrorReason: e.toString()));
    } finally {
      _loading.remove(messageId);
      notifyListeners();
    }
  }

  // Load messages from backend on startup
  Future<void> loadMessages() async {
    try {
      print('Loading messages from backend...');

      // Fetch messages from backend API
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.backendBaseUrl}/api/admin/table/messages?page=1&limit=100'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (json['items'] as List).cast<Map<String, dynamic>>();

        _messages.clear();

        // Convert backend messages to ChatMessage format
        for (final item in items.reversed) {
          // Reverse to show oldest first in chat
          final role = item['role'] as String?;
          final content = item['content'] as String?;
          final messageId = item['id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          final processed = item['processed'] as int? ?? 0;
          final interpretationJson = item['interpretation_json'] as String?;

          if (content != null && content.isNotEmpty) {
            // Add user message
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

              // If message was processed by AI, add AI response
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
                      timestamp: timestamp.add(const Duration(
                          seconds:
                              1)), // AI response slightly after user message
                      aiRefined: parsed,
                      parseSource: parsed ? 'ai' : null,
                    ));
                  }
                } catch (e) {
                  print('Error parsing interpretation JSON: $e');
                }
              }
            }
          }
        }

        print('Loaded ${_messages.length} messages from backend');
        notifyListeners();
      } else {
        print('Failed to load messages: ${response.statusCode}');
        _messages.clear();
        notifyListeners();
      }
    } catch (e) {
      print('ERROR loading messages: $e');
      _messages.clear();
      notifyListeners();
    }
  }

  // Debug method to show message counts
  Future<void> debugMessageCounts() async {
    final localCount = _messages.length;
    print(
        'Local chat messages: $localCount (backend messages viewable in Data screen)');
  }

  // Clear all messages (for testing)
  Future<void> clearAllMessages() async {
    _messages.clear();
    notifyListeners();
    print('Local chat messages cleared (backend messages remain in database)');
  }

  /// Handle trend analysis response (Yes/No)
  Future<void> handleTrendResponse(
      String messageId, bool showTrend, String type, String category) async {
    if (!showTrend) {
      // User said No - just add a simple response
      _messages.add(ChatMessage(
        id: '${messageId}_trend_no',
        text: 'Understood. Let me know if you need anything else!',
        isUser: false,
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    // User said Yes - generate trend analysis
    _loading.add('${messageId}_trend');
    notifyListeners();

    try {
      final trendData =
          await _ai.generateTrendAnalysis(type, category, 'current_user_id');

      if (trendData != null) {
        final prognosis =
            trendData['prognosis'] as String? ?? 'Trend analysis completed.';

        _messages.add(ChatMessage(
          id: '${messageId}_trend_yes',
          text: prognosis,
          isUser: false,
          timestamp: DateTime.now(),
          aiRefined: true,
        ));
      } else {
        _messages.add(ChatMessage(
          id: '${messageId}_trend_error',
          text: 'Sorry, I couldn\'t generate the trend analysis at this time.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      _messages.add(ChatMessage(
        id: '${messageId}_trend_error',
        text: 'Error generating trend analysis: ${e.toString()}',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    } finally {
      _loading.remove('${messageId}_trend');
      notifyListeners();
    }
  }
}

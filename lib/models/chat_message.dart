import 'package:flutter/foundation.dart';
import 'health_entry.dart';
import 'health_data_entry.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final HealthEntry? parsedEntry;
  final HealthDataEntry? healthDataEntry;
  final bool parseFailed;
  final bool aiRefined;
  final bool backendPersisted;
  final String? aiErrorReason;
  final String? parseSource;
  final bool showTrendButtons;
  final String? trendType;
  final String? trendCategory;

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

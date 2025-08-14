import 'package:flutter/services.dart';

class PromptService {
  static const String _healthDataEntryPromptPath = 'assets/prompts/health_data_entry_prompt.txt';
  static const String _healthDataTrendPromptPath = 'assets/prompts/health_data_trend_prompt.txt';
  
  static String? _healthDataEntryPrompt;
  static String? _healthDataTrendPrompt;
  
  /// Load the health data entry prompt from assets
  static Future<String> getHealthDataEntryPrompt() async {
    _healthDataEntryPrompt ??= await rootBundle.loadString(_healthDataEntryPromptPath);
    return _healthDataEntryPrompt!;
  }
  
  /// Load the health data trend prompt from assets
  static Future<String> getHealthDataTrendPrompt() async {
    _healthDataTrendPrompt ??= await rootBundle.loadString(_healthDataTrendPromptPath);
    return _healthDataTrendPrompt!;
  }
  
  /// Clear cached prompts (useful for testing)
  static void clearCache() {
    _healthDataEntryPrompt = null;
    _healthDataTrendPrompt = null;
  }
}
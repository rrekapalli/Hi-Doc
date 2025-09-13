import 'package:flutter/foundation.dart';
import 'ai_rate_limiter.dart';
import 'ai_service_client.dart';
import '../repositories/repository_manager.dart';
import '../models/health_entry.dart';

/// Enhanced AI service that combines rate limiting with external AI providers
/// Handles health data interpretation, chat responses, and usage tracking
class EnhancedAIService {
  final AIRateLimiter _rateLimiter;
  final AIServiceClient _client;
  final RepositoryManager _repoManager;

  // Default configuration - can be overridden
  static const AIProvider _defaultProvider = AIProvider.openai;
  static const String _defaultModel = 'gpt-3.5-turbo';

  EnhancedAIService({
    required RepositoryManager repoManager,
    String? openAiApiKey,
    String? anthropicApiKey,
    String? customBackendUrl,
  }) : _repoManager = repoManager,
       _rateLimiter = AIRateLimiter(repoManager),
       _client = AIServiceClient(
         openAiApiKey: openAiApiKey,
         anthropicApiKey: anthropicApiKey,
         customBackendUrl: customBackendUrl,
       );

  /// Process chat message with AI, including rate limiting
  /// Returns AI response and handles health data interpretation
  Future<AIServiceResult> processChatMessage({
    required String message,
    required String userId,
    String? profileId,
    List<ChatMessage>? conversationHistory,
    AIProvider? provider,
    String? model,
  }) async {
    try {
      // Check rate limit first
      final canMakeRequest = await _rateLimiter.canMakeRequest(userId);
      if (!canMakeRequest) {
        return AIServiceResult(
          success: false,
          errorMessage: _rateLimiter.getRateLimitMessage(userId),
          isRateLimited: true,
        );
      }

      final usedProvider = provider ?? _defaultProvider;
      final usedModel = model ?? _defaultModel;

      // Check if provider is configured
      if (!_client.isConfigured(usedProvider)) {
        return AIServiceResult(
          success: false,
          errorMessage: 'AI service is not configured. Please contact support.',
          isConfigurationError: true,
        );
      }

      // Enhance message with health context if needed
      final enhancedMessage = await _enhanceMessageWithContext(
        message,
        userId,
        profileId,
      );

      // Send to AI service
      final response = await _client.sendChatMessage(
        message: enhancedMessage,
        userId: userId,
        conversationHistory: conversationHistory,
        provider: usedProvider,
        model: usedModel,
      );

      if (response.success) {
        // Record usage for rate limiting
        await _rateLimiter.recordUsage(
          userId,
          requestType: 'chat',
          model: usedModel,
          tokensUsed: response.tokensUsed,
          requestId: response.requestId,
        );

        // Try to parse health data from the response
        final healthEntry = await _parseHealthDataFromResponse(
          response.generatedText!,
          userId,
          profileId,
        );

        return AIServiceResult(
          success: true,
          response: response.generatedText!,
          healthEntry: healthEntry,
          tokensUsed: response.tokensUsed,
          provider: usedProvider,
          model: usedModel,
        );
      } else {
        return AIServiceResult(
          success: false,
          errorMessage: response.errorMessage ?? 'Unknown AI service error',
          provider: usedProvider,
          model: usedModel,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EnhancedAIService] Error processing chat message: $e');
      }
      return AIServiceResult(
        success: false,
        errorMessage: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  /// Get AI usage statistics for user
  Future<Map<String, int>> getUsageStats(String userId) async {
    return await _rateLimiter.getUsageStats(userId);
  }

  /// Check if user can make AI requests
  Future<bool> canMakeRequest(String userId) async {
    return await _rateLimiter.canMakeRequest(userId);
  }

  /// Get remaining AI requests for user
  Future<int> getRemainingRequests(String userId) async {
    return await _rateLimiter.getRemainingRequests(userId);
  }

  /// Generate health insights based on recent data
  Future<AIServiceResult> generateHealthInsights({
    required String userId,
    String? profileId,
    int daysBack = 30,
  }) async {
    try {
      // Check rate limit
      final canMakeRequest = await _rateLimiter.canMakeRequest(userId);
      if (!canMakeRequest) {
        return AIServiceResult(
          success: false,
          errorMessage: _rateLimiter.getRateLimitMessage(userId),
          isRateLimited: true,
        );
      }

      // Get recent health data
      final healthEntries = await _getRecentHealthData(
        userId,
        profileId,
        daysBack,
      );

      if (healthEntries.isEmpty) {
        return AIServiceResult(
          success: false,
          errorMessage: 'No recent health data found to analyze.',
        );
      }

      // Build insights prompt
      final prompt = _buildInsightsPrompt(healthEntries);

      // Send to AI service
      final response = await _client.sendChatMessage(
        message: prompt,
        userId: userId,
        provider: _defaultProvider,
        model: _defaultModel,
      );

      if (response.success) {
        // Record usage
        await _rateLimiter.recordUsage(
          userId,
          requestType: 'insights',
          model: _defaultModel,
          tokensUsed: response.tokensUsed,
          requestId: response.requestId,
        );

        return AIServiceResult(
          success: true,
          response: response.generatedText!,
          tokensUsed: response.tokensUsed,
          provider: _defaultProvider,
          model: _defaultModel,
        );
      } else {
        return AIServiceResult(
          success: false,
          errorMessage: response.errorMessage ?? 'Failed to generate insights',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EnhancedAIService] Error generating insights: $e');
      }
      return AIServiceResult(
        success: false,
        errorMessage: 'Failed to generate health insights.',
      );
    }
  }

  /// Enhance user message with relevant health context
  Future<String> _enhanceMessageWithContext(
    String message,
    String userId,
    String? profileId,
  ) async {
    try {
      // For now, return the message as-is
      // In the future, we could add context from recent health entries
      return message;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EnhancedAIService] Error enhancing message: $e');
      }
      return message; // Fallback to original message
    }
  }

  /// Parse health data from AI response
  Future<HealthEntry?> _parseHealthDataFromResponse(
    String response,
    String userId,
    String? profileId,
  ) async {
    try {
      // Simple keyword-based parsing for now
      // In the future, this could use more sophisticated NLP
      final lowercaseResponse = response.toLowerCase();

      if (lowercaseResponse.contains('glucose') ||
          lowercaseResponse.contains('blood sugar')) {
        // Try to extract glucose reading
        final match = RegExp(
          r'(\d+(?:\.\d+)?)\s*(?:mg/dl|mmol/l)?',
        ).firstMatch(lowercaseResponse);
        if (match != null) {
          final value = double.tryParse(match.group(1) ?? '');
          if (value != null && value > 0 && value < 1000) {
            // This would create a glucose health entry
            // For now, return null since HealthEntry creation is complex
          }
        }
      }

      return null; // No health data parsed
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EnhancedAIService] Error parsing health data: $e');
      }
      return null;
    }
  }

  /// Get recent health data for insights
  Future<List<HealthEntry>> _getRecentHealthData(
    String userId,
    String? profileId,
    int daysBack,
  ) async {
    try {
      final fromTs = DateTime.now()
          .subtract(Duration(days: daysBack))
          .millisecondsSinceEpoch;
      final toTs = DateTime.now().millisecondsSinceEpoch;

      return await _repoManager.healthEntryRepository.findByDateRange(
        fromTs,
        toTs,
        userId,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[EnhancedAIService] Error getting recent health data: $e');
      }
      return [];
    }
  }

  /// Build insights prompt from health data
  String _buildInsightsPrompt(List<HealthEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Please analyze the following health data and provide insights:',
    );
    buffer.writeln();

    for (final entry in entries) {
      buffer.writeln('Date: ${entry.timestamp}');
      buffer.writeln('Type: ${entry.type}');
      if (entry.vital != null) {
        buffer.writeln(
          'Vital: ${entry.vital?.vitalType} = ${entry.vital?.value}',
        );
      }
      buffer.writeln();
    }

    buffer.writeln('Please provide:');
    buffer.writeln('1. Overall trends and patterns');
    buffer.writeln('2. Any concerning values or changes');
    buffer.writeln('3. Recommendations for improvement');
    buffer.writeln('4. Questions to discuss with healthcare provider');

    return buffer.toString();
  }

  /// Check if any AI provider is configured
  bool get isConfigured {
    return _client.isConfigured(AIProvider.openai) ||
        _client.isConfigured(AIProvider.anthropic) ||
        _client.isConfigured(AIProvider.customBackend);
  }

  /// Get available AI providers
  List<AIProvider> get availableProviders {
    final providers = <AIProvider>[];

    if (_client.isConfigured(AIProvider.openai)) {
      providers.add(AIProvider.openai);
    }
    if (_client.isConfigured(AIProvider.anthropic)) {
      providers.add(AIProvider.anthropic);
    }
    if (_client.isConfigured(AIProvider.customBackend)) {
      providers.add(AIProvider.customBackend);
    }

    return providers;
  }
}

/// Result wrapper for AI service operations
class AIServiceResult {
  final bool success;
  final String? response;
  final String? errorMessage;
  final HealthEntry? healthEntry;
  final int? tokensUsed;
  final AIProvider? provider;
  final String? model;
  final bool isRateLimited;
  final bool isConfigurationError;
  final DateTime timestamp;

  AIServiceResult({
    required this.success,
    this.response,
    this.errorMessage,
    this.healthEntry,
    this.tokensUsed,
    this.provider,
    this.model,
    this.isRateLimited = false,
    this.isConfigurationError = false,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'AIServiceResult(success: $success, provider: $provider, rateLimited: $isRateLimited)';
  }
}

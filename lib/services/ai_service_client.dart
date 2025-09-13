import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// External AI service client for communicating with AI providers
/// Supports OpenAI and Anthropic (Claude) APIs
/// Handles authentication, request formatting, and error handling
class AIServiceClient {
  final String? _openAiApiKey;
  final String? _anthropicApiKey;
  final String? _customBackendUrl;

  static const Duration _timeout = Duration(seconds: 30);

  AIServiceClient({
    String? openAiApiKey,
    String? anthropicApiKey,
    String? customBackendUrl,
  }) : _openAiApiKey = openAiApiKey,
       _anthropicApiKey = anthropicApiKey,
       _customBackendUrl = customBackendUrl;

  /// Send a chat message to AI service and get response
  /// Returns AIResponse with the generated text and metadata
  Future<AIResponse> sendChatMessage({
    required String message,
    required String userId,
    List<ChatMessage>? conversationHistory,
    AIProvider provider = AIProvider.openai,
    String model = 'gpt-3.5-turbo',
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
          '[AIServiceClient] Sending message to $provider: ${message.substring(0, message.length.clamp(0, 50))}...',
        );
      }

      switch (provider) {
        case AIProvider.openai:
          return await _sendToOpenAI(
            message: message,
            conversationHistory: conversationHistory,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
          );
        case AIProvider.anthropic:
          return await _sendToAnthropic(
            message: message,
            conversationHistory: conversationHistory,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
          );
        case AIProvider.customBackend:
          return await _sendToCustomBackend(
            message: message,
            userId: userId,
            conversationHistory: conversationHistory,
          );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIServiceClient] Error sending message: $e');
      }
      return AIResponse(
        success: false,
        errorMessage: _getErrorMessage(e),
        provider: provider,
        model: model,
      );
    }
  }

  /// Send request to OpenAI API
  Future<AIResponse> _sendToOpenAI({
    required String message,
    List<ChatMessage>? conversationHistory,
    String model = 'gpt-3.5-turbo',
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    if (_openAiApiKey == null) {
      throw AIServiceException('OpenAI API key not configured');
    }

    final messages = <Map<String, dynamic>>[];

    // Add conversation history
    if (conversationHistory != null) {
      for (final msg in conversationHistory) {
        messages.add({'role': msg.role, 'content': msg.content});
      }
    }

    // Add current message
    messages.add({'role': 'user', 'content': message});

    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_openAiApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List;
      final usage = data['usage'] as Map<String, dynamic>?;

      if (choices.isNotEmpty) {
        final choice = choices.first as Map<String, dynamic>;
        final messageData = choice['message'] as Map<String, dynamic>;

        return AIResponse(
          success: true,
          generatedText: messageData['content'] as String,
          provider: AIProvider.openai,
          model: model,
          tokensUsed: usage?['total_tokens'] as int?,
          requestId: data['id'] as String?,
        );
      } else {
        throw AIServiceException('No response choices returned');
      }
    } else {
      final errorData = jsonDecode(response.body) as Map<String, dynamic>;
      final error = errorData['error'] as Map<String, dynamic>?;
      throw AIServiceException(
        error?['message'] as String? ?? 'OpenAI API error',
      );
    }
  }

  /// Send request to Anthropic Claude API
  Future<AIResponse> _sendToAnthropic({
    required String message,
    List<ChatMessage>? conversationHistory,
    String model = 'claude-3-sonnet-20240229',
    double temperature = 0.7,
    int maxTokens = 1000,
  }) async {
    if (_anthropicApiKey == null) {
      throw AIServiceException('Anthropic API key not configured');
    }

    // For Anthropic, we use the new messages format
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': _anthropicApiKey,
            'Content-Type': 'application/json',
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            'temperature': temperature,
            'messages': [
              {'role': 'user', 'content': message},
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List;
      final usage = data['usage'] as Map<String, dynamic>?;

      if (content.isNotEmpty) {
        final textContent = content.first as Map<String, dynamic>;

        return AIResponse(
          success: true,
          generatedText: textContent['text'] as String,
          provider: AIProvider.anthropic,
          model: model,
          tokensUsed: usage?['output_tokens'] as int?,
          requestId: data['id'] as String?,
        );
      } else {
        throw AIServiceException('No content returned from Claude');
      }
    } else {
      final errorData = jsonDecode(response.body) as Map<String, dynamic>;
      final error = errorData['error'] as Map<String, dynamic>?;
      throw AIServiceException(
        error?['message'] as String? ?? 'Anthropic API error',
      );
    }
  }

  /// Send request to custom backend (Java + Spring Boot)
  Future<AIResponse> _sendToCustomBackend({
    required String message,
    required String userId,
    List<ChatMessage>? conversationHistory,
  }) async {
    if (_customBackendUrl == null) {
      throw AIServiceException('Custom backend URL not configured');
    }

    final response = await http
        .post(
          Uri.parse('$_customBackendUrl/api/ai/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message,
            'user_id': userId,
            'conversation_history': conversationHistory
                ?.map((msg) => {'role': msg.role, 'content': msg.content})
                .toList(),
          }),
        )
        .timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return AIResponse(
        success: true,
        generatedText: data['response'] as String,
        provider: AIProvider.customBackend,
        model: data['model'] as String? ?? 'unknown',
        tokensUsed: data['tokens_used'] as int?,
        requestId: data['request_id'] as String?,
      );
    } else {
      throw AIServiceException('Custom backend error: ${response.statusCode}');
    }
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic error) {
    if (error is AIServiceException) {
      return error.message;
    } else if (error is SocketException) {
      return 'Network connection error. Please check your internet connection.';
    } else if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    } else if (error is FormatException) {
      return 'Invalid response from AI service. Please try again.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Check if AI service is available/configured
  bool isConfigured(AIProvider provider) {
    switch (provider) {
      case AIProvider.openai:
        return _openAiApiKey != null && _openAiApiKey.isNotEmpty;
      case AIProvider.anthropic:
        return _anthropicApiKey != null && _anthropicApiKey.isNotEmpty;
      case AIProvider.customBackend:
        return _customBackendUrl != null && _customBackendUrl.isNotEmpty;
    }
  }
}

/// Supported AI providers
enum AIProvider { openai, anthropic, customBackend }

/// AI service response wrapper
class AIResponse {
  final bool success;
  final String? generatedText;
  final String? errorMessage;
  final AIProvider provider;
  final String model;
  final int? tokensUsed;
  final String? requestId;
  final DateTime timestamp;

  AIResponse({
    required this.success,
    this.generatedText,
    this.errorMessage,
    required this.provider,
    required this.model,
    this.tokensUsed,
    this.requestId,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'AIResponse(success: $success, provider: $provider, model: $model, tokens: $tokensUsed)';
  }
}

/// Chat message for conversation history
class ChatMessage {
  final String role; // 'user' or 'assistant' or 'system'
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String,
    content: json['content'] as String,
  );
}

/// Custom exception for AI service errors
class AIServiceException implements Exception {
  final String message;

  const AIServiceException(this.message);

  @override
  String toString() => 'AIServiceException: $message';
}

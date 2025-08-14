// IO implementation for LocalLlamaService using HTTP requests to local Ollama
import 'dart:convert';
import 'dart:io';
import '../models/parsed_parameter.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';

class LocalLlamaService {
  static final LocalLlamaService _instance = LocalLlamaService._internal();
  factory LocalLlamaService() => _instance;
  LocalLlamaService._internal();

  static const Duration _timeout = Duration(seconds: 30);

  final _uuid = const Uuid();

  Future<List<ParsedParameter>?> parseMessage(String message) async {
    try {
      // Get Ollama configuration from app config
      final baseUrl = AppConfig.ollamaBaseUrl;
      final model = AppConfig.ollamaModel;

      final systemPrompt =
          '''You are a health data extraction assistant. Extract health parameters from user messages and return them as JSON array.

For each health parameter found, return an object with:
- category: one of "vitals", "activities", "calories", "reports"
- parameter: the health metric name (e.g., "glucose", "weight", "steps", "blood pressure")
- value: the numeric value or measurement
- unit: the unit of measurement (optional)

Examples:
Input: "glucose 112 mg/dl"
Output: [{"category":"vitals","parameter":"glucose","value":"112","unit":"mg/dL"}]

Input: "walked 5000 steps today"
Output: [{"category":"activities","parameter":"steps","value":"5000","unit":"steps"}]

Input: "weight 70 kg, bp 120/80"
Output: [{"category":"vitals","parameter":"weight","value":"70","unit":"kg"},{"category":"vitals","parameter":"blood pressure","value":"120/80","unit":"mmHg"}]

Return only the JSON array, no other text.''';

      final response = await _callOllama(baseUrl, model, systemPrompt, message);
      if (response == null) return null;

      // Parse the JSON response
      final jsonData = jsonDecode(response);
      if (jsonData is! List) return null;

      final parameters = <ParsedParameter>[];
      for (final item in jsonData) {
        if (item is Map<String, dynamic>) {
          try {
            parameters.add(ParsedParameter(
              id: _uuid.v4(),
              category: item['category'] as String,
              parameter: item['parameter'] as String,
              value: item['value']?.toString() ?? '',
              unit: item['unit'] as String?,
              datetime: DateTime.now().toIso8601String(),
            ));
          } catch (e) {
            // Skip invalid parameter entries
            continue;
          }
        }
      }

      return parameters.isEmpty ? null : parameters;
    } catch (e) {
      // Return null on any error to fall back to other parsing methods
      return null;
    }
  }

  Future<String?> _callOllama(String baseUrl, String model, String systemPrompt,
      String userMessage) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;

      final uri = Uri.parse('$baseUrl/api/chat');
      final request = await client.postUrl(uri);

      request.headers.set('Content-Type', 'application/json');

      final body = jsonEncode({
        'model': model,
        'stream': false,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'options': {
          'temperature': 0,
          'top_p': 0.9,
        },
      });

      request.add(utf8.encode(body));

      final response = await request.close().timeout(_timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final jsonResponse = jsonDecode(responseBody);

      return jsonResponse['message']?['content'] as String?;
    } catch (e) {
      return null;
    }
  }
}

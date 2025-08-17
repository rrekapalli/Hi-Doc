import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/health_entry.dart';
import '../models/health_data_entry.dart';

class AiInterpretResult {
  final String? reply;
  final HealthEntry? entry;
  final HealthDataEntry? healthDataEntry; // New health data entry
  final String? storedId; // ID assigned by backend persistence
  final bool persisted;
  final String? reasoning; // error / explanation
  final List<Map<String,dynamic>>? matches; // param target similarity results
  AiInterpretResult({this.reply, this.entry, this.healthDataEntry, this.storedId, this.persisted = false, this.reasoning, this.matches});
}

class AiService {
  static DateTime? _lastBackendFailure;
  static const _failureBackoff = Duration(seconds: 5);
  static DateTime? _offlineUntil; // extended offline window
  static const _extendedOfflineBackoff = Duration(seconds: 30);

  Future<bool> _probeBackend(String base) async {
    if (_offlineUntil != null && DateTime.now().isBefore(_offlineUntil!)) return false;
    try {
      final resp = await http.get(Uri.parse('$base/healthz')).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) return true;
    } catch (_) {}
    _offlineUntil = DateTime.now().add(_extendedOfflineBackoff);
    return false;
  }

  Future<AiInterpretResult?> interpret(String message, {String? bearerToken}) async {
    final base = AppConfig.backendBaseUrl;
    final interpretUri = Uri.parse('$base/api/ai/interpret');

    // Backoff if backend recently failed
    if (_lastBackendFailure != null && DateTime.now().difference(_lastBackendFailure!) < _failureBackoff) {
      return null;
    }

    // Quick probe if we think it's offline
    if (!await _probeBackend(base)) {
      // ignore: avoid_print
      print('AIService: backend offline (probe failed)');
      return null;
    }

    // Prototype mode: no authentication needed
    final headers = {
      'Content-Type': 'application/json',
    };

    http.Response resp;
    try {
      resp = await http.post(interpretUri, headers: headers, body: jsonEncode({'message': message})).timeout(const Duration(seconds: 8));
    } on TimeoutException catch (_) {
      _lastBackendFailure = DateTime.now();
      // ignore: avoid_print
      print('AIService interpret timeout');
      return null;
    } catch (e) {
      _lastBackendFailure = DateTime.now();
      // ignore: avoid_print
      print('AIService interpret error: $e');
      return null;
    }

    if (resp.statusCode != 200) {
      // ignore: avoid_print
      print('AIService interpret non-200: ${resp.statusCode} ${resp.body}');
      return null;
    }
    try {
      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final parsed = jsonMap['entry'] as Map<String, dynamic>?;
      HealthEntry? entry;
      if (parsed != null) {
        try { entry = HealthEntry.fromJson(parsed); } catch (e) {
          // ignore: avoid_print
          print('AIService entry decode failed: $e');
        }
      }
      return AiInterpretResult(reply: jsonMap['reply'] as String?, entry: entry, reasoning: jsonMap['reasoning'] as String?, matches: (jsonMap['matches'] as List?)?.cast<Map<String,dynamic>>());
    } catch (e) {
      // ignore: avoid_print
      print('AIService parse response error: $e');
      return null;
    }
  }

  Future<AiInterpretResult?> interpretAndStore(String message, {String? bearerToken}) async {
    final base = AppConfig.backendBaseUrl;
    final storeUri = Uri.parse('$base/api/ai/interpret-store');
    
    if (_lastBackendFailure != null && DateTime.now().difference(_lastBackendFailure!) < _failureBackoff) {
      return null;
    }
    if (!await _probeBackend(base)) {
      return null;
    }

    // Prototype mode: no authentication needed
    final headers = {
      'Content-Type': 'application/json',
    };
    
    http.Response resp;
    try {
      resp = await http.post(storeUri, headers: headers, body: jsonEncode({'message': message})).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode != 200 && resp.statusCode != 201) {
        debugPrint('AIService interpret-store failed with status: ${resp.statusCode}');
        _lastBackendFailure = DateTime.now();
        return null;
      }
    } catch (e) {
      debugPrint('AIService interpret-store request failed: $e');
      _lastBackendFailure = DateTime.now();
      return null;
    }
    
    try {
      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final interpretation = jsonMap['interpretation'] as Map<String, dynamic>?;
      final entryMap = interpretation != null ? interpretation['entry'] as Map<String, dynamic>? : null;
      
      HealthEntry? entry;
      if (entryMap != null) {
        try { 
          entry = HealthEntry.fromJson(entryMap); 
        } catch (e) {
          debugPrint('Failed to parse health entry: $e');
        }
      }
      
      final reply = interpretation != null ? interpretation['reply'] as String? : null;
      final storedId = jsonMap['storedId'] as String?;
      final reasoning = interpretation != null ? interpretation['reasoning'] as String? : null;
      return AiInterpretResult(reply: reply, entry: entry, storedId: storedId, persisted: storedId != null, reasoning: reasoning, matches: (jsonMap['matches'] as List?)?.cast<Map<String,dynamic>>());
    } catch (_) {
      return null;
    }
  }

  /// New method: Process health message with prompt-based workflow
  Future<AiInterpretResult?> processHealthMessage(String message, {String? bearerToken}) async {
    final base = AppConfig.backendBaseUrl;
    
    if (_lastBackendFailure != null && DateTime.now().difference(_lastBackendFailure!) < _failureBackoff) {
      return null;
    }
    if (!await _probeBackend(base)) {
      return null;
    }

    try {
      // Step 1: Process message with health data entry prompt (loaded on backend)
      final entryResult = await _processWithPrompt(message, '', base);
      
      if (entryResult?.healthDataEntry != null) {
        // Step 2: Save to SQLite via backend
        final savedEntry = await _saveHealthDataEntry(entryResult!.healthDataEntry!, base);
        
        if (savedEntry != null) {
          return AiInterpretResult(
            reply: 'Health data recorded successfully',
            healthDataEntry: savedEntry,
            persisted: true,
            storedId: savedEntry.id,
          );
        }
      }
      
      return entryResult;
    } catch (e) {
      _lastBackendFailure = DateTime.now();
      return AiInterpretResult(
        reply: 'Error processing health message',
        reasoning: e.toString(),
      );
    }
  }

  /// Process message with health data entry prompt (loaded from backend)
  Future<AiInterpretResult?> _processWithPrompt(String message, String prompt, String baseUrl) async {
    final processUri = Uri.parse('$baseUrl/api/ai/process-with-prompt');
    
    final headers = {
      'Content-Type': 'application/json',
    };
    
    try {
      final resp = await http.post(
        processUri,
        headers: headers,
        body: jsonEncode({
          'message': message,
          // Note: prompt is loaded from file on backend, not sent from client
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (resp.statusCode != 200) {
        return null;
      }
      
      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final healthDataMap = jsonMap['healthData'] as Map<String, dynamic>?;
      
      HealthDataEntry? healthDataEntry;
      if (healthDataMap != null) {
        try {
          healthDataEntry = HealthDataEntry.fromJson(healthDataMap);
        } catch (e) {
          // ignore: avoid_print
          print('Error parsing health data entry: $e');
        }
      }
      
      return AiInterpretResult(
        reply: jsonMap['reply'] as String?,
        healthDataEntry: healthDataEntry,
        reasoning: jsonMap['reasoning'] as String?,
      );
    } catch (e) {
      return null;
    }
  }

  /// Save health data entry to backend SQLite
  Future<HealthDataEntry?> _saveHealthDataEntry(HealthDataEntry entry, String baseUrl) async {
    final saveUri = Uri.parse('$baseUrl/api/health-data');
    
    final headers = {
      'Content-Type': 'application/json',
    };
    
    try {
      final resp = await http.post(
        saveUri,
        headers: headers,
        body: jsonEncode(entry.toJson()),
      ).timeout(const Duration(seconds: 10));
      
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return HealthDataEntry.fromJson(jsonMap);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Ask user about trend analysis
  Future<String> askForTrendAnalysis(String type, String category) async {
    return 'Would you like to see the historic trend for this $type parameter?';
  }

  /// Generate trend analysis and chart
  Future<Map<String, dynamic>?> generateTrendAnalysis(String type, String category, String userId) async {
    final base = AppConfig.backendBaseUrl;
    final trendUri = Uri.parse('$base/api/health-data/trend');
    
    if (!await _probeBackend(base)) {
      return null;
    }

    final headers = {
      'Content-Type': 'application/json',
    };
    
    try {
      final resp = await http.post(
        trendUri,
        headers: headers,
        body: jsonEncode({
          'type': type,
          'category': category,
          'userId': userId,
          'limit': 20,
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}

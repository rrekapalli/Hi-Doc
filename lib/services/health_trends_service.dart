import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_service.dart';
import '../models/trend_models.dart';

/// Service responsible for fetching health indicator types, time-series readings and target ranges.
class HealthTrendsService {
  final AuthService? _authService; // nullable for tests
  HealthTrendsService(this._authService);

  Future<Map<String, String>> _headers() async {
    final token = await _authService?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch distinct indicator types for the current user.
  /// Tries GET /api/health-data/types then falls back to param_targets.
  Future<List<String>> fetchIndicatorTypes() async {
    // Primary endpoint (may not exist yet)
    try {
      final resp = await http.get(Uri.parse('${AppConfig.backendBaseUrl}/api/health-data/types'), headers: await _headers());
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
        if (data is Map && data['items'] is List) {
          return (data['items'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (_) {
      // ignore and fallback
    }
    // Fallback: use param_targets list
    try {
      final resp = await http.get(Uri.parse('${AppConfig.backendBaseUrl}/api/param-targets'), headers: await _headers());
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body);
        if (list is List) {
          return list.map((e) => (e['param_code'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (e) {
      debugPrint('fetchIndicatorTypes fallback failed: $e');
    }
    return [];
  }

  /// Fetch time-series data for indicator within a date range.
  Future<List<TrendPoint>> fetchSeries({required String type, required DateTime from, required DateTime to}) async {
    // Hypothetical endpoint: GET /api/health-data/series?type=...&from=...&to=...
    try {
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/health-data/series')
          .replace(queryParameters: {
        'type': type,
        'from': from.millisecondsSinceEpoch.toString(),
        'to': to.millisecondsSinceEpoch.toString(),
      });
      final resp = await http.get(uri, headers: await _headers());
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body);
        if (list is List) {
          return list.map((e) {
            final ts = (e['timestamp'] as num?)?.toInt();
            final vRaw = e['value'];
            final v = vRaw is num ? vRaw.toDouble() : double.tryParse(vRaw?.toString() ?? '');
            if (ts == null || v == null) return null;
            return TrendPoint(timestamp: DateTime.fromMillisecondsSinceEpoch(ts), value: v, unit: e['unit'] as String?);
          }).whereType<TrendPoint>().toList();
        }
      }
    } catch (e) {
      debugPrint('fetchSeries primary endpoint failed: $e');
    }
    // Fallback: use trend endpoint (limited) and parse chart JSON.
    try {
      // trend endpoint requires userId; token auth middleware sets req.userId; pass dummy to keep shape (backend ignores mismatch if using auth override)
      final body = jsonEncode({'type': type, 'category': 'HEALTH_PARAMS', 'userId': 'fallback', 'limit': 200});
      final resp = await http.post(Uri.parse('${AppConfig.backendBaseUrl}/api/health-data/trend'), headers: await _headers(), body: body);
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body);
        final chartStr = map['chart'];
        if (chartStr is String) {
          final list = jsonDecode(chartStr);
          if (list is List) {
            return list.map((e) {
              final ts = (e['timestamp'] as num?)?.toInt();
              final v = (e['value'] as num?)?.toDouble();
              if (ts == null || v == null) return null;
              return TrendPoint(timestamp: DateTime.fromMillisecondsSinceEpoch(ts), value: v, unit: e['unit'] as String?);
            }).whereType<TrendPoint>().toList();
          }
        }
      }
    } catch (e) {
      debugPrint('fetchSeries fallback failed: $e');
    }
    return [];
  }

  Future<TargetRange?> fetchTarget(String type) async {
    try {
      final resp = await http.get(Uri.parse('${AppConfig.backendBaseUrl}/api/param-targets'), headers: await _headers());
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body);
        if (list is List) {
          final row = list.firstWhere((e) => e['param_code'] == type, orElse: () => null);
          if (row != null) {
            return TargetRange(
              min: (row['target_min'] as num?)?.toDouble(),
              max: (row['target_max'] as num?)?.toDouble(),
              preferredUnit: row['preferred_unit'] as String?,
              description: row['description'] as String?,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('fetchTarget failed: $e');
    }
    return null;
  }
}

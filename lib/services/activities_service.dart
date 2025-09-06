import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/activity.dart';
import 'auth_service.dart';

class ActivitiesService {
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService().getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<Activity>> listActivities({int limit = 100, int offset = 0}) async {
    try {
      final headers = await _getAuthHeaders();
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/activities')
          .replace(queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
      });
      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 200) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (jsonMap['items'] as List<dynamic>).cast<Map<String, dynamic>>();
        return items.map((m){
          return Activity.fromJson(m);
        }).toList();
      }
      debugPrint('Failed to load activities: ${resp.statusCode} ${resp.body}');
      return [];
    } catch (e) {
      debugPrint('Error fetching activities: $e');
      return [];
    }
  }

  Future<Activity?> createActivity(Activity activity) async {
    try {
      final headers = await _getAuthHeaders();
      final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/activities');
      final payload = jsonEncode(activity.toJson());
      final resp = await http.post(uri, headers: headers, body: payload);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        return Activity.fromJson(jsonMap);
      }
      debugPrint('Failed to create activity: ${resp.statusCode} ${resp.body}');
      return null;
    } catch (e) {
      debugPrint('Error creating activity: $e');
      return null;
    }
  }
}

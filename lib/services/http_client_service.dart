import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/performance_config.dart';
import '../utils/app_logger.dart';

/// Optimized HTTP client with connection pooling and request caching
class HttpClientService {
  static final HttpClientService _instance = HttpClientService._internal();
  factory HttpClientService() => _instance;
  HttpClientService._internal();

  static http.Client? _client;
  static final Map<String, _CachedResponse> _responseCache = {};

  /// Get persistent HTTP client with connection pooling
  static http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// Make a GET request with optional caching
  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool cache = false,
    Duration? cacheDuration,
  }) async {
    final cacheKey = uri.toString();

    // Check cache first if enabled
    if (cache && _responseCache.containsKey(cacheKey)) {
      final cached = _responseCache[cacheKey]!;
      if (!cached.isExpired(cacheDuration ?? PerformanceConfig.cacheExpiry)) {
        AppLogger.debug('HTTP cache hit: $uri');
        return cached.response;
      } else {
        _responseCache.remove(cacheKey);
      }
    }

    AppLogger.debug('HTTP GET: $uri');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await client
          .get(uri, headers: headers)
          .timeout(PerformanceConfig.mediumTimeout);

      stopwatch.stop();
      AppLogger.performance('HTTP GET $uri', stopwatch.elapsed);

      // Cache successful responses if requested
      if (cache && response.statusCode == 200) {
        _responseCache[cacheKey] = _CachedResponse(response);

        // Limit cache size to prevent memory issues
        if (_responseCache.length > PerformanceConfig.maxCachedItems) {
          final oldestKey = _responseCache.keys.first;
          _responseCache.remove(oldestKey);
        }
      }

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.error('HTTP GET failed: $uri', e);
      rethrow;
    }
  }

  /// Make a POST request
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    AppLogger.debug('HTTP POST: $uri');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await client
          .post(uri, headers: headers, body: body, encoding: encoding)
          .timeout(PerformanceConfig.mediumTimeout);

      stopwatch.stop();
      AppLogger.performance('HTTP POST $uri', stopwatch.elapsed);

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.error('HTTP POST failed: $uri', e);
      rethrow;
    }
  }

  /// Make a PUT request
  static Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    AppLogger.debug('HTTP PUT: $uri');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await client
          .put(uri, headers: headers, body: body, encoding: encoding)
          .timeout(PerformanceConfig.mediumTimeout);

      stopwatch.stop();
      AppLogger.performance('HTTP PUT $uri', stopwatch.elapsed);

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.error('HTTP PUT failed: $uri', e);
      rethrow;
    }
  }

  /// Make a DELETE request
  static Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    AppLogger.debug('HTTP DELETE: $uri');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await client
          .delete(uri, headers: headers)
          .timeout(PerformanceConfig.shortTimeout);

      stopwatch.stop();
      AppLogger.performance('HTTP DELETE $uri', stopwatch.elapsed);

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.error('HTTP DELETE failed: $uri', e);
      rethrow;
    }
  }

  /// Clear cached responses
  static void clearCache() {
    _responseCache.clear();
    AppLogger.debug('HTTP response cache cleared');
  }

  /// Clean up expired cache entries
  static void cleanupExpiredCache() {
    final expiredKeys = <String>[];

    for (final entry in _responseCache.entries) {
      if (entry.value.isExpired(PerformanceConfig.cacheExpiry)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _responseCache.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      AppLogger.debug('Cleaned up ${expiredKeys.length} expired cache entries');
    }
  }

  /// Close the HTTP client and cleanup
  static void dispose() {
    _client?.close();
    _client = null;
    clearCache();
  }
}

/// Cached HTTP response with expiry
class _CachedResponse {
  final http.Response response;
  final DateTime timestamp;

  _CachedResponse(this.response) : timestamp = DateTime.now();

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(timestamp) > maxAge;
  }
}

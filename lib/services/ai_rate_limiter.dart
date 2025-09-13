import 'package:flutter/foundation.dart';
import '../repositories/repository_manager.dart';

/// AI rate limiting service that tracks usage locally in SQLite
/// Enforces monthly limits to prevent excessive API usage
class AIRateLimiter {
  final RepositoryManager _repoManager;
  static const int _monthlyLimit = 100; // 100 calls per user per month

  AIRateLimiter(this._repoManager);

  /// Check if user can make an AI request
  /// Returns true if under limit, false if exceeded
  Future<bool> canMakeRequest(String userId) async {
    try {
      final currentUsage = await _getCurrentMonthUsage(userId);
      return currentUsage < _monthlyLimit;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Error checking rate limit: $e');
      }
      // Default to allowing request if there's an error checking
      return true;
    }
  }

  /// Get current month usage count for user
  Future<int> getCurrentMonthUsage(String userId) async {
    return await _getCurrentMonthUsage(userId);
  }

  /// Get remaining requests for current month
  Future<int> getRemainingRequests(String userId) async {
    final currentUsage = await _getCurrentMonthUsage(userId);
    return (_monthlyLimit - currentUsage).clamp(0, _monthlyLimit);
  }

  /// Record an AI request usage
  /// Should be called after a successful AI API call
  Future<void> recordUsage(
    String userId, {
    String? requestType,
    String? model,
    int? tokensUsed,
    String? requestId,
  }) async {
    try {
      final db = _repoManager.localDb.database;
      final now = DateTime.now();

      await db.insert('ai_usage_logs', {
        'id': _generateId(),
        'user_id': userId,
        'timestamp': now.millisecondsSinceEpoch,
        'month_year': '${now.year}-${now.month.toString().padLeft(2, '0')}',
        'request_type': requestType ?? 'chat',
        'model': model,
        'tokens_used': tokensUsed,
        'request_id': requestId,
      });

      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Recorded usage for user $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Error recording usage: $e');
      }
      // Don't throw - usage tracking shouldn't break the app
    }
  }

  /// Get usage statistics for user (current and previous months)
  Future<Map<String, int>> getUsageStats(String userId) async {
    try {
      final db = _repoManager.localDb.database;
      final now = DateTime.now();

      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final lastMonth = now.month == 1
          ? '${now.year - 1}-12'
          : '${now.year}-${(now.month - 1).toString().padLeft(2, '0')}';

      // Get current month usage
      final currentResult = await db.rawQuery(
        '''
        SELECT COUNT(*) as count FROM ai_usage_logs 
        WHERE user_id = ? AND month_year = ?
      ''',
        [userId, currentMonth],
      );

      // Get last month usage
      final lastResult = await db.rawQuery(
        '''
        SELECT COUNT(*) as count FROM ai_usage_logs 
        WHERE user_id = ? AND month_year = ?
      ''',
        [userId, lastMonth],
      );

      return {
        'current_month': currentResult.first['count'] as int,
        'last_month': lastResult.first['count'] as int,
        'limit': _monthlyLimit,
        'remaining': (_monthlyLimit - (currentResult.first['count'] as int))
            .clamp(0, _monthlyLimit),
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Error getting usage stats: $e');
      }
      return {
        'current_month': 0,
        'last_month': 0,
        'limit': _monthlyLimit,
        'remaining': _monthlyLimit,
      };
    }
  }

  /// Clean up old usage logs (older than 2 years)
  Future<void> cleanupOldLogs() async {
    try {
      final db = _repoManager.localDb.database;
      final twoYearsAgo = DateTime.now().subtract(const Duration(days: 730));

      await db.delete(
        'ai_usage_logs',
        where: 'timestamp < ?',
        whereArgs: [twoYearsAgo.millisecondsSinceEpoch],
      );

      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Cleaned up old usage logs');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Error cleaning up logs: $e');
      }
    }
  }

  /// Get user-friendly rate limit message
  String getRateLimitMessage(String userId) {
    return 'You have reached your monthly limit of $_monthlyLimit AI requests. '
        'Your limit will reset next month. This helps us manage costs and ensure '
        'fair usage for all users.';
  }

  /// Internal helper to get current month usage
  Future<int> _getCurrentMonthUsage(String userId) async {
    final db = _repoManager.localDb.database;
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM ai_usage_logs 
      WHERE user_id = ? AND month_year = ?
    ''',
      [userId, currentMonth],
    );

    return result.first['count'] as int;
  }

  /// Generate unique ID for usage log entries
  String _generateId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  /// Reset usage for a user (admin/debug function)
  Future<void> resetUserUsage(String userId) async {
    try {
      final db = _repoManager.localDb.database;
      final now = DateTime.now();
      final currentMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      await db.delete(
        'ai_usage_logs',
        where: 'user_id = ? AND month_year = ?',
        whereArgs: [userId, currentMonth],
      );

      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Reset usage for user $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AIRateLimiter] Error resetting usage: $e');
      }
    }
  }
}

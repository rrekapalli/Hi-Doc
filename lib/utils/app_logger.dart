import 'package:flutter/foundation.dart';
import 'performance_config.dart';

/// Centralized logging utility with performance optimizations
class AppLogger {
  AppLogger._();
  
  static void debug(String message, [Object? error]) {
    if (PerformanceConfig.enableDebugLogs) {
      debugPrint('[DEBUG] $message${error != null ? ' - $error' : ''}');
    }
  }
  
  static void info(String message) {
    if (PerformanceConfig.enableDebugLogs) {
      debugPrint('[INFO] $message');
    }
  }
  
  static void warning(String message, [Object? error]) {
    if (PerformanceConfig.enableDebugLogs) {
      debugPrint('[WARNING] $message${error != null ? ' - $error' : ''}');
    }
  }
  
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    // Always log errors, even in production
    debugPrint('[ERROR] $message${error != null ? ' - $error' : ''}');
    if (stackTrace != null && PerformanceConfig.enableDebugLogs) {
      debugPrint('[STACK] $stackTrace');
    }
  }
  
  static void performance(String operation, Duration duration) {
    if (PerformanceConfig.enableDebugLogs) {
      debugPrint('[PERF] $operation took ${duration.inMilliseconds}ms');
    }
  }
}

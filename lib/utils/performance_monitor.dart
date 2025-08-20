import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'performance_config.dart';

/// Performance monitoring utility for Hi-Doc application
class PerformanceMonitor {
  PerformanceMonitor._();
  
  static final Map<String, Stopwatch> _timers = {};
  static final List<PerformanceMetric> _metrics = [];
  
  /// Start timing an operation
  static void startTimer(String operation) {
    if (!PerformanceConfig.enableDebugLogs) return;
    
    _timers[operation] = Stopwatch()..start();
  }
  
  /// Stop timing and record the operation
  static void stopTimer(String operation) {
    if (!PerformanceConfig.enableDebugLogs) return;
    
    final timer = _timers.remove(operation);
    if (timer != null) {
      timer.stop();
      final metric = PerformanceMetric(
        operation: operation,
        duration: timer.elapsed,
        timestamp: DateTime.now(),
      );
      
      _metrics.add(metric);
      
      // Log slow operations
      if (timer.elapsed.inMilliseconds > 1000) {
        developer.log(
          '[SLOW] $operation took ${timer.elapsed.inMilliseconds}ms',
          name: 'Performance',
        );
      }
      
      // Keep only last 100 metrics to prevent memory leaks
      if (_metrics.length > 100) {
        _metrics.removeRange(0, _metrics.length - 100);
      }
    }
  }
  
  /// Time an async operation
  static Future<T> timeAsync<T>(
    String operation, 
    Future<T> Function() function,
  ) async {
    startTimer(operation);
    try {
      return await function();
    } finally {
      stopTimer(operation);
    }
  }
  
  /// Time a synchronous operation
  static T timeSync<T>(
    String operation,
    T Function() function,
  ) {
    startTimer(operation);
    try {
      return function();
    } finally {
      stopTimer(operation);
    }
  }
  
  /// Get performance summary
  static Map<String, dynamic> getSummary() {
    if (!PerformanceConfig.enableDebugLogs) {
      return {'enabled': false};
    }
    
    final operations = <String, List<Duration>>{};
    for (final metric in _metrics) {
      operations.putIfAbsent(metric.operation, () => []).add(metric.duration);
    }
    
    final summary = <String, dynamic>{
      'enabled': true,
      'totalMetrics': _metrics.length,
      'operations': <String, Map<String, dynamic>>{},
    };
    
    for (final entry in operations.entries) {
      final durations = entry.value;
      final total = durations.fold<Duration>(
        Duration.zero, 
        (prev, duration) => prev + duration,
      );
      final average = Duration(
        milliseconds: total.inMilliseconds ~/ durations.length,
      );
      final max = durations.reduce((a, b) => a > b ? a : b);
      final min = durations.reduce((a, b) => a < b ? a : b);
      
      summary['operations'][entry.key] = {
        'count': durations.length,
        'totalMs': total.inMilliseconds,
        'averageMs': average.inMilliseconds,
        'maxMs': max.inMilliseconds,
        'minMs': min.inMilliseconds,
      };
    }
    
    return summary;
  }
  
  /// Clear all metrics
  static void clear() {
    _metrics.clear();
    _timers.clear();
  }
}

/// Represents a single performance metric
class PerformanceMetric {
  final String operation;
  final Duration duration;
  final DateTime timestamp;
  
  const PerformanceMetric({
    required this.operation,
    required this.duration,
    required this.timestamp,
  });
}

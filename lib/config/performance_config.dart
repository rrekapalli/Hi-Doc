import 'package:flutter/foundation.dart';

/// Performance configuration for the Hi-Doc application
class PerformanceConfig {
  PerformanceConfig._();
  
  /// Enable/disable debug logging
  static const bool enableDebugLogs = kDebugMode;
  
  /// HTTP request timeout durations
  static const Duration shortTimeout = Duration(seconds: 5);
  static const Duration mediumTimeout = Duration(seconds: 10);
  static const Duration longTimeout = Duration(seconds: 30);
  
  /// Database batch sizes
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  
  /// Debounce delays
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration inputDebounce = Duration(milliseconds: 500);
  
  /// Cache configurations
  static const int maxCachedItems = 1000;
  static const Duration cacheExpiry = Duration(minutes: 30);
  
  /// UI performance settings
  static const double listItemHeight = 72.0;
  static const int visibleItemBuffer = 5;
  
  /// Memory management
  static const bool enableMemoryOptimizations = true;
  static const int maxImageCacheSize = 50 * 1024 * 1024; // 50MB
}

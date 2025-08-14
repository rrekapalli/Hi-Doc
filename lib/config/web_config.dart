import 'package:flutter/foundation.dart';

class WebConfig {
  static const bool enableWebGL = true;
  static const bool enableServiceWorker = true;
  static const Duration initializationDelay = Duration(milliseconds: 200);
  
  // Web-specific performance settings
  static const Map<String, dynamic> webGLOptions = {
    'antialias': false,
    'depth': false,
    'stencil': false,
    'alpha': false,
    'powerPreference': 'high-performance',
  };
  
  // Channel buffer configurations to prevent message discarding
  static const Map<String, int> channelBuffers = {
    'flutter/lifecycle': 10,
    'flutter/platform': 10,
    'flutter/settings': 10,
    'flutter/textinput': 10,
  };
  
  // Web-specific error handling
  static void configureWebErrorHandling() {
    if (kIsWeb) {
      // Set up global error handler for web
      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          print('Web Flutter Error: ${details.exception}');
          print('Stack trace: ${details.stack}');
        }
        // In production, you might want to send this to a logging service
      };
    }
  }
}

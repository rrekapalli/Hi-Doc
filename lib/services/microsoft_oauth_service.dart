import 'dart:convert';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'package:flutter/material.dart';

/// Service for handling Microsoft OAuth authentication directly without backend dependency
class MicrosoftOAuthService {
  static final MicrosoftOAuthService _instance =
      MicrosoftOAuthService._internal();
  factory MicrosoftOAuthService() => _instance;
  MicrosoftOAuthService._internal();

  AadOAuth? _aadOAuth;
  Map<String, dynamic>? _currentUser;

  /// Current signed in Microsoft user
  Map<String, dynamic>? get currentUser => _currentUser;

  /// Initialize Microsoft OAuth with configuration
  void initialize({
    required String clientId,
    String? tenant,
    String? redirectUri,
    String? scope,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final config = Config(
      tenant: tenant ?? 'common',
      clientId: clientId,
      scope: scope ?? 'openid profile email User.Read',
      redirectUri: redirectUri ?? 'http://localhost:8080/redirect',
      navigatorKey: navigatorKey ?? GlobalKey<NavigatorState>(),
      webUseRedirect: false,
    );

    _aadOAuth = AadOAuth(config);
  }

  /// Sign in with Microsoft
  /// Returns user profile information on success
  Future<Map<String, dynamic>> signIn() async {
    if (_aadOAuth == null) {
      throw Exception(
        'Microsoft OAuth not initialized. Call initialize() first.',
      );
    }

    try {
      await _aadOAuth!.login();

      // Get access token to verify login success
      final accessToken = await _aadOAuth!.getAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Failed to get access token after login');
      }

      // Get user profile information
      _currentUser = await _getUserProfile(accessToken);
      return _currentUser!;
    } catch (error) {
      throw Exception('Microsoft sign-in failed: $error');
    }
  }

  /// Sign out from Microsoft
  Future<void> signOut() async {
    if (_aadOAuth == null) return;

    try {
      await _aadOAuth!.logout();
      _currentUser = null;
    } catch (error) {
      throw Exception('Microsoft sign-out failed: $error');
    }
  }

  /// Check if user is currently signed in
  bool get isSignedIn {
    if (_aadOAuth == null || _currentUser == null) return false;

    // Check if we have user data (simplified check)
    return true;
  }

  /// Get access token for API calls
  Future<String?> getAccessToken() async {
    if (_aadOAuth == null) return null;
    return await _aadOAuth!.getAccessToken();
  }

  /// Get user profile information from Microsoft Graph API
  Future<Map<String, dynamic>> _getUserProfile(String accessToken) async {
    try {
      // Parse JWT token to extract user info (basic implementation)
      final parts = accessToken.split('.');
      if (parts.length >= 2) {
        final payload = parts[1];
        // Add padding if necessary
        final normalizedPayload = payload.padRight(
          (payload.length + 3) ~/ 4 * 4,
          '=',
        );

        try {
          final decoded = utf8.decode(base64.decode(normalizedPayload));
          final claims = json.decode(decoded) as Map<String, dynamic>;

          return {
            'id': claims['sub'] ?? claims['oid'] ?? 'unknown',
            'email': claims['email'] ?? claims['preferred_username'] ?? '',
            'displayName': claims['name'] ?? '',
            'givenName': claims['given_name'] ?? '',
            'surname': claims['family_name'] ?? '',
            'tenantId': claims['tid'] ?? '',
          };
        } catch (e) {
          // If token parsing fails, return minimal info
          return {
            'id': 'unknown',
            'email': '',
            'displayName': 'Microsoft User',
          };
        }
      }

      // Fallback
      return {'id': 'unknown', 'email': '', 'displayName': 'Microsoft User'};
    } catch (error) {
      throw Exception('Failed to get user profile: $error');
    }
  }

  /// Get user profile information
  Map<String, dynamic>? getUserProfile() {
    return _currentUser;
  }
}

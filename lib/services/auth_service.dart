import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

// NOTE: You must add firebase_options.dart via flutterfire configure.

class AuthService {
  final FirebaseAuth? _auth; // null on web
  // Google Sign-In temporarily disabled due to API mismatch; re-enable after stabilizing dependency.
  // GoogleSignIn? _googleSignIn;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  AuthService() : _auth = kIsWeb ? null : FirebaseAuth.instance;

  Stream<User?> authStateChanges() => _auth?.authStateChanges() ?? const Stream<User?>.empty();

  User? get currentUser => _auth?.currentUser;

  Future<void> initFirebase({FirebaseOptions? options}) async {
  if (_auth == null) return; // web
  if (Firebase.apps.isEmpty) {
      if (options != null) {
        await Firebase.initializeApp(options: options);
      } else {
        await Firebase.initializeApp();
      }
    }
  }

  Future<UserCredential> signInWithGoogle() async => throw Exception('Google Sign-In temporarily disabled');

  // Microsoft sign-in via Azure AD (App Registration) - configure values below.
  // Provide these via constructor or env in production.
  final String msClientId = 'YOUR_MICROSOFT_APP_CLIENT_ID';
  final String msTenant = 'common'; // or organizations / consumers or specific tenant id
  final String msRedirectUri = 'com.example.app://auth'; // match app's manifest
  final List<String> msScopes = const ['openid', 'profile', 'email', 'User.Read', 'offline_access'];

  Future<UserCredential> signInWithMicrosoft() async {
    // 1. Use AppAuth to perform interactive auth
    if (_auth == null) {
      throw Exception('Microsoft sign-in disabled on web preview');
    }
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        msClientId,
        msRedirectUri,
        discoveryUrl: 'https://login.microsoftonline.com/$msTenant/v2.0/.well-known/openid-configuration',
        scopes: msScopes,
        promptValues: ['login'],
      ),
    );

    // 2. Store refresh token securely for future Graph API / sync operations
    if (result.refreshToken != null) {
      await _secure.write(key: 'ms_refresh_token', value: result.refreshToken);
    }

    // 3. Exchange Microsoft id token and access token with backend for Firebase custom token
    final idToken = result.idToken;
    final accessToken = result.accessToken;
    if (idToken == null || accessToken == null) {
      throw Exception('Missing Microsoft tokens');
    }
    final resp = await http.post(AppConfig.microsoftExchangeUri(),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken, 'access_token': accessToken}));
    if (resp.statusCode != 200) {
      throw Exception('Microsoft exchange failed: ${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final customToken = body['firebase_custom_token'] as String?;
    if (customToken == null) {
      throw Exception('No firebase_custom_token in response');
    }
  return _auth.signInWithCustomToken(customToken);
  }

  Future<void> signOut() async {
    if (_auth == null) return;
  await _auth.signOut();
  }
}

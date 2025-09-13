import 'package:google_sign_in/google_sign_in.dart';

/// Service for handling Google OAuth authentication directly without backend dependency
class GoogleOAuthService {
  static final GoogleOAuthService _instance = GoogleOAuthService._internal();
  factory GoogleOAuthService() => _instance;
  GoogleOAuthService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _currentUser;

  /// Current signed in Google user
  GoogleSignInAccount? get currentUser => _currentUser;

  /// Stream of authentication state changes
  Stream<GoogleSignInAuthenticationEvent> get authStateChanges =>
      _googleSignIn.authenticationEvents;

  /// Initialize the service and listen to authentication events
  Future<void> initialize({String? clientId, String? serverClientId}) async {
    await _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );

    // Listen to authentication events to track current user
    _googleSignIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          _currentUser = event.user;
          break;
        case GoogleSignInAuthenticationEventSignOut():
          _currentUser = null;
          break;
      }
    });

    // Try lightweight authentication to restore previous session
    await _googleSignIn.attemptLightweightAuthentication();
  }

  /// Sign in with Google
  /// Returns GoogleSignInAccount on success
  Future<GoogleSignInAccount> signIn() async {
    try {
      if (_googleSignIn.supportsAuthenticate()) {
        final user = await _googleSignIn.authenticate();
        _currentUser = user;
        return user;
      } else {
        throw Exception('Google sign-in not supported on this platform');
      }
    } catch (error) {
      throw Exception('Google sign-in failed: $error');
    }
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
    } catch (error) {
      throw Exception('Google sign-out failed: $error');
    }
  }

  /// Disconnect Google account (revoke access)
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
    } catch (error) {
      throw Exception('Google disconnect failed: $error');
    }
  }

  /// Check if user is currently signed in
  bool get isSignedIn => _currentUser != null;

  /// Get user profile information
  Map<String, dynamic>? getUserProfile() {
    if (_currentUser == null) return null;

    return {
      'id': _currentUser!.id,
      'email': _currentUser!.email,
      'displayName': _currentUser!.displayName,
      'photoUrl': _currentUser!.photoUrl,
    };
  }
}

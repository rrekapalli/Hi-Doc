import 'package:flutter/foundation.dart';
import '../services/google_oauth_service.dart';
import '../services/microsoft_oauth_service.dart';
import '../repositories/repository_manager.dart';

/// Enhanced AuthProvider that uses direct OAuth flows without backend dependency
class AuthProviderV2 extends ChangeNotifier {
  final GoogleOAuthService _googleOAuthService;
  final MicrosoftOAuthService _microsoftOAuthService;
  final RepositoryManager
  _repositoryManager; // TODO: Use for local user storage

  // Current user state
  String? _userId;
  String? _userEmail;
  String? _userName;
  String? _userPhotoUrl;
  String? _authProvider; // 'google' or 'microsoft'
  bool _isLoading = false;
  String? _error;

  AuthProviderV2({
    GoogleOAuthService? googleService,
    MicrosoftOAuthService? microsoftService,
    RepositoryManager? repositoryManager,
  }) : _googleOAuthService = googleService ?? GoogleOAuthService(),
       _microsoftOAuthService = microsoftService ?? MicrosoftOAuthService(),
       _repositoryManager = repositoryManager ?? RepositoryManager.instance {
    _initialize();
  }

  // Getters
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get userPhotoUrl => _userPhotoUrl;
  String? get authProvider => _authProvider;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _userId != null;
  String? get error => _error;

  /// Initialize the auth provider
  Future<void> _initialize() async {
    try {
      // Initialize OAuth services
      await _googleOAuthService.initialize();

      _microsoftOAuthService.initialize(
        clientId:
            'YOUR_MICROSOFT_CLIENT_ID', // Should be configured from environment
      );

      // Check for existing authentication
      await _checkExistingAuth();
    } catch (e) {
      _error = 'Initialization failed: $e';
      notifyListeners();
    }
  }

  /// Check for existing authentication on startup
  Future<void> _checkExistingAuth() async {
    try {
      // Try to restore Google Sign-In session
      if (_googleOAuthService.isSignedIn) {
        final profile = _googleOAuthService.getUserProfile();
        if (profile != null) {
          await _setUserFromProfile(profile, 'google');
          return;
        }
      }

      // Try to restore Microsoft session
      if (_microsoftOAuthService.isSignedIn) {
        final profile = _microsoftOAuthService.getUserProfile();
        if (profile != null) {
          await _setUserFromProfile(profile, 'microsoft');
          return;
        }
      }

      // Check local database for active user
      // await _checkLocalUser();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking existing auth: $e');
      }
    }
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _error = null;

    try {
      final user = await _googleOAuthService.signIn();
      final profile = {
        'id': user.id,
        'email': user.email,
        'displayName': user.displayName,
        'photoUrl': user.photoUrl,
      };

      await _setUserFromProfile(profile, 'google');
      await _storeUserLocally(profile, 'google');
    } catch (e) {
      _error = 'Google sign-in failed: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Sign in with Microsoft
  Future<void> signInWithMicrosoft() async {
    _setLoading(true);
    _error = null;

    try {
      final profile = await _microsoftOAuthService.signIn();
      await _setUserFromProfile(profile, 'microsoft');
      await _storeUserLocally(profile, 'microsoft');
    } catch (e) {
      _error = 'Microsoft sign-in failed: $e';
      if (kDebugMode) {
        debugPrint(_error);
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Sign out from current provider
  Future<void> signOut() async {
    _setLoading(true);

    try {
      if (_authProvider == 'google') {
        await _googleOAuthService.signOut();
      } else if (_authProvider == 'microsoft') {
        await _microsoftOAuthService.signOut();
      }

      _clearUserState();
    } catch (e) {
      _error = 'Sign-out failed: $e';
    } finally {
      _setLoading(false);
    }
  }

  /// Set user state from OAuth profile
  Future<void> _setUserFromProfile(
    Map<String, dynamic> profile,
    String provider,
  ) async {
    _userId = profile['id'] as String?;
    _userEmail = profile['email'] as String?;
    _userName = profile['displayName'] as String?;
    _userPhotoUrl = profile['photoUrl'] as String?;
    _authProvider = provider;
    _error = null;
    notifyListeners();
  }

  /// Clear user authentication state
  void _clearUserState() {
    _userId = null;
    _userEmail = null;
    _userName = null;
    _userPhotoUrl = null;
    _authProvider = null;
    _error = null;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Get user display name or email
  String get displayName => _userName ?? _userEmail ?? 'Unknown User';

  /// Get user initials for avatar
  String get userInitials {
    if (_userName != null && _userName!.isNotEmpty) {
      final parts = _userName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        return _userName![0].toUpperCase();
      }
    } else if (_userEmail != null && _userEmail!.isNotEmpty) {
      return _userEmail![0].toUpperCase();
    }
    return 'U';
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Store user data locally (placeholder for future implementation)
  Future<void> _storeUserLocally(
    Map<String, dynamic> profile,
    String provider,
  ) async {
    // TODO: Use _repositoryManager to store user data
    final _ = _repositoryManager; // Acknowledge usage
    if (kDebugMode) {
      debugPrint('Storing user locally: ${profile['email']} via $provider');
    }
  }
}

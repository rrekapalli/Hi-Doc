import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  User? _user;
  bool _initializing = true;
  String? _error;

  AuthProvider(this._authService) {
    if (kIsWeb) {
      // Bypass real auth on web preview; create a mock user-like object via a lightweight interface.
      _initializing = false;
      notifyListeners();
    } else {
      _authService.authStateChanges().listen((u) {
        _user = u;
        _initializing = false;
        notifyListeners();
      });
    }
  }

  User? get user => _user;
  bool get isLoading => _initializing;
  String? get error => _error;

  Future<void> signInGoogle() async {
    _error = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        // simulate success
        return;
      }
      await _authService.signInWithGoogle();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> signInMicrosoft() async {
    _error = null;
    notifyListeners();
    try {
      if (kIsWeb) {
        return;
      }
      await _authService.signInWithMicrosoft();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> signOut() async {
  if (kIsWeb) return; // nothing to do
  await _authService.signOut();
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final bool enabled;
  final AuthService? _authService;
  User? _user;
  bool _loading = true;
  Object? _error;

  AuthProvider({AuthService? authService, this.enabled = true})
      : _authService = enabled ? (authService ?? AuthService()) : null {
    if (!enabled) {
      _loading = false;
      _user = null;
      return;
    }

    _authService!.authStateChanges.listen((user) {
      _user = user;
      _loading = false;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      _error = e;
      _loading = false;
      notifyListeners();
    });
  }

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _loading;
  Object? get error => _error;

  void _ensureEnabled() {
    if (!enabled || _authService == null) {
      throw StateError('Auth is disabled on this platform.');
    }
  }

  Future<void> signInAnonymously() async {
    _ensureEnabled();
    _loading = true;
    notifyListeners();
    try {
      await _authService!.signInAnonymously();
    } finally {
      _loading = false;
    }
  }

  Future<void> signOut() async {
    _ensureEnabled();
    await _authService!.signOut();
  }

  Future<void> deleteAccount() async {
    _ensureEnabled();
    await _authService!.deleteAccount();
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'credit_service.dart';

class CreditProvider extends ChangeNotifier {
  CreditProvider({CreditService? service})
    : _service = service ?? CreditService();

  final CreditService _service;

  String? _uid;
  bool _loading = false;
  bool _hydrated = false;
  Object? _error;
  int _balance = 0;

  StreamSubscription<int>? _sub;

  String? get uid => _uid;
  bool get loading => _loading;
  bool get hydrated => _hydrated;
  Object? get error => _error;
  int get balance => _balance;

  Future<void> setUser(User? user) async {
    final nextUid = (user == null || user.isAnonymous) ? null : user.uid;
    if (nextUid == _uid) return;

    await _sub?.cancel();
    _sub = null;
    _error = null;
    _uid = nextUid;

    if (_uid == null) {
      _balance = 0;
      _hydrated = true;
      notifyListeners();
      return;
    }

    _loading = true;
    _hydrated = false;
    notifyListeners();

    try {
      final remote = await _service.fetchBalance(_uid!);
      _balance = remote;
      _hydrated = true;
      notifyListeners();

      _sub = _service.watchBalance(_uid!).listen((v) {
        _balance = v;
        notifyListeners();
      });
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_uid == null) return;
    try {
      final remote = await _service.fetchBalance(_uid!);
      _balance = remote;
      notifyListeners();
    } catch (e) {
      _error = e;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _sub?.cancel();
    super.dispose();
  }
}

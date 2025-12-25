import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'device_identity_service.dart';

/// On desktop, signs out automatically when this PC is revoked/removed
/// from `users/{uid}/devices/{deviceId}`.
class PcDeviceRevocationWatcher {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deviceSub;
  String? _deviceId;
  bool _signingOut = false;
  Timer? _missingTimer;

  Future<void> start() async {
    _deviceId ??= await DeviceIdentityService.getDeviceId();
    _authSub ??= _auth.authStateChanges().listen(_onAuthChanged);
    await _onAuthChanged(_auth.currentUser);
  }

  Future<void> dispose() async {
    _missingTimer?.cancel();
    _missingTimer = null;
    await _deviceSub?.cancel();
    _deviceSub = null;
    await _authSub?.cancel();
    _authSub = null;
  }

  Future<void> _onAuthChanged(User? user) async {
    await _deviceSub?.cancel();
    _deviceSub = null;

    if (_signingOut) return;
    if (user == null || user.isAnonymous) return;

    final deviceId = _deviceId ?? await DeviceIdentityService.getDeviceId();
    _deviceId = deviceId;

    final ref = _db
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId);

    _deviceSub = ref.snapshots().listen((snap) async {
      if (_signingOut) return;
      if (snap.exists) {
        _missingTimer?.cancel();
        _missingTimer = null;
        return;
      }

      // Avoid false positives on initial login or cache races:
      // re-check once against the server after a short delay.
      _missingTimer?.cancel();
      _missingTimer = Timer(const Duration(seconds: 2), () async {
        if (_signingOut) return;
        final cur = _auth.currentUser;
        if (cur == null || cur.isAnonymous || cur.uid != user.uid) return;
        try {
          final serverSnap = await ref.get(const GetOptions(source: Source.server));
          if (serverSnap.exists) return;
        } catch (_) {
          // If server fetch fails, don't sign out based on missing local data.
          return;
        }

        _signingOut = true;
        try {
          await _auth.signOut();
        } finally {
          _signingOut = false;
        }
      });
    });
  }
}

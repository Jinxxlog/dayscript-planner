import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/entitlement.dart';
import 'entitlement_cache.dart';
import 'entitlement_service.dart';

class EntitlementProvider extends ChangeNotifier {
  EntitlementProvider({EntitlementService? service, EntitlementCache? cache})
    : _service = service ?? EntitlementService(),
      _cache = cache ?? EntitlementCache();

  final EntitlementService _service;
  final EntitlementCache _cache;

  String? _uid;
  bool _loading = false;
  bool _hydrated = false;
  Object? _error;

  Entitlement _effective = Entitlement.standard();
  StreamSubscription<Entitlement?>? _sub;

  bool get loading => _loading;
  bool get hydrated => _hydrated;
  Object? get error => _error;
  String? get uid => _uid;

  Entitlement get raw => _effective;
  EntitlementBalance balanceAt(DateTime now) => _effective.balanceAt(now);
  bool isAdFree(DateTime now) => _effective.isAdFree(now);

  Future<void> setUser(User? user) async {
    final nextUid = (user == null || user.isAnonymous) ? null : user.uid;
    if (nextUid == _uid) return;

    await _sub?.cancel();
    _sub = null;
    _error = null;
    _uid = nextUid;

    if (_uid == null) {
      _effective = Entitlement.standard();
      _hydrated = true;
      notifyListeners();
      return;
    }

    _loading = true;
    _hydrated = false;
    notifyListeners();

    try {
      final cached = await _cache.load(_uid!);
      _hydrated = true;
      if (cached != null) {
        _effective = cached;
        notifyListeners();
      } else {
        notifyListeners();
      }

      final remote = await _service.fetch(_uid!);
      _effective = remote ?? Entitlement.standard();
      await _cache.save(_uid!, _effective);

      _sub = _service.watch(_uid!).listen((e) async {
        if (_uid == null) return;
        _effective = e ?? Entitlement.standard();
        await _cache.save(_uid!, _effective);
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
      final remote = await _service.fetch(_uid!);
      _effective = remote ?? Entitlement.standard();
      await _cache.save(_uid!, _effective);
      notifyListeners();
    } catch (e) {
      _error = e;
      notifyListeners();
    }
  }

  Future<void> grantDaysDebug({
    required SubscriptionTier tier,
    required int days,
    DateTime? now,
  }) async {
    if (_uid == null) return;
    final seconds = days * 86400;
    final t = now ?? DateTime.now();
    final next = switch (tier) {
      SubscriptionTier.pro => _effective.applyDelta(
        now: t,
        addProSeconds: seconds,
      ),
      SubscriptionTier.premium => _effective.applyDelta(
        now: t,
        addPremiumSeconds: seconds,
      ),
      SubscriptionTier.standard => Entitlement.standard(lastAccruedAt: t),
    };
    _effective = next;
    notifyListeners();
    try {
      await _service.upsert(_uid!, next);
    } catch (_) {}
    await _cache.save(_uid!, next);
  }

  Future<void> clearDebug({DateTime? now}) async {
    if (_uid == null) return;
    final next = Entitlement.standard(lastAccruedAt: (now ?? DateTime.now()));
    _effective = next;
    notifyListeners();
    try {
      await _service.upsert(_uid!, next);
    } catch (_) {}
    await _cache.save(_uid!, next);
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _sub?.cancel();
    super.dispose();
  }
}

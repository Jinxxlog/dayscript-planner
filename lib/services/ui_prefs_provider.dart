import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/ui_prefs.dart';
import 'ui_prefs_cache.dart';
import 'ui_prefs_service.dart';

class UiPrefsProvider extends ChangeNotifier {
  UiPrefsProvider({UiPrefsService? service, UiPrefsCache? cache})
      : _service = service ?? UiPrefsService(),
        _cache = cache ?? UiPrefsCache();

  static const String _localCacheId = 'local';

  final UiPrefsService _service;
  final UiPrefsCache _cache;

  String? _uid;
  String _cacheId = _localCacheId;
  bool _loading = false;
  bool _hydrated = false;
  Object? _error;

  UiPrefs _effective = UiPrefs.defaults();
  StreamSubscription<UiPrefs?>? _sub;

  bool get loading => _loading;
  bool get hydrated => _hydrated;
  Object? get error => _error;
  String? get uid => _uid;

  UiPrefs get raw => _effective;
  String get fontFamily => _effective.fontFamily;
  String get themePresetId => _effective.themePresetId;
  double get textScale => _effective.textScale;

  Future<void> setUser(User? user) async {
    final nextUid = (user == null || user.isAnonymous) ? null : user.uid;
    final nextCacheId = nextUid ?? _localCacheId;
    if (nextUid == _uid && nextCacheId == _cacheId) return;

    await _sub?.cancel();
    _sub = null;
    _error = null;
    _uid = nextUid;
    _cacheId = nextCacheId;

    _loading = true;
    _hydrated = false;
    notifyListeners();

    try {
      final cached = await _cache.load(_cacheId);
      _hydrated = true;
      if (cached != null) {
        _effective = cached;
        notifyListeners();
      } else {
        _effective = UiPrefs.defaults();
        notifyListeners();
      }

      if (_uid == null) return;

      final remote = await _service.fetch(_uid!);
      _effective = remote ?? UiPrefs.defaults();
      await _cache.save(_cacheId, _effective);

      _sub = _service.watch(_uid!).listen((p) async {
        if (_uid == null) return;
        _effective = p ?? UiPrefs.defaults();
        await _cache.save(_cacheId, _effective);
        notifyListeners();
      });
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setFontFamily(String fontFamily) async {
    await _setFontFamily(fontFamily, persistRemote: true);
  }

  Future<void> setFontFamilyLocal(String fontFamily) async {
    await _setFontFamily(fontFamily, persistRemote: false);
  }

  Future<void> _setFontFamily(
    String fontFamily, {
    required bool persistRemote,
  }) async {
    final normalized = fontFamily.trim();
    final next = UiPrefs(
      fontFamily: normalized,
      themePresetId: _effective.themePresetId,
      textScale: _effective.textScale,
      updatedAt: DateTime.now().toUtc(),
    );
    _effective = next;
    notifyListeners();
    await _cache.save(_cacheId, next);
    if (persistRemote && _uid != null) {
      await _service.upsert(_uid!, next);
    }
  }

  Future<void> setThemePresetId(String themePresetId) async {
    await _setThemePresetId(themePresetId, persistRemote: true);
  }

  Future<void> setThemePresetIdLocal(String themePresetId) async {
    await _setThemePresetId(themePresetId, persistRemote: false);
  }

  Future<void> _setThemePresetId(
    String themePresetId, {
    required bool persistRemote,
  }) async {
    final normalized = themePresetId.trim();
    final next = UiPrefs(
      fontFamily: _effective.fontFamily,
      themePresetId: normalized,
      textScale: _effective.textScale,
      updatedAt: DateTime.now().toUtc(),
    );
    _effective = next;
    notifyListeners();
    await _cache.save(_cacheId, next);
    if (persistRemote && _uid != null) {
      await _service.upsert(_uid!, next);
    }
  }

  Future<void> refresh() async {
    if (_uid == null) return;
    try {
      final remote = await _service.fetch(_uid!);
      _effective = remote ?? UiPrefs.defaults();
      await _cache.save(_cacheId, _effective);
      notifyListeners();
    } catch (e) {
      _error = e;
      notifyListeners();
    }
  }

  Future<void> setTextScale(double textScale) async {
    await _setTextScale(textScale, persistRemote: true);
  }

  Future<void> setTextScaleLocal(double textScale) async {
    await _setTextScale(textScale, persistRemote: false);
  }

  Future<void> _setTextScale(
    double textScale, {
    required bool persistRemote,
  }) async {
    final normalized = textScale.clamp(0.85, 1.25).toDouble();
    final next = UiPrefs(
      fontFamily: _effective.fontFamily,
      themePresetId: _effective.themePresetId,
      textScale: normalized,
      updatedAt: DateTime.now().toUtc(),
    );
    _effective = next;
    notifyListeners();
    await _cache.save(_cacheId, next);
    if (persistRemote && _uid != null) {
      await _service.upsert(_uid!, next);
    }
  }

  Future<void> reloadFromCache() async {
    final cached = await _cache.load(_cacheId);
    if (cached == null) return;
    _effective = cached;
    _hydrated = true;
    notifyListeners();
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _sub?.cancel();
    super.dispose();
  }
}

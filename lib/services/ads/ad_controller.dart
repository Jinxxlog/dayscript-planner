import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ads_debug_settings_provider.dart';
import '../entitlement_provider.dart';
import 'ad_service.dart';
import 'admob_ad_service.dart';
import 'noop_ad_service.dart';

class AdController extends ChangeNotifier {
  AdController({
    required EntitlementProvider entitlement,
    required AdsDebugSettingsProvider debugSettings,
  })  : _entitlement = entitlement,
        _debugSettings = debugSettings,
        _service = _pickService() {
    _bind();
    // ignore: discarded_futures
    _debugSettings.load().then((_) => _recompute());
    _recompute();
  }

  EntitlementProvider _entitlement;
  AdsDebugSettingsProvider _debugSettings;
  final AdService _service;

  Widget? _banner;
  bool _loading = false;

  bool get shouldShow => _banner != null;
  Widget? get banner => _banner;
  bool get loading => _loading;

  void updateDeps({
    required EntitlementProvider entitlement,
    required AdsDebugSettingsProvider debugSettings,
  }) {
    if (identical(entitlement, _entitlement) &&
        identical(debugSettings, _debugSettings)) {
      return;
    }
    _unbind();
    _entitlement = entitlement;
    _debugSettings = debugSettings;
    _bind();
    // ignore: discarded_futures
    _debugSettings.load().then((_) => _recompute());
    _recompute();
  }

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static AdService _pickService() {
    return _isMobile ? AdmobAdService() : NoopAdService();
  }

  void _bind() {
    _entitlement.addListener(_recompute);
    _debugSettings.addListener(_recompute);
  }

  void _unbind() {
    _entitlement.removeListener(_recompute);
    _debugSettings.removeListener(_recompute);
  }

  void _recompute() {
    final now = DateTime.now();
    if (!_entitlement.hydrated) {
      // ignore: discarded_futures
      _hide();
      return;
    }
    final adFree = _entitlement.isAdFree(now);
    final enabled = _debugSettings.adsEnabled;
    final want = _isMobile && enabled && !adFree;
    if (!want) {
      // ignore: discarded_futures
      _hide();
      return;
    }
    // ignore: discarded_futures
    _show();
  }

  Future<void> _show() async {
    if (_banner != null || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      await _service.init();
      final w = await _service.loadFloatingBanner();
      _banner = w;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _hide() async {
    if (_banner == null && !_loading) return;
    _loading = false;
    _banner = null;
    notifyListeners();
    await _service.disposeFloatingBanner();
  }

  @override
  void dispose() {
    _unbind();
    // ignore: discarded_futures
    _service.disposeFloatingBanner();
    super.dispose();
  }
}

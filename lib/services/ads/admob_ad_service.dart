import 'admob_ad_service_stub.dart'
    if (dart.library.io) 'admob_ad_service_io.dart'
    if (dart.library.html) 'admob_ad_service_stub.dart';

import 'package:flutter/widgets.dart';

import 'ad_service.dart';

/// AdMob implementation (wrapped with conditional imports).
class AdmobAdService implements AdService {
  final AdService _impl = AdmobAdServiceImpl();

  @override
  Future<void> init() => _impl.init();

  @override
  Future<Widget?> loadFloatingBanner() => _impl.loadFloatingBanner();

  @override
  Future<void> disposeFloatingBanner() => _impl.disposeFloatingBanner();
}

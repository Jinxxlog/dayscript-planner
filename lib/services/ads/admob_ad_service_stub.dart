import 'package:flutter/widgets.dart';

import 'ad_service.dart';

/// Fallback used on unsupported platforms (web/desktop).
class AdmobAdServiceImpl implements AdService {
  @override
  Future<void> init() async {}

  @override
  Future<Widget?> loadFloatingBanner() async => null;

  @override
  Future<void> disposeFloatingBanner() async {}
}


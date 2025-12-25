import 'dart:io' if (dart.library.html) '../../platform_stub.dart' show Platform;

import 'package:flutter/foundation.dart';

class AdmobIds {
  AdmobIds._();

  /// Until you ship to production, keep this `true`.
  /// You can flip it per build:
  /// - `--dart-define=FORCE_TEST_ADS=false`
  static const bool forceTestAds =
      bool.fromEnvironment('FORCE_TEST_ADS', defaultValue: true);

  // Google-provided test unit IDs
  static const String _testAndroidBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testIosBanner =
      'ca-app-pub-3940256099942544/2934735716';

  // Live unit IDs (your AdMob)
  static const String _liveAndroidBanner =
      'ca-app-pub-9368851457077806/1052419644';

  static String bannerUnitId() {
    if (forceTestAds || !kReleaseMode) {
      if (Platform.isIOS) return _testIosBanner;
      return _testAndroidBanner;
    }
    return _liveAndroidBanner;
  }
}

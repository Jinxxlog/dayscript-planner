import 'package:flutter/widgets.dart';

abstract class AdService {
  Future<void> init();

  /// Returns the banner widget to render, or null when unavailable.
  Future<Widget?> loadFloatingBanner();

  Future<void> disposeFloatingBanner();
}


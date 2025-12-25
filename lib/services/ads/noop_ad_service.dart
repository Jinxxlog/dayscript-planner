import 'package:flutter/widgets.dart';

import 'ad_service.dart';

class NoopAdService implements AdService {
  @override
  Future<void> init() async {}

  @override
  Future<Widget?> loadFloatingBanner() async => null;

  @override
  Future<void> disposeFloatingBanner() async {}
}


import 'package:flutter/material.dart';

import 'ad_service.dart';

/// Placeholder implementation used until Google Mobile Ads SDK is integrated.
class MobilePlaceholderAdService implements AdService {
  bool _initialized = false;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<Widget?> loadFloatingBanner() async {
    if (!_initialized) await init();
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.12)),
      ),
      alignment: Alignment.center,
      child: const Text(
        'Ad',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Future<void> disposeFloatingBanner() async {}
}


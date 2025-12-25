import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';
import 'admob_ids.dart';

class AdmobAdServiceImpl implements AdService {
  bool _initialized = false;
  BannerAd? _bannerAd;
  Completer<void>? _loadCompleter;

  @override
  Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  @override
  Future<Widget?> loadFloatingBanner() async {
    final existing = _bannerAd;
    if (existing != null) {
      return Container(
        height: existing.size.height.toDouble(),
        alignment: Alignment.center,
        child: AdWidget(ad: existing),
      );
    }
    if (!_initialized) await init();

    _loadCompleter ??= Completer<void>();

    final unitId = AdmobIds.bannerUnitId();
    final ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _loadCompleter?.complete();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _loadCompleter?.completeError(error);
          _loadCompleter = null;
        },
      ),
    );

    _bannerAd = ad;
    ad.load();

    try {
      await _loadCompleter!.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }

    final w = Container(
      height: ad.size.height.toDouble(),
      alignment: Alignment.center,
      child: AdWidget(ad: ad),
    );

    return w;
  }

  @override
  Future<void> disposeFloatingBanner() async {
    _loadCompleter = null;
    final ad = _bannerAd;
    _bannerAd = null;
    await ad?.dispose();
  }
}

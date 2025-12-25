import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdsDebugSettingsProvider extends ChangeNotifier {
  static const _keyAdsEnabled = 'ads_debug_enabled';

  bool _loaded = false;
  bool _adsEnabled = true;

  bool get loaded => _loaded;
  bool get adsEnabled => _adsEnabled;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _adsEnabled = prefs.getBool(_keyAdsEnabled) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAdsEnabled(bool enabled) async {
    _adsEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdsEnabled, enabled);
  }
}


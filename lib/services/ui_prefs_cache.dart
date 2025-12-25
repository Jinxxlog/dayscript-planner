import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ui_prefs.dart';

class UiPrefsCache {
  static String _key(String uid) => 'ui_prefs__$uid';

  Future<UiPrefs?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      return UiPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String uid, UiPrefs prefsModel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), jsonEncode(prefsModel.toJson()));
  }

  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}

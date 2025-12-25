import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/entitlement.dart';

class EntitlementCache {
  static String _keyForUid(String uid) => 'entitlement_cache__$uid';

  Future<Entitlement?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForUid(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Entitlement.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String uid, Entitlement entitlement) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForUid(uid), jsonEncode(entitlement.toJson()));
  }

  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUid(uid));
  }
}


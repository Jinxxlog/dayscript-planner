import 'package:shared_preferences/shared_preferences.dart';
import 'local_scope.dart';

/// 동기화 메타데이터 저장소.
/// - lastSyncAt 을 SharedPreferences 에 저장/조회한다.
class SyncMetadataService {
  static const String _legacyLastSyncAtKey = 'lastSyncAt';
  static String get _lastSyncAtKey => LocalScope.lastSyncAtKey;

  static Future<DateTime?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readWithMigration(
        prefs, _lastSyncAtKey, _legacyLastSyncAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> setLastSyncAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncAtKey, value.toIso8601String());
  }

  static Future<void> clearLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncAtKey);
    await prefs.remove(_legacyLastSyncAtKey);
  }

  static Future<String?> _readWithMigration(
      SharedPreferences prefs, String scopedKey, String legacyKey) async {
    final scoped = prefs.getString(scopedKey);
    if (scoped != null) return scoped;

    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      await prefs.setString(scopedKey, legacy);
      await prefs.remove(legacyKey);
    }
    return legacy;
  }
}

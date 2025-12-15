import 'package:shared_preferences/shared_preferences.dart';

/// 동기화 메타데이터 저장소.
/// - lastSyncAt 을 SharedPreferences 에 저장/조회한다.
class SyncMetadataService {
  static const String _lastSyncAtKey = 'lastSyncAt';

  static Future<DateTime?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> setLastSyncAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncAtKey, value.toIso8601String());
  }

  static Future<void> clearLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncAtKey);
  }
}

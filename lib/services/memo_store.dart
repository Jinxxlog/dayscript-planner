import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_memo.dart';
import 'local_scope.dart';

/// SharedPreferences 기반 메모 저장/불러오기 헬퍼.
class CalendarMemoStore {
  static const String _legacyPrefsKey = 'calendar_memos';
  String get _prefsKey => LocalScope.calendarMemosKey;

  /// 날짜별 메모 맵 로드.
  Future<Map<String, List<CalendarMemo>>> loadByDate() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_prefsKey);
    if (jsonString == null) {
      jsonString = prefs.getString(_legacyPrefsKey);
      if (jsonString != null) {
        await prefs.setString(_prefsKey, jsonString);
        await prefs.remove(_legacyPrefsKey);
      }
    }
    if (jsonString == null) return {};
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return decoded.map((key, value) {
      final list = (value as List)
          .map((m) => CalendarMemo.fromJson(Map<String, dynamic>.from(m)))
          .map((m) => m.dateKey == null ? m.copyWith(dateKey: key) : m)
          .toList();
      return MapEntry(key, list);
    });
  }

  /// 날짜별 메모 맵 저장.
  Future<void> saveByDate(Map<String, List<CalendarMemo>> memos) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = memos.map((key, list) {
      return MapEntry(
        key,
        list.map((m) => m.copyWith(dateKey: m.dateKey ?? key).toJson()).toList(),
      );
    });
    await prefs.setString(_prefsKey, jsonEncode(jsonMap));
    await prefs.remove(_legacyPrefsKey);
  }

  /// 리스트를 날짜별로 묶어 저장.
  Future<void> saveFlat(List<CalendarMemo> list) async {
    final map = <String, List<CalendarMemo>>{};
    for (final m in list) {
      final key = m.dateKey ?? m.createdAt.toIso8601String().split('T').first;
      map.putIfAbsent(key, () => []);
      map[key]!.add(m.copyWith(dateKey: key));
    }
    await saveByDate(map);
  }
}

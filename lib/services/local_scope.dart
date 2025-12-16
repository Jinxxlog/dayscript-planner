import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Provides user-scoped identifiers for local storage (Hive boxes, prefs keys).
/// Falls back to `guest` when auth is unavailable.
class LocalScope {
  static String _uidOrGuest() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    } catch (e) {
      debugPrint('[LocalScope] Using guest scope: $e');
      return 'guest';
    }
  }

  static String boxName(String base) => '${base}__${_uidOrGuest()}';
  static String prefKey(String base) => '${base}__${_uidOrGuest()}';

  static String get weeklyMainBox => boxName('weekly_todos_main');
  static String get weeklyDialogBox => boxName('weekly_todos_dialog');
  static String get dailyTodosBox => boxName('planner_daily_todos_state_box');

  static String get calendarMemosKey => prefKey('calendar_memos');
  static String get memoPadKey => prefKey('memo');
  static String get todosKey => prefKey('todos');
  static String get todayTodosKey => prefKey('today_todos');
  static String get lastWeeklySyncDateKey =>
      prefKey('lastWeeklySyncDate');
  static String get lastSyncAtKey => prefKey('lastSyncAt');

  static String prefKeyWithBase(String base) => prefKey(base);
}

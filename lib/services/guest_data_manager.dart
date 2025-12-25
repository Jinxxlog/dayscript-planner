import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recurring_event.dart';

/// Utilities to detect and clear guest-scoped local data.
class GuestDataManager {
  static const _guestBoxes = [
    'weekly_todos_main__guest',
    'weekly_todos_dialog__guest',
    'planner_daily_todos_state_box__guest',
    'customHolidays__guest',
    'recurring_events__guest',
    'custom_holidays',
    'customHolidays',
  ];

  static const _guestPrefsKeys = [
    'calendar_memos__guest',
    'memo__guest',
    'memo_updated_at__guest',
    'todos__guest',
    'today_todos__guest',
    'lastWeeklySyncDate__guest',
    'lastSyncAt__guest',
    'last_date__guest',
  ];

  static bool _isMapBox(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('customholidays');
  }

  static bool _isRecurringBox(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('recurring_events');
  }

  static Future<Box> _openBoxSafe(String name) async {
    if (_isMapBox(name)) {
      if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
      return Hive.openBox<Map>(name);
    }
    if (_isRecurringBox(name)) {
      if (Hive.isBoxOpen(name)) return Hive.box<RecurringEvent>(name);
      return Hive.openBox<RecurringEvent>(name);
    }
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  /// Returns true if any known guest boxes or prefs contain data.
  static Future<bool> hasGuestData() async {
    for (final name in _guestBoxes) {
      if (await Hive.boxExists(name)) {
        final box = await _openBoxSafe(name);
        if (box.isNotEmpty) return true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in _guestPrefsKeys) {
      if (prefs.containsKey(key)) {
        final val = prefs.get(key);
        if (val != null) return true;
      }
    }
    return false;
  }

  /// Clears guest boxes and guest-scoped SharedPreferences keys.
  static Future<void> clearGuestData() async {
    for (final name in _guestBoxes) {
      if (await Hive.boxExists(name)) {
        try {
          if (Hive.isBoxOpen(name)) {
            final box = Hive.box(name);
            await box.clear();
            await box.close();
          }
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in _guestPrefsKeys) {
      await prefs.remove(key);
    }
  }
}

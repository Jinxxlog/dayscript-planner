import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recurring_event.dart';
import 'local_change_notifier.dart';
import 'local_scope.dart';

class LocalDataResetService {
  LocalDataResetService._();

  static const _legacyHiveBoxes = <String>[
    'weekly_todos_main',
    'weekly_todos_dialog',
    'planner_daily_todos_state_box',
    'customHolidays',
    'custom_holidays',
    'recurring_events',
  ];

  static const _legacyPrefsKeys = <String>[
    'calendar_memos',
    'memo',
    'memo_updated_at',
    'todos',
    'today_todos',
    'lastWeeklySyncDate',
    'lastSyncAt',
    'last_date',
  ];

  static Future<void> resetCurrentAccountData() async {
    await _ensureHiveInitialized();

    final boxes = <String>{
      LocalScope.weeklyMainBox,
      LocalScope.weeklyDialogBox,
      LocalScope.dailyTodosBox,
      LocalScope.customHolidaysBox,
      LocalScope.recurringEventsBox,
      ..._legacyHiveBoxes,
    };

    for (final name in boxes) {
      await _clearHiveBox(name);
    }

    final prefs = await SharedPreferences.getInstance();
    await _clearScopedPrefs(prefs);
    for (final key in _legacyPrefsKeys) {
      await _safeRemovePref(prefs, key);
    }

    LocalChangeNotifier.notify('todos');
    LocalChangeNotifier.notify('storage');
    LocalChangeNotifier.notify('memos');
    LocalChangeNotifier.notify('holidays');
    LocalChangeNotifier.notify('recurring');
    LocalChangeNotifier.notify('sync');
  }

  static Future<void> _ensureHiveInitialized() async {
    try {
      await Hive.initFlutter();
    } catch (_) {}
  }

  static Future<void> _clearHiveBox(String name) async {
    try {
      if (Hive.isBoxOpen(name)) {
        if (_isHolidayBoxName(name)) {
          await Hive.box<Map>(name).clear();
        } else if (_isRecurringBoxName(name)) {
          await Hive.box<RecurringEvent>(name).clear();
        } else {
          await Hive.box(name).clear();
        }
        return;
      }
      if (await Hive.boxExists(name)) {
        await Hive.deleteBoxFromDisk(name);
      }
    } catch (e) {
      debugPrint('[LocalDataResetService] Failed to clear Hive box $name: $e');
    }
  }

  static bool _isHolidayBoxName(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('customholidays') || lower.startsWith('custom_holidays');
  }

  static bool _isRecurringBoxName(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('recurring_events');
  }

  static Future<void> _clearScopedPrefs(SharedPreferences prefs) async {
    final suffix = _currentScopeSuffix();
    if (suffix.isEmpty) return;

    final keys = prefs.getKeys().where((k) => k.endsWith(suffix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static Future<void> _safeRemovePref(SharedPreferences prefs, String key) async {
    try {
      await prefs.remove(key);
    } catch (e) {
      debugPrint('[LocalDataResetService] Failed to remove pref $key: $e');
    }
  }

  static String _currentScopeSuffix() {
    final probe = LocalScope.prefKeyWithBase('scope_probe');
    final idx = probe.lastIndexOf('__');
    if (idx == -1) return '';
    return probe.substring(idx);
  }
}

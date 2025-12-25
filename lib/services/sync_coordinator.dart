import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weekly_todo.dart';
import '../models/calendar_memo.dart';
import '../models/recurring_event.dart';
import '../models/daily_todo_state.dart';
import '../models/memo_pad_doc.dart';
import '../services/holiday_service.dart';
import 'memo_store.dart';
import 'recurring_service.dart';
import 'todo_service.dart';
import 'firestore_sync_service.dart';
import 'merge_policy.dart';
import 'sync_metadata_service.dart';
import 'storage_service.dart';
import 'local_scope.dart';
import 'local_change_notifier.dart';
import 'local_data_reset_service.dart';

/// 동기 오케스트레이션: 네트워크 복귀/풀다운 새로고침 시 호출.
class SyncCoordinator {
  SyncCoordinator._internal();
  static final SyncCoordinator _instance = SyncCoordinator._internal();
  factory SyncCoordinator() => _instance;

  final _todoService = TodoService();
  final _holidayService = HolidayService();
  final _recurringService = RecurringService();
  final _memoStore = CalendarMemoStore();
  final _fs = FirestoreSyncService();

  bool _syncing = false;
  bool _applyingRemote = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<String>? _localSub;
  Timer? _debounce;
  Timer? _poller;
  bool _resyncRequested = false;
  Timer? _memoDebounce;
  bool _memoSyncing = false;
  bool _dirty = false;
  DateTime? _lastSyncAttemptAt;

  static const String _resetInProgressKey = 'reset_in_progress';

  Future<void> startNetworkListener() async {
    _ensureLocalListener();
    _connSub ??= Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection =
          results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _scheduleDebouncedSync(markDirty: false);
      }
    });

    // Periodic pull to reflect changes made on other devices while the app is open.
    _poller ??= Timer.periodic(const Duration(minutes: 2), (_) {
      // ignore: discarded_futures
      _scheduleDebouncedSync(markDirty: false);
    });
  }

  void _ensureLocalListener() {
    _localSub ??= LocalChangeNotifier.stream.listen((area) {
      // `syncAll()` applies remote merged data locally and emits LocalChangeNotifier
      // events (holidays/recurring/todos). Those should not trigger another sync.
      if (_applyingRemote) return;

      // Avoid running a full sync on every keystroke (memo pad writes a lot).
      if (area == 'storage') {
        _scheduleDebouncedMemoPadSync();
        return;
      }
      _scheduleDebouncedSync();
    });
  }

  void _scheduleDebouncedSync({bool markDirty = true}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    if (markDirty) _dirty = true;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      // ignore: discarded_futures
      syncAll();
    });
  }

  void _scheduleDebouncedMemoPadSync() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    if (_syncing) return; // full sync will cover memo pad too
    if (_memoSyncing) return;

    _memoDebounce?.cancel();
    _memoDebounce = Timer(const Duration(milliseconds: 1500), () {
      // ignore: discarded_futures
      _syncMemoPadOnly();
    });
  }

  Future<void> _syncMemoPadOnly() async {
    if (_memoSyncing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    _memoSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_resetInProgressKey) == true) return;

      await _fs.init(user.uid);
      final appliedReset = await _applyRemoteResetIfNeeded();
      if (appliedReset) return;

      final memoLocal = await _loadMemoPadLocal();
      final memoRemote = await _fs.fetchMemoPad();
      final merged = mergeMemoPad(
        local: memoLocal == null ? const [] : [memoLocal],
        remote: memoRemote == null ? const [] : [memoRemote],
      );
      if (merged.toUpload.isNotEmpty) {
        await _fs.upsertMemoPad(merged.toUpload.first);
      }
      await _replaceMemoPad(merged.merged.isEmpty ? null : merged.merged.first);
    } catch (e) {
      // ignore: avoid_print
      print('[SyncCoordinator] memoPad sync failed: $e');
    } finally {
      _memoSyncing = false;
    }
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _connSub = null;
    await _localSub?.cancel();
    _localSub = null;
    _debounce?.cancel();
    _debounce = null;
    _poller?.cancel();
    _poller = null;
    _memoDebounce?.cancel();
    _memoDebounce = null;
  }

  Future<bool> syncAll() async {
    if (_syncing) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final now = DateTime.now();
    final lastAttempt = _lastSyncAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 5) &&
        !_dirty) {
      return false;
    }
    _lastSyncAttemptAt = now;
    final wasDirty = _dirty;
    _dirty = false;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_resetInProgressKey) == true) {
      return false;
    }

    _syncing = true;
    try {
      await _fs.init(user.uid);

      final appliedReset = await _applyRemoteResetIfNeeded();
      if (appliedReset) return false;

      await _holidayService.init();
      await _recurringService.init();

      // 1) 로컬 로드
      // Weekly schedule lives in the dialog box (`weekly_todos_dialog__<uid>`).
      final List<WeeklyTodo> weeklyLocal =
          await _todoService.loadTodos(fromMain: false, includeDeleted: true);
      final memosByDate = await _memoStore.loadByDate();
      final List<CalendarMemo> memosLocal = memosByDate.entries
          .expand((e) =>
              e.value.map((m) => m.copyWith(dateKey: m.dateKey ?? e.key)))
          .toList();
      final List<CustomHoliday> holidaysLocal =
          await _holidayService.loadCustomHolidays(includeDeleted: true);
      final List<RecurringEvent> recurringLocal =
          _recurringService.getAllEvents(includeDeleted: true);

      final dailyStatesLocal = await _loadDailyTodoStatesLocal();
      final memoPadLocal = await _loadMemoPadLocal();

      // 2) 서버 fetch
      final weeklyRemote = await _fs.fetchWeeklyTodos();
      final memosRemote = await _fs.fetchMemos();
      final holidaysRemote = await _fs.fetchHolidays();
      final recurringRemote = await _fs.fetchRecurring();

      final dailyStatesRemote = await _fs.fetchDailyTodoStates();
      final memoPadRemote = await _fs.fetchMemoPad();

      // 3) 병합
      final weeklyMerged =
          mergeWeeklyTodos(local: weeklyLocal, remote: weeklyRemote);
      final memoMerged = mergeMemos(local: memosLocal, remote: memosRemote);
      final holidayMerged =
          mergeHolidays(local: holidaysLocal, remote: holidaysRemote);
      final recurringMerged =
          mergeRecurring(local: recurringLocal, remote: recurringRemote);

      final dailyMerged = mergeDailyTodoStates(
        local: dailyStatesLocal,
        remote: dailyStatesRemote,
      );
      final memoPadMerged = mergeMemoPad(
        local: memoPadLocal == null ? const [] : [memoPadLocal],
        remote: memoPadRemote == null ? const [] : [memoPadRemote],
      );

      final didUpload = weeklyMerged.toUpload.isNotEmpty ||
          memoMerged.toUpload.isNotEmpty ||
          holidayMerged.toUpload.isNotEmpty ||
          recurringMerged.toUpload.isNotEmpty ||
          dailyMerged.toUpload.isNotEmpty ||
          memoPadMerged.toUpload.isNotEmpty;
      final didApplyLocal = weeklyMerged.toApplyLocal.isNotEmpty ||
          memoMerged.toApplyLocal.isNotEmpty ||
          holidayMerged.toApplyLocal.isNotEmpty ||
          recurringMerged.toApplyLocal.isNotEmpty ||
          dailyMerged.toApplyLocal.isNotEmpty ||
          memoPadMerged.toApplyLocal.isNotEmpty;
      final didWork = didUpload || didApplyLocal;

      if (kDebugMode && (didWork || wasDirty)) {
        // ignore: avoid_print
        print(
          '[SyncCoordinator] syncAll start uid=${user.uid} anon=${user.isAnonymous}',
        );
        // ignore: avoid_print
        print(
          '[SyncCoordinator] local counts weekly=${weeklyLocal.length} memos=${memosLocal.length} holidays=${holidaysLocal.length} recurring=${recurringLocal.length} dailyStates=${dailyStatesLocal.length} memoPad=${memoPadLocal == null ? 0 : 1}',
        );
        // ignore: avoid_print
        print(
          '[SyncCoordinator] remote counts weekly=${weeklyRemote.length} memos=${memosRemote.length} holidays=${holidaysRemote.length} recurring=${recurringRemote.length} dailyStates=${dailyStatesRemote.length} memoPad=${memoPadRemote == null ? 0 : 1}',
        );
        // ignore: avoid_print
        print(
          '[SyncCoordinator] toUpload weekly=${weeklyMerged.toUpload.length} memos=${memoMerged.toUpload.length} holidays=${holidayMerged.toUpload.length} recurring=${recurringMerged.toUpload.length} dailyStates=${dailyMerged.toUpload.length} memoPad=${memoPadMerged.toUpload.length}',
        );
      }

      // 4) 서버 업로드 (로컬이 더 최신)
      if (weeklyMerged.toUpload.isNotEmpty) {
        await _fs.upsertWeeklyTodos(weeklyMerged.toUpload);
      }
      if (memoMerged.toUpload.isNotEmpty) {
        await _fs.upsertMemos(memoMerged.toUpload);
      }
      if (holidayMerged.toUpload.isNotEmpty) {
        await _fs.upsertHolidays(holidayMerged.toUpload);
      }
      if (recurringMerged.toUpload.isNotEmpty) {
        await _fs.upsertRecurring(recurringMerged.toUpload);
      }
      if (dailyMerged.toUpload.isNotEmpty) {
        await _fs.upsertDailyTodoStates(dailyMerged.toUpload);
      }
      if (memoPadMerged.toUpload.isNotEmpty) {
        await _fs.upsertMemoPad(memoPadMerged.toUpload.first);
      }

      // 5) 로컬 갱신 (병합 결과 전체 저장)
      _applyingRemote = true;
      try {
        if (weeklyMerged.toApplyLocal.isNotEmpty) {
          await _todoService.saveTodos(
            weeklyMerged.merged,
            fromMain: false,
            touchUpdatedAt: false,
          );
        }
        if (memoMerged.toApplyLocal.isNotEmpty) {
          await _memoStore.saveFlat(memoMerged.merged);
        }
        if (holidayMerged.toApplyLocal.isNotEmpty) {
          await _replaceHolidays(holidayMerged.merged);
        }
        if (recurringMerged.toApplyLocal.isNotEmpty) {
          await _replaceRecurring(recurringMerged.merged);
        }
        if (dailyMerged.toApplyLocal.isNotEmpty) {
          await _applyDailyTodoStates(dailyMerged.toApplyLocal);
        }
        if (memoPadMerged.toApplyLocal.isNotEmpty) {
          await _replaceMemoPad(
            memoPadMerged.merged.isEmpty ? null : memoPadMerged.merged.first,
          );
        }
      } finally {
        _applyingRemote = false;
      }

      // 6) lastSyncAt 갱신
      await SyncMetadataService.setLastSyncAt(DateTime.now().toUtc());
      if (kDebugMode && (didWork || wasDirty)) {
        // ignore: avoid_print
        print('[SyncCoordinator] syncAll done');
      }

      return true;
    } catch (e) {
      // TODO: 로깅/재시도 큐 연결
      // Keep existing behavior, but make it visible in debug logs.
      // ignore: avoid_print
      print('[SyncCoordinator] syncAll failed: $e');
      _dirty = true;
      return false;
    } finally {
      _syncing = false;
      if (_resyncRequested) {
        _resyncRequested = false;
        _scheduleDebouncedSync(markDirty: true);
      }
    }
  }

  Future<void> _replaceHolidays(List<CustomHoliday> holidays) async {
    final box = await Hive.openBox<Map>(LocalScope.customHolidaysBox);
    await box.clear();
    for (final h in holidays) {
      await box.put(h.date.toIso8601String(), h.toJson());
    }
    LocalChangeNotifier.notify('holidays');
  }

  Future<void> _replaceRecurring(List<RecurringEvent> events) async {
    // 초기화되어 있으므로 어댑터 등록 완료
    final box =
        await Hive.openBox<RecurringEvent>(RecurringService.boxName);
    await box.clear();
    for (final e in events) {
      await box.add(e);
    }
    LocalChangeNotifier.notify('recurring');
  }

  Future<List<DailyTodoState>> _loadDailyTodoStatesLocal() async {
    final map = await _todoService.loadAllDailyStates();
    final out = <DailyTodoState>[];
    for (final entry in map.entries) {
      out.add(DailyTodoState(dateKey: entry.key, items: entry.value));
    }
    return out;
  }

  Future<MemoPadDoc?> _loadMemoPadLocal() async {
    final text = await StorageService.loadMemo();
    if (text == null) return null;
    final ts = await StorageService.loadMemoUpdatedAt();
    return MemoPadDoc(text: text, updatedAt: ts);
  }

  Future<void> _replaceDailyTodoStates(List<DailyTodoState> states) async {
    // Prefer replacing the whole box to keep ordering deterministic per day.
    await _todoService.clearDailyStates();
    for (final s in states) {
      if (s.deleted) continue;
      await _todoService.saveDailyStateByKey(
        s.dateKey,
        s.items,
        touchUpdatedAt: false,
      );
    }
  }

  Future<void> _applyDailyTodoStates(List<DailyTodoState> states) async {
    if (states.isEmpty) return;
    for (final s in states) {
      if (s.deleted) {
        await _todoService.deleteDailyStateByKey(s.dateKey);
        continue;
      }
      await _todoService.saveDailyStateByKey(
        s.dateKey,
        s.items,
        touchUpdatedAt: false,
      );
    }
  }

  Future<void> _replaceMemoPad(MemoPadDoc? doc) async {
    if (doc == null) return;
    if (doc.deleted) {
      await StorageService.saveMemo('', updatedAt: doc.updatedAt);
      return;
    }
    final existing = await StorageService.loadMemo();
    final existingTs = await StorageService.loadMemoUpdatedAt();
    if (existing == doc.text && existingTs?.toUtc() == doc.updatedAt.toUtc()) {
      return;
    }
    await StorageService.saveMemo(doc.text, updatedAt: doc.updatedAt);
  }

  Future<bool> _applyRemoteResetIfNeeded() async {
    final remoteResetAt = await _fs.fetchResetAt();
    if (remoteResetAt == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final localKey = LocalScope.prefKeyWithBase('reset_at');
    final localRaw = prefs.getString(localKey);
    final localResetAt = localRaw == null ? null : DateTime.tryParse(localRaw);

    if (localResetAt != null && !remoteResetAt.isAfter(localResetAt)) {
      return false;
    }

    await prefs.setBool(_resetInProgressKey, true);
    try {
      await LocalDataResetService.resetCurrentAccountData();
      final prefsAfter = await SharedPreferences.getInstance();
      await prefsAfter.setString(
        localKey,
        remoteResetAt.toUtc().toIso8601String(),
      );
    } finally {
      final prefsAfter = await SharedPreferences.getInstance();
      await prefsAfter.setBool(_resetInProgressKey, false);
    }

    return true;
  }
}

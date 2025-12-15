import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/weekly_todo.dart';
import '../models/calendar_memo.dart';
import '../models/recurring_event.dart';
import '../services/holiday_service.dart';
import 'memo_store.dart';
import 'recurring_service.dart';
import 'todo_service.dart';
import 'firestore_sync_service.dart';
import 'merge_policy.dart';
import 'sync_metadata_service.dart';

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
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  Future<void> startNetworkListener() async {
    _connSub ??= Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection =
          results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        syncAll();
      }
    });
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _connSub = null;
  }

  Future<bool> syncAll() async {
    if (_syncing) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    _syncing = true;
    try {
      await _fs.init(user.uid);
      await _holidayService.init();
      await _recurringService.init();

      // 1) 로컬 로드
      final List<WeeklyTodo> weeklyLocal =
          await _todoService.loadTodos(fromMain: true);
      final memosByDate = await _memoStore.loadByDate();
      final List<CalendarMemo> memosLocal = memosByDate.entries
          .expand((e) =>
              e.value.map((m) => m.copyWith(dateKey: m.dateKey ?? e.key)))
          .toList();
      final List<CustomHoliday> holidaysLocal =
          await _holidayService.loadCustomHolidays();
      final List<RecurringEvent> recurringLocal =
          _recurringService.getEvents();

      // 2) 서버 fetch
      final weeklyRemote = await _fs.fetchWeeklyTodos();
      final memosRemote = await _fs.fetchMemos();
      final holidaysRemote = await _fs.fetchHolidays();
      final recurringRemote = await _fs.fetchRecurring();

      // 3) 병합
      final weeklyMerged =
          mergeWeeklyTodos(local: weeklyLocal, remote: weeklyRemote);
      final memoMerged = mergeMemos(local: memosLocal, remote: memosRemote);
      final holidayMerged =
          mergeHolidays(local: holidaysLocal, remote: holidaysRemote);
      final recurringMerged =
          mergeRecurring(local: recurringLocal, remote: recurringRemote);

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

      // 5) 로컬 갱신 (병합 결과 전체 저장)
      await _todoService.saveTodos(weeklyMerged.merged, fromMain: true);
      await _memoStore.saveFlat(memoMerged.merged);
      await _replaceHolidays(holidayMerged.merged);
      await _replaceRecurring(recurringMerged.merged);

      // 6) lastSyncAt 갱신
      await SyncMetadataService.setLastSyncAt(DateTime.now().toUtc());

      return true;
    } catch (e) {
      // TODO: 로깅/재시도 큐 연결
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _replaceHolidays(List<CustomHoliday> holidays) async {
    final box = await Hive.openBox<Map>('customHolidays');
    await box.clear();
    for (final h in holidays) {
      await box.put(h.date.toIso8601String(), h.toJson());
    }
  }

  Future<void> _replaceRecurring(List<RecurringEvent> events) async {
    // 초기화되어 있으므로 어댑터 등록 완료
    final box =
        await Hive.openBox<RecurringEvent>(RecurringService.boxName);
    await box.clear();
    for (final e in events) {
      await box.add(e);
    }
  }
}

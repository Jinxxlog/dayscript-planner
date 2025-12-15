import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/todo.dart';
import '../models/weekly_todo.dart';
import '../models/calendar_memo.dart';
import '../models/recurring_event.dart';
import '../services/holiday_service.dart';
import 'merge_policy.dart';

/// Firestore CRUD + 오프라인 캐시 활성화.
class FirestoreSyncService {
  FirestoreSyncService._internal();
  static final FirestoreSyncService _instance = FirestoreSyncService._internal();
  factory FirestoreSyncService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _initialized = false;
  String? _uid;

  Future<void> init(String uid) async {
    _uid = uid;
    if (!_initialized) {
      _db.settings = const Settings(persistenceEnabled: true);
      _initialized = true;
    }
  }

  void _ensure() {
    if (!_initialized || _uid == null) {
      throw Exception('FirestoreSyncService not initialized. Call init(uid).');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _encodeDates(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is DateTime) {
        out[key] = Timestamp.fromDate(value);
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  Map<String, dynamic> _decodeDates(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is Timestamp) {
        out[key] = value.toDate();
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  // ---------------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> _col(String name) {
    _ensure();
    return _db.collection('users').doc(_uid).collection(name);
  }

  // ---------------------------------------------------------------------------
  // Todos
  // ---------------------------------------------------------------------------
  Future<List<Todo>> fetchTodos() async {
    final snap = await _col('todos').get();
    return snap.docs
        .map((d) => Todo.fromJson(_decodeDates(d.data())))
        .toList();
  }

  Future<void> upsertTodos(List<Todo> todos) async {
    final batch = _db.batch();
    for (final t in todos) {
      final doc = _col('todos').doc(t.id);
      batch.set(doc, _encodeDates(t.toJson()), SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // WeeklyTodos
  // ---------------------------------------------------------------------------
  Future<List<WeeklyTodo>> fetchWeeklyTodos() async {
    final snap = await _col('weeklyTodos').get();
    return snap.docs
        .map((d) => WeeklyTodo.fromJson(_decodeDates(d.data())))
        .toList();
  }

  Future<void> upsertWeeklyTodos(List<WeeklyTodo> todos) async {
    final batch = _db.batch();
    for (final t in todos) {
      final doc = _col('weeklyTodos').doc(t.id);
      batch.set(doc, _encodeDates(t.toJson()), SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Memos
  // ---------------------------------------------------------------------------
  Future<List<CalendarMemo>> fetchMemos() async {
    final snap = await _col('memos').get();
    return snap.docs
        .map((d) => CalendarMemo.fromJson(_decodeDates(d.data())))
        .toList();
  }

  Future<void> upsertMemos(List<CalendarMemo> memos) async {
    final batch = _db.batch();
    for (final m in memos) {
      final doc = _col('memos').doc(m.id);
      batch.set(doc, _encodeDates(m.toJson()), SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Holidays (custom)
  // ---------------------------------------------------------------------------
  Future<List<CustomHoliday>> fetchHolidays() async {
    final snap = await _col('holidays').get();
    return snap.docs
        .map((d) => CustomHoliday.fromJson(_decodeDates(d.data())))
        .toList();
  }

  Future<void> upsertHolidays(List<CustomHoliday> holidays) async {
    final batch = _db.batch();
    for (final h in holidays) {
      // 날짜를 doc id로 사용
      final doc = _col('holidays').doc(h.date.toIso8601String());
      batch.set(doc, _encodeDates(h.toJson()), SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Recurring
  // ---------------------------------------------------------------------------
  String _recurringId(RecurringEvent e) {
    if (e.id != null && e.id!.isNotEmpty) return e.id!;
    final ym = e.yearMonth ?? 0;
    final yd = e.yearDay ?? 0;
    final rule = e.rule ?? '';
    return '${e.title}__${e.cycleType.name}__${ym}_${yd}__${rule.isEmpty ? e.startDate.toIso8601String() : rule}';
  }

  Future<List<RecurringEvent>> fetchRecurring() async {
    final snap = await _col('recurring').get();
    return snap.docs
        .map((d) => RecurringEvent.fromJson(_decodeDates(d.data())))
        .toList();
  }

  Future<void> upsertRecurring(List<RecurringEvent> events) async {
    final batch = _db.batch();
    for (final e in events) {
      final doc = _col('recurring').doc(_recurringId(e));
      batch.set(doc, _encodeDates(e.toJson()), SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // 병합 엔트리 포인트 (선택적으로 사용)
  // ---------------------------------------------------------------------------
  Future<void> syncTodos(List<Todo> local) async {
    final remote = await fetchTodos();
    final merged = mergeTodos(local: local, remote: remote);
    if (merged.toUpload.isNotEmpty) await upsertTodos(merged.toUpload);
  }

  Future<void> syncWeeklyTodos(List<WeeklyTodo> local) async {
    final remote = await fetchWeeklyTodos();
    final merged = mergeWeeklyTodos(local: local, remote: remote);
    if (merged.toUpload.isNotEmpty) await upsertWeeklyTodos(merged.toUpload);
  }

  Future<void> syncMemos(List<CalendarMemo> local) async {
    final remote = await fetchMemos();
    final merged = mergeMemos(local: local, remote: remote);
    if (merged.toUpload.isNotEmpty) await upsertMemos(merged.toUpload);
  }

  Future<void> syncHolidays(List<CustomHoliday> local) async {
    final remote = await fetchHolidays();
    final merged = mergeHolidays(local: local, remote: remote);
    if (merged.toUpload.isNotEmpty) await upsertHolidays(merged.toUpload);
  }

  Future<void> syncRecurring(List<RecurringEvent> local) async {
    final remote = await fetchRecurring();
    final merged = mergeRecurring(local: local, remote: remote);
    if (merged.toUpload.isNotEmpty) await upsertRecurring(merged.toUpload);
  }
}

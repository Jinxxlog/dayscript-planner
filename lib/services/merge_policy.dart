import '../models/todo.dart';
import '../models/weekly_todo.dart';
import '../models/calendar_memo.dart';
import '../services/holiday_service.dart';
import '../models/recurring_event.dart';
import '../models/daily_todo_state.dart';
import '../models/memo_pad_doc.dart';

/// 병합 결과: 최종 merged, 로컬이 서버에 업로드해야 할 항목, 서버에서 로컬에 반영해야 할 항목.
class MergeResult<T> {
  final List<T> merged;
  final List<T> toUpload; // 로컬이 더 최신 → 서버로 올리기
  final List<T> toApplyLocal; // 서버가 더 최신 → 로컬에 반영

  MergeResult({
    required this.merged,
    required this.toUpload,
    required this.toApplyLocal,
  });
}

DateTime _ts(DateTime? v) => v ?? DateTime.fromMillisecondsSinceEpoch(0);

MergeResult<T> _mergeGeneric<T>({
  required List<T> local,
  required List<T> remote,
  required String Function(T) id,
  required DateTime? Function(T) updatedAt,
  required bool Function(T) deleted,
}) {
  final Map<String, T> localMap = {for (final e in local) id(e): e};
  final Map<String, T> remoteMap = {for (final e in remote) id(e): e};
  final keys = {...localMap.keys, ...remoteMap.keys};

  final merged = <T>[];
  final toUpload = <T>[];
  final toApplyLocal = <T>[];

  for (final k in keys) {
    final l = localMap[k];
    final r = remoteMap[k];

    if (l != null && r != null) {
      final lDel = deleted(l);
      final rDel = deleted(r);

      // 삭제 우선
      if (rDel) {
        merged.add(r);
        if (!lDel) toApplyLocal.add(r);
        continue;
      }
      if (lDel && !rDel) {
        merged.add(l);
        toUpload.add(l);
        continue;
      }

      // 둘 다 삭제 아님 → LWW
      final lTs = _ts(updatedAt(l));
      final rTs = _ts(updatedAt(r));
      if (rTs.isAfter(lTs)) {
        merged.add(r);
        toApplyLocal.add(r);
      } else if (lTs.isAfter(rTs)) {
        merged.add(l);
        toUpload.add(l);
      } else {
        // 동시간 → 서버 우선
        merged.add(r);
      }
    } else if (r != null) {
      merged.add(r);
      toApplyLocal.add(r);
    } else if (l != null) {
      merged.add(l);
      toUpload.add(l);
    }
  }

  return MergeResult(merged: merged, toUpload: toUpload, toApplyLocal: toApplyLocal);
}

// -----------------------------------------------------------------------------
// 엔티티별 병합 어댑터
// -----------------------------------------------------------------------------

MergeResult<Todo> mergeTodos({
  required List<Todo> local,
  required List<Todo> remote,
}) {
  return _mergeGeneric<Todo>(
    local: local,
    remote: remote,
    id: (t) => t.id,
    updatedAt: (t) => t.updatedAt,
    deleted: (t) => t.deleted,
  );
}

MergeResult<WeeklyTodo> mergeWeeklyTodos({
  required List<WeeklyTodo> local,
  required List<WeeklyTodo> remote,
}) {
  return _mergeGeneric<WeeklyTodo>(
    local: local,
    remote: remote,
    id: (t) => t.id,
    updatedAt: (t) => t.updatedAt,
    deleted: (t) => t.deleted,
  );
}

MergeResult<CalendarMemo> mergeMemos({
  required List<CalendarMemo> local,
  required List<CalendarMemo> remote,
}) {
  return _mergeGeneric<CalendarMemo>(
    local: local,
    remote: remote,
    id: (m) => m.id,
    updatedAt: (m) => m.updatedAt,
    deleted: (m) => m.deleted,
  );
}

/// CustomHoliday 는 id 대신 날짜를 키로 사용(동일 날짜 중복 허용 시 서버 우선 병합).
MergeResult<CustomHoliday> mergeHolidays({
  required List<CustomHoliday> local,
  required List<CustomHoliday> remote,
}) {
  String key(CustomHoliday h) => h.date.toIso8601String();
  return _mergeGeneric<CustomHoliday>(
    local: local,
    remote: remote,
    id: key,
    updatedAt: (h) => h.updatedAt,
    deleted: (h) => h.deleted,
  );
}

/// RecurringEvent 는 id 없을 수도 있어 surrogate 키 사용.
String _recurringKey(RecurringEvent e) {
  if (e.id != null && e.id!.isNotEmpty) return e.id!;
  final ym = e.yearMonth ?? 0;
  final yd = e.yearDay ?? 0;
  final rule = e.rule ?? '';
  return '${e.title}__${e.cycleType.name}__${ym}_${yd}__${rule.isEmpty ? e.startDate.toIso8601String() : rule}';
}

MergeResult<RecurringEvent> mergeRecurring({
  required List<RecurringEvent> local,
  required List<RecurringEvent> remote,
}) {
  return _mergeGeneric<RecurringEvent>(
    local: local,
    remote: remote,
    id: _recurringKey,
    updatedAt: (e) => e.updatedAt,
    deleted: (e) => e.deleted,
  );
}

MergeResult<DailyTodoState> mergeDailyTodoStates({
  required List<DailyTodoState> local,
  required List<DailyTodoState> remote,
}) {
  return _mergeGeneric<DailyTodoState>(
    local: local,
    remote: remote,
    id: (s) => s.dateKey,
    updatedAt: (s) => s.updatedAt,
    deleted: (s) => s.deleted,
  );
}

MergeResult<MemoPadDoc> mergeMemoPad({
  required List<MemoPadDoc> local,
  required List<MemoPadDoc> remote,
}) {
  return _mergeGeneric<MemoPadDoc>(
    local: local,
    remote: remote,
    id: (m) => m.id,
    updatedAt: (m) => m.updatedAt,
    deleted: (m) => m.deleted,
  );
}

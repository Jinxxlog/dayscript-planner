import 'package:hive_flutter/hive_flutter.dart';
import '../models/weekly_todo.dart';
import '../models/todo.dart';
import 'local_scope.dart';
import 'dart:convert'; // ✅ jsonEncode / jsonDecode 사용을 위해 필요
import 'local_change_notifier.dart';

class TodoService {
  static final Map<String, Future<Box>> _openingBoxes = {};
  static final Map<String, Future<void>> _migratingLegacy = {};

  static const String _legacyMainBoxName = 'weekly_todos_main';
  static const String _legacyDialogBoxName = 'weekly_todos_dialog';
  static const String _legacyDailyBoxName = 'planner_daily_todos_state_box';

  String get _mainBoxName => LocalScope.weeklyMainBox;
  String get _dialogBoxName => LocalScope.weeklyDialogBox;
  String get _dailyBoxName => LocalScope.dailyTodosBox;

  Future<Box> _openBoxByName(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    final existing = _openingBoxes[name];
    if (existing != null) return await existing;
    final future = Hive.openBox(name);
    _openingBoxes[name] = future;
    try {
      return await future;
    } finally {
      _openingBoxes.remove(name);
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 공통 초기화

  Future<void> clearAllTodos() async {
    await clearAll(fromMain: true);
    await clearAll(fromMain: false);
    await clearDailyStates(); // ✅ 날짜별 상태도 초기화
    LocalChangeNotifier.notify('todos');
  }

  Future<Box> _openBox({bool fromMain = false}) async {
    final name = fromMain ? _mainBoxName : _dialogBoxName;
    // ✅ 제네릭 제거
    final box = await _openBoxByName(name);
    await _migrateLegacyBox(
      targetBox: box,
      legacyName: fromMain ? _legacyMainBoxName : _legacyDialogBoxName,
    );
    return box;
  }


  Future<Box> _openDailyBox() async {
    // 이미 열려있으면 바로 반환 (중복 open 방지)
    final box = await _openBoxByName(_dailyBoxName);
    await _migrateLegacyBox(
      targetBox: box,
      legacyName: _legacyDailyBoxName,
    );
    return box;
  }

  // ─────────────────────────────────────────────
  // ✅ WeeklyTodo 관리창용

  Future<List<WeeklyTodo>> loadTodos({
    bool fromMain = false,
    bool includeDeleted = false,
  }) async {
    final box = await _openBox(fromMain: fromMain);
    final raw = box.get('todos', defaultValue: <WeeklyTodo>[]);
    final out = <WeeklyTodo>[];
    for (final e in (raw as List)) {
      final WeeklyTodo w;
      if (e is WeeklyTodo) {
        w = e.copy();
      } else if (e is Map) {
        w = WeeklyTodo.fromJson(Map<String, dynamic>.from(e));
      } else {
        throw Exception('Invalid WeeklyTodo: $e');
      }
      if (!includeDeleted && w.deleted) continue;
      out.add(w);
    }
    return out;
  }

  Future<void> saveTodos(
    List<WeeklyTodo> todos, {
    bool fromMain = false,
    bool touchUpdatedAt = true,
  }) async {
    final box = await _openBox(fromMain: fromMain);
    if (touchUpdatedAt) {
      final now = DateTime.now().toUtc();
      for (final t in todos) {
        t.updatedAt = now;
      }
    }
    await box.put('todos', todos);
    LocalChangeNotifier.notify('todos');
  }

  Future<void> addTodo(
    String title,
    List<int> days, {
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    String? textTime,
    bool fromMain = false,
    String? color,
  }) async {
    final box = await _openBox(fromMain: fromMain);
    final current = List<WeeklyTodo>.from(box.get('todos', defaultValue: []));

    final todo = WeeklyTodo(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      days: days,
      startTime: startTime,
      endTime: endTime,
      textTime: textTime,
      color: (color?.trim().isEmpty ?? true) ? "#64B5F6" : color!.trim(), // ✅ 수정
    );

    current.add(todo);
    await box.put('todos', current);
    LocalChangeNotifier.notify('todos');
  }


  // ─────────────────────────────────────────────
  // ✅ 모든 요일의 투두를 한 번에 동기화 (Flutter 호환 완전판)
  Future<void> syncAllFromDialog({bool forceRefresh = false}) async {
    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
    if (dialogTodos.isEmpty) {
      print("📭 WeeklyTodoDialog 비어 있음 (syncAllFromDialog)");
      return;
    }

    final dailyBox = await _openDailyBox();
    if (forceRefresh) {
      await dailyBox.clear();
      LocalChangeNotifier.notify('todos');
      return;
    }
    final weeklyById = <String, WeeklyTodo>{};
    for (final w in dialogTodos) {
      weeklyById[w.id] = w;
    }

    bool changedAny = false;
    for (final rawKey in dailyBox.keys) {
      final key = rawKey.toString();
      final date = _tryParseDateKey(key);
      if (date == null) continue;
      final existingTodos = _decodeDailyTodos(dailyBox.get(key));
      final merged = _mergeDailyWithWeekly(date, existingTodos, weeklyById);
      if (!merged.changed) continue;
      changedAny = true;
      await dailyBox.put(
        key,
        jsonEncode(merged.todos.map((t) => t.toJson()).toList()),
      );
    }

    if (changedAny) {
      LocalChangeNotifier.notify('todos');
    }
    return;

    /*

    final weeklyById = <String, WeeklyTodo>{};
    for (final w in dialogTodos) {
      weeklyById[w.id] = w;
    }

    bool changedAny = false;
    for (final rawKey in dailyBox.keys) {
      final key = rawKey.toString();
      final date = _tryParseDateKey(key);
      if (date == null) continue;
      if (!daysToUpdate.contains(date.weekday)) continue;

      final existingTodos = _decodeDailyTodos(dailyBox.get(key));
      final merged = _mergeDailyWithWeekly(date, existingTodos, weeklyById);
      if (!merged.changed) continue;
      changedAny = true;
      await dailyBox.put(
        key,
        jsonEncode(merged.todos.map((t) => t.toJson()).toList()),
      );
    }

    if (changedAny) {
      LocalChangeNotifier.notify('todos');
    }
    return;

    final now = DateTime.now();

    // ✅ 강제 새로고침 모드면 모든 DailyBox 초기화
    if (forceRefresh) {
      print("🌀 강제 새로고침: DailyBox 전체 초기화 중...");
      await dailyBox.clear();
      LocalChangeNotifier.notify('todos');
      return;
    }

    // 🔹 일주일 전~후 7일 포함
    final weeklyById = <String, WeeklyTodo>{};
    for (final w in dialogTodos) {
      weeklyById[w.id] = w;
    }

    bool changedAny = false;
    for (final rawKey in dailyBox.keys) {
      final key = rawKey.toString();
      final date = _tryParseDateKey(key);
      if (date == null) continue;

      final existingTodos = _decodeDailyTodos(dailyBox.get(key));
      final merged = _mergeDailyWithWeekly(date, existingTodos, weeklyById);
      if (!merged.changed) continue;
      changedAny = true;
      await dailyBox.put(
        key,
        jsonEncode(merged.todos.map((t) => t.toJson()).toList()),
      );
    }

    if (changedAny) {
      LocalChangeNotifier.notify('todos');
    }
    return;

    for (int offset = -365; offset <= 365; offset++) {
      final date = now.add(Duration(days: offset));
      final weekday = date.weekday;
      final key = _dateKey(date);

      final existingData = dailyBox.get(key);
      final List<Todo> existingTodos = existingData == null
          ? []
          : List<Todo>.from(
              (jsonDecode(existingData) as List)
                  .map((e) => Todo.fromJson(Map<String, dynamic>.from(e))));

      // ✅ 이번 요일에 해당하는 주간 투두만 추출
      final weeklyForDay = dialogTodos
          .where((t) => t.deleted != true && t.days.contains(weekday))
          .toList();

      // ✅ 병합 로직
      final updated = <Todo>[...existingTodos];

      // 🔸 새로 추가된 항목 병합
      for (final w in weeklyForDay) {
        final exists = updated.any((t) => t.id == w.id);
        if (!exists) {
          updated.add(Todo(
            w.id,
            w.title,
            isDone: false,
            dueTime: w.startTime,
            textTime: w.textTime,
            color: w.color,
          ));
        }
      }

      // 🔸 WeeklyTodo에 없는 항목 제거
      updated.removeWhere((t) => !weeklyForDay.any((w) => w.id == t.id));

      await dailyBox.put(key, jsonEncode(updated.map((t) => t.toJson()).toList()));
    }

    print("✅ WeeklyTodo → DailyBox 완전 병합 동기화 완료 (${forceRefresh ? '강제 초기화 포함' : '일반'})");
  */
  }

  Future<void> syncSpecificDays(List<int> daysToUpdate) async {
    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
    if (dialogTodos.isEmpty) return;

    final dailyBox = await _openDailyBox();

    final weeklyById = <String, WeeklyTodo>{};
    for (final w in dialogTodos) {
      weeklyById[w.id] = w;
    }

    bool changedAny = false;
    for (final rawKey in dailyBox.keys) {
      final key = rawKey.toString();
      final date = _tryParseDateKey(key);
      if (date == null) continue;
      if (!daysToUpdate.contains(date.weekday)) continue;

      final existingTodos = _decodeDailyTodos(dailyBox.get(key));
      final merged = _mergeDailyWithWeekly(date, existingTodos, weeklyById);
      if (!merged.changed) continue;
      changedAny = true;
      await dailyBox.put(
        key,
        jsonEncode(merged.todos.map((t) => t.toJson()).toList()),
      );
    }

    if (changedAny) {
      LocalChangeNotifier.notify('todos');
    }
    return;

    /*
    final now = DateTime.now();

    for (int offset = -365; offset <= 365; offset++) {
      final date = now.add(Duration(days: offset));
      if (!daysToUpdate.contains(date.weekday)) continue; // ✅ 선택된 요일만 갱신

      final key = _dateKey(date);
      final existingData = dailyBox.get(key);
      final List<Todo> existingTodos = existingData == null
          ? []
          : List<Todo>.from(
              (jsonDecode(existingData) as List)
                  .map((e) => Todo.fromJson(Map<String, dynamic>.from(e))));

      final weeklyForDay = dialogTodos
          .where((t) => t.deleted != true && t.days.contains(date.weekday))
          .toList();

      // ✅ 기존 유지 + 추가/삭제 병합
      final updated = <Todo>[...existingTodos];

      // 새로 추가된 항목 병합
      for (final w in weeklyForDay) {
        final exists = updated.any((t) => t.id == w.id);
        if (!exists) {
          updated.add(Todo(
            w.id,
            w.title,
            isDone: false,
            dueTime: w.startTime,
            textTime: w.textTime,
            color: (w.color?.isNotEmpty ?? false) ? w.color : "#64B5F6", // ✅ 수정
          ));
        }
      }

      // WeeklyTodo에 없는 항목 제거
      updated.removeWhere((t) => !weeklyForDay.any((w) => w.id == t.id));

      await dailyBox.put(key, jsonEncode(updated.map((t) => t.toJson()).toList()));
    }

    print("✅ 선택된 요일만 부분 동기화 완료: $daysToUpdate");
  */
  }

  Future<void> refreshColorsFromDialog() async {
    await syncAllFromDialog();
    return;

    final dialogBox = await _openBox(fromMain: false);
    final dialogTodosRaw =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
    final dialogTodos = dialogTodosRaw.where((w) => w.deleted != true).toList();
    if (dialogTodos.isEmpty) return;

    final dailyBox = await _openDailyBox();
    final now = DateTime.now();

    // 🔹 2주 범위 (지난 7일~앞으로 7일)
    for (int offset = -365; offset <= 365; offset++) {
      final date = now.add(Duration(days: offset));
      final key = _dateKey(date);
      final existingData = dailyBox.get(key);
      if (existingData == null) continue;

      final List<Todo> todos = List<Todo>.from(
        (jsonDecode(existingData) as List)
            .map((e) => Todo.fromJson(Map<String, dynamic>.from(e))),
      );

      bool changed = false;

      for (var t in todos) {
        final match = dialogTodos.firstWhere(
          (w) => w.id == t.id,
          orElse: () => WeeklyTodo(id: '', title: '', days: []),
        );
        if (match.id.isNotEmpty && t.color != match.color) {
          t.color = match.color; // ✅ 색상 동기화
          changed = true;
        }
      }

      if (changed) {
        await dailyBox.put(key, jsonEncode(todos.map((t) => t.toJson()).toList()));
        print("🎨 ${_dateKey(date)} 색상 갱신 완료");
      }
    }
  }


  Future<void> updateTodo(
    String id, {
    String? title,
    List<int>? days,
    DateTime? startTime,
    DateTime? endTime,
    String? textTime,
    bool fromMain = false,
  }) async {
    final box = await _openBox(fromMain: fromMain);
    final current = List<WeeklyTodo>.from(box.get('todos', defaultValue: []));
    final index = current.indexWhere((t) => t.id == id);
    if (index != -1) {
      final target = current[index];
      if (title != null) target.title = title.trim();
      if (days != null) target.days = List<int>.from(days);
      target.startTime = startTime;
      target.endTime = endTime;
      if (textTime != null) target.textTime = textTime;
      target.updatedAt = DateTime.now().toUtc();
      await box.put('todos', current);
      LocalChangeNotifier.notify('todos');
    }
  }
  // ─────────────────────────────────────────────
    // ✅ 날짜별 Todo 상태 관리 (핵심 추가)
    Todo _copyWithTouchedUpdatedAt(Todo t, DateTime now, bool touchUpdatedAt) {
      final copy = t.copy();
      if (touchUpdatedAt) copy.updatedAt = now;
      return copy;
    }

    Future<void> saveDailyState(
      DateTime date,
      List<Todo> todos, {
      bool touchUpdatedAt = true,
    }) async {
      final box = await _openDailyBox();
      final key = _dateKey(date);

      // ✅ 순서 및 체크 상태를 JSON으로 저장
      final now = DateTime.now();
      final data = todos
          .map((t) => _copyWithTouchedUpdatedAt(t, now, touchUpdatedAt).toJson())
          .toList();
      await box.put(key, jsonEncode(data));
      LocalChangeNotifier.notify('todos');
    }

    Future<void> saveDailyStateByKey(
      String dateKey,
      List<Todo> todos, {
      bool touchUpdatedAt = true,
    }) async {
      final box = await _openDailyBox();

      final now = DateTime.now();
      final data = todos
          .map((t) => _copyWithTouchedUpdatedAt(t, now, touchUpdatedAt).toJson())
          .toList();
      await box.put(dateKey, jsonEncode(data));
      LocalChangeNotifier.notify('todos');
    }

    Future<void> deleteDailyStateByKey(String dateKey) async {
      final box = await _openDailyBox();
      await box.delete(dateKey);
      LocalChangeNotifier.notify('todos');
    }

    Future<List<Todo>> loadDailyState(DateTime date) async {
      final box = await _openDailyBox();
      final key = _dateKey(date);
      final jsonData = box.get(key);
      if (jsonData == null) return [];

      try {
        final list = jsonDecode(jsonData);
        return List<Todo>.from(
          (list as List).map((e) => Todo.fromJson(Map<String, dynamic>.from(e))),
        );
      } catch (e) {
        print("⚠️ [TodoService] loadDailyState parsing error: $e");
        return [];
      }
    }

    Future<List<Todo>> loadDailyTodosMerged(
      DateTime date, {
      bool forceRefresh = false,
      bool persist = false,
    }) async {
      final dialogBox = await _openBox(fromMain: false);
      final dialogTodos =
          List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));

      final weeklyById = <String, WeeklyTodo>{};
      for (final w in dialogTodos) {
        weeklyById[w.id] = w;
      }

      final dailyBox = await _openDailyBox();
      final key = _dateKey(date);
      if (forceRefresh) {
        await dailyBox.delete(key);
      }

      final existingTodos = _decodeDailyTodos(dailyBox.get(key));
      final merged = _mergeDailyWithWeekly(date, existingTodos, weeklyById);
      if (persist && merged.changed) {
        await dailyBox.put(
          key,
          jsonEncode(merged.todos.map((t) => t.toJson()).toList()),
        );
        LocalChangeNotifier.notify('todos');
      }
      return merged.todos;
    }

    Future<Map<String, List<Todo>>> loadAllDailyStates() async {
      final box = await _openDailyBox();
      final out = <String, List<Todo>>{};
      for (final entry in box.toMap().entries) {
        final key = entry.key?.toString();
        final val = entry.value?.toString();
        if (key == null || val == null) continue;
        try {
          final decoded = jsonDecode(val);
          final list = List<Todo>.from(
            (decoded as List)
                .map((e) => Todo.fromJson(Map<String, dynamic>.from(e))),
          );
          out[key] = list;
        } catch (_) {}
      }
      return out;
    }

    Future<void> clearDailyStates() async {
      final box = await _openDailyBox();
      await box.clear();
      LocalChangeNotifier.notify('todos');
    }

    String _dateKey(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    DateTime? _tryParseDateKey(String key) {
      final t = DateTime.tryParse(key);
      if (t == null) return null;
      return DateTime(t.year, t.month, t.day);
    }

    List<Todo> _decodeDailyTodos(dynamic raw) {
      if (raw == null) return [];
      try {
        if (raw is String) {
          final decoded = jsonDecode(raw);
          return List<Todo>.from(
            (decoded as List).map((e) => Todo.fromJson(Map<String, dynamic>.from(e))),
          );
        }
        if (raw is List) {
          return List<Todo>.from(
            raw.map((e) => e is Todo ? e : Todo.fromJson(Map<String, dynamic>.from(e))),
          );
        }
      } catch (_) {}
      return [];
    }

    DateTime? _weeklyDueTimeForDate(DateTime date, WeeklyTodo w) {
      final st = w.startTime;
      if (st == null) return null;
      return DateTime(date.year, date.month, date.day, st.hour, st.minute);
    }

    bool _sameDueTime(DateTime? a, DateTime? b) {
      if (a == null || b == null) return a == b;
      return a.year == b.year &&
          a.month == b.month &&
          a.day == b.day &&
          a.hour == b.hour &&
          a.minute == b.minute;
    }

    ({List<Todo> todos, bool changed}) _mergeDailyWithWeekly(
      DateTime date,
      List<Todo> existingTodos,
      Map<String, WeeklyTodo> weeklyById,
    ) {
      final weekday = date.weekday;
      bool changed = false;

      final out = <Todo>[];
      for (final t in existingTodos) {
        final w = weeklyById[t.id];
        if (w == null) {
          out.add(t);
          continue;
        }
        if (w.deleted == true || !w.days.contains(weekday)) {
          changed = true;
          continue;
        }

        final newTitle = w.title;
        final newTextTime = w.textTime;
        final newColor = w.color;
        final newDueTime = _weeklyDueTimeForDate(date, w);

        if (t.title != newTitle) {
          t.title = newTitle;
          changed = true;
        }
        if (t.textTime != newTextTime) {
          t.textTime = newTextTime;
          changed = true;
        }
        if (t.color != newColor) {
          t.color = newColor;
          changed = true;
        }
        if (!_sameDueTime(t.dueTime, newDueTime)) {
          t.dueTime = newDueTime;
          changed = true;
        }

        out.add(t);
      }

      final existingIds = out.map((t) => t.id).toSet();
      for (final w in weeklyById.values) {
        if (w.deleted == true) continue;
        if (!w.days.contains(weekday)) continue;
        if (existingIds.contains(w.id)) continue;
        changed = true;
        out.add(Todo(
          w.id,
          w.title,
          isDone: false,
          dueTime: _weeklyDueTimeForDate(date, w),
          textTime: w.textTime,
          color: w.color,
        ));
      }

      return (todos: out, changed: changed);
    }

  // ─────────────────────────────────────────────
  // ✅ 메인(Todo) 전용 로드/세이브

  Future<List<Todo>> loadMainTodos() async {
    final box = await _openBox(fromMain: true);
    final raw = box.get('todos');

    if (raw == null || raw is! List || raw.isEmpty) {
      print("📭 메인 박스 비어 있음");
      return [];
    }

    final result = <Todo>[];
    for (final e in raw) {
      if (e is Map) {
        result.add(Todo.fromJson(Map<String, dynamic>.from(e)));
      } else if (e is Todo) {
        result.add(e);
      } else if (e is WeeklyTodo) {
        // ✅ WeeklyTodo 데이터 자동 변환
        result.add(
          Todo(
            e.id,
            e.title,
            isDone: e.isCompleted,
            dueTime: e.startTime,
            textTime: e.textTime,
            color: e.color, // ✅ 추가!
          ),
        );
      }
    }

    print("📦 메인 박스 로드 완료 (${result.length}개)");
    return result;
  }

  Future<void> saveMainTodos(List<Todo> todos) async {
    final box = await _openBox(fromMain: true);
    await box.put('todos', todos.map((t) => t.toJson()).toList());
    LocalChangeNotifier.notify('todos');
  }

  // ─────────────────────────────────────────────
  // ✅ 완료 / 삭제 / 순서 갱신

  Future<void> toggleComplete(String id, bool value,
      {bool fromMain = false}) async {
    if (fromMain) {
      final list = await loadMainTodos();
      final i = list.indexWhere((t) => t.id == id);
      if (i != -1) {
        list[i].isDone = value;
        list[i].updatedAt = DateTime.now().toUtc();
        await saveMainTodos(list);
      }
    } else {
      final box = await _openBox(fromMain: false);
      final list =
          List<WeeklyTodo>.from(box.get('todos', defaultValue: []));
      final i = list.indexWhere((t) => t.id == id);
      if (i != -1) {
        list[i].isCompleted = value;
        list[i].updatedAt = DateTime.now().toUtc();
        await box.put('todos', list);
        LocalChangeNotifier.notify('todos');
      }
    }
  }

  Future<void> deleteTodo(String id, {bool fromMain = false}) async {
    if (fromMain) {
      final list = await loadMainTodos();
      list.removeWhere((t) => t.id == id);
      await saveMainTodos(list);
    } else {
      final box = await _openBox(fromMain: false);
      final list =
          List<WeeklyTodo>.from(box.get('todos', defaultValue: []));
      final i = list.indexWhere((t) => t.id == id);
      if (i != -1) {
        list[i].deleted = true;
        list[i].updatedAt = DateTime.now().toUtc();
      }
      await box.put('todos', list);
      LocalChangeNotifier.notify('todos');
    }
  }

  Future<void> updateOrder(List<dynamic> reordered,
      {bool fromMain = false}) async {
    if (fromMain) {
      final todos = List<Todo>.from(reordered);
      await saveMainTodos(todos);
    } else {
      final box = await _openBox(fromMain: false);
      final weekly = List<WeeklyTodo>.from(reordered);
      await box.put('todos', weekly);
      LocalChangeNotifier.notify('todos');
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 전체 초기화

  Future<void> clearAll({bool fromMain = false}) async {
    final box = await _openBox(fromMain: fromMain);
    await box.clear();
    LocalChangeNotifier.notify('todos');
  }

  // ─────────────────────────────────────────────
  // ✅ 오늘 요일 
  Future<void> syncTodayFromDialog({bool forceRefresh = false}) async {
    final today = DateTime.now();
    await syncDayFromDialog(today, forceRefresh: forceRefresh);
  }

  /// ✅ 특정 날짜의 DailyState를 WeeklyTodo(Dialog) 기준으로 동기화
  /// - 기존 완료 상태/로컬 정렬은 유지
  /// - 새로 추가된 WeeklyTodo는 추가
  /// - 삭제된 WeeklyTodo는 제거
  Future<void> syncDayFromDialog(DateTime date, {bool forceRefresh = false}) async {
    await loadDailyTodosMerged(date, forceRefresh: forceRefresh);
    return;

    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));

    final weekday = date.weekday;
    final dailyBox = await _openDailyBox();
    final key = _dateKey(date);

    if (forceRefresh) {
      await dailyBox.delete(key);
    }

    final weeklyForDayAll =
        dialogTodos.where((t) => t.days.contains(weekday)).toList();
    final weeklyForDay =
        weeklyForDayAll.where((t) => t.deleted != true).toList();
    if (weeklyForDay.isEmpty && weeklyForDayAll.isEmpty) {
      // keep existing daily state as-is when there is no schedule for the day
      return;
    }

    final existingData = dailyBox.get(key);
    final List<Todo> existingTodos = existingData == null
        ? []
        : List<Todo>.from(
            (jsonDecode(existingData) as List)
                .map((e) => Todo.fromJson(Map<String, dynamic>.from(e))),
          );

    final updated = <Todo>[...existingTodos];

    // 1) 신규 항목 추가
    for (final w in weeklyForDay) {
      final exists = updated.any((t) => t.id == w.id);
      if (!exists) {
        updated.add(Todo(
          w.id,
          w.title,
          isDone: false,
          dueTime: w.startTime,
          textTime: w.textTime,
          color: w.color,
        ));
      }
    }

    final activeIds = weeklyForDay.map((w) => w.id).toSet();
    final allIds = weeklyForDayAll.map((w) => w.id).toSet();

    // 2) 스케줄에서 빠진 항목 제거 (또는 삭제된 항목 제거)
    updated.removeWhere((t) {
      // if this id exists in weekly schedule (even as deleted), keep only when active
      if (allIds.contains(t.id)) return !activeIds.contains(t.id);
      // otherwise, keep (may be one-off)
      return false;
    });

    await dailyBox.put(key, jsonEncode(updated.map((t) => t.toJson()).toList()));
    LocalChangeNotifier.notify('todos');
  }

  

  // ─────────────────────────────────────────────
  // ✅ 레거시 타이틀 정리 (안전 버전)
  Future<void> cleanLegacyTitles() async {
    final timeTag = RegExp(r'\[.*?\]\s*');

    // 1) 관리창 박스(WeeklyTodo)만 WeeklyTodo로 정리
    final dialogBox = await _openBox(fromMain: false);
    final rawDialog = dialogBox.get('todos', defaultValue: []);
    bool dialogModified = false;
    final List dialogOut = [];

    if (rawDialog is List) {
      for (final e in rawDialog) {
        if (e is WeeklyTodo) {
          final cleaned = e.title.replaceAll(timeTag, '').trim();
          if (cleaned != e.title) {
            e.title = cleaned;
            dialogModified = true;
          }
          dialogOut.add(e); // Hive 어댑터 등록되어 있으니 객체로 저장 OK
        } else if (e is Map) {
          // 옛날에 Map으로 저장된 경우 복구
          final w = WeeklyTodo.fromJson(Map<String, dynamic>.from(e));
          final cleaned = w.title.replaceAll(timeTag, '').trim();
          if (cleaned != w.title) {
            w.title = cleaned;
            dialogModified = true;
          }
          dialogOut.add(w);
        } else {
          // 알 수 없는 타입은 그대로 보존
          dialogOut.add(e);
        }
      }
      if (dialogModified) {
        await dialogBox.put('todos', dialogOut);
      }
    }

    // 2) 메인 박스(Todo)는 Map/객체 혼재 → title만 문자열로 깨끗하게
    final mainBox = await _openBox(fromMain: true);
    final rawMain = mainBox.get('todos', defaultValue: []);
    bool mainModified = false;
    final List mainOut = [];

    if (rawMain is List) {
      for (final e in rawMain) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final title = (m['title'] ?? '').toString();
          final cleaned = title.replaceAll(timeTag, '').trim();
          if (cleaned != title) {
            m['title'] = cleaned;
            mainModified = true;
          }
          mainOut.add(m); // 메인 박스는 원래 Map(JSON) 형태로 유지
        } else if (e is Todo) {
          final t = e;
          final cleaned = t.title.replaceAll(timeTag, '').trim();
          if (cleaned != t.title) {
            t.title = cleaned;
            mainModified = true;
          }
          mainOut.add(t.toJson()); // 일관성 위해 JSON으로 저장
        } else if (e is WeeklyTodo) {
          // 드물게 섞여 있으면 제목만 정리 후 Todo JSON으로 변환해서 넣을 수도 있음.
          final cleaned = e.title.replaceAll(timeTag, '').trim();
          final title2 = cleaned.isEmpty ? e.title : cleaned;
          mainOut.add({
            'id': e.id,
            'title': title2,
            'isDone': e.isCompleted,
            'dueTime': e.startTime?.toIso8601String(),
            'textTime': e.textTime,
            'color': e.color, // ✅ 여기를 이렇게 수정!
          });
          mainModified = true;
        } else {
          mainOut.add(e);
        }
      }
      if (mainModified) {
        await mainBox.put('todos', mainOut);
      }
    }
  }

  Future<void> _migrateLegacyBox({
    required Box targetBox,
    required String legacyName,
  }) async {
    if (targetBox.name == legacyName) return;
    if (!await Hive.boxExists(legacyName)) return;

    final migrateKey = '${targetBox.name}<-${legacyName}';
    final existing = _migratingLegacy[migrateKey];
    if (existing != null) return await existing;

    final future = () async {
      final legacy = await _openBoxByName(legacyName);
      if (targetBox.isEmpty && legacy.isNotEmpty) {
        await targetBox.putAll(legacy.toMap());
        await legacy.clear();
      }
    }();

    _migratingLegacy[migrateKey] = future;
    try {
      await future;
    } finally {
      _migratingLegacy.remove(migrateKey);
    }
  }
}

import 'package:hive_flutter/hive_flutter.dart';
import '../models/weekly_todo.dart';
import '../models/todo.dart';
import 'local_scope.dart';
import 'dart:convert'; // ✅ jsonEncode / jsonDecode 사용을 위해 필요

class TodoService {
  static const String _legacyMainBoxName = 'weekly_todos_main';
  static const String _legacyDialogBoxName = 'weekly_todos_dialog';
  static const String _legacyDailyBoxName = 'planner_daily_todos_state_box';

  String get _mainBoxName => LocalScope.weeklyMainBox;
  String get _dialogBoxName => LocalScope.weeklyDialogBox;
  String get _dailyBoxName => LocalScope.dailyTodosBox;

  // ─────────────────────────────────────────────
  // ✅ 공통 초기화

  Future<void> clearAllTodos() async {
    await clearAll(fromMain: true);
    await clearAll(fromMain: false);
    await clearDailyStates(); // ✅ 날짜별 상태도 초기화
  }

  Future<Box> _openBox({bool fromMain = false}) async {
    final name = fromMain ? _mainBoxName : _dialogBoxName;
    // ✅ 제네릭 제거
    final box = await Hive.openBox(name);
    await _migrateLegacyBox(
      targetBox: box,
      legacyName: fromMain ? _legacyMainBoxName : _legacyDialogBoxName,
    );
    return box;
  }


  Future<Box> _openDailyBox() async {
    // 이미 열려있으면 바로 반환 (중복 open 방지)
    if (Hive.isBoxOpen(_dailyBoxName)) {
      return Hive.box(_dailyBoxName);
    }
    final box = await Hive.openBox(_dailyBoxName);
    await _migrateLegacyBox(
      targetBox: box,
      legacyName: _legacyDailyBoxName,
    );
    return box;
  }

  // ─────────────────────────────────────────────
  // ✅ WeeklyTodo 관리창용

  Future<List<WeeklyTodo>> loadTodos({bool fromMain = false}) async {
    final box = await _openBox(fromMain: fromMain);
    final todos = box.get('todos', defaultValue: <WeeklyTodo>[]);
    return List<WeeklyTodo>.from(
      (todos as List).map((e) {
        if (e is WeeklyTodo) return e.copy();
        if (e is Map) return WeeklyTodo.fromJson(Map<String, dynamic>.from(e));
        throw Exception('Invalid WeeklyTodo: $e');
      }),
    );
  }

  Future<void> saveTodos(List<WeeklyTodo> todos,
      {bool fromMain = false}) async {
    final box = await _openBox(fromMain: fromMain);
    await box.put('todos', todos);
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
    final now = DateTime.now();

    // ✅ 강제 새로고침 모드면 모든 DailyBox 초기화
    if (forceRefresh) {
      print("🌀 강제 새로고침: DailyBox 전체 초기화 중...");
      await dailyBox.clear();
    }

    // 🔹 일주일 전~후 7일 포함
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
      final weeklyForDay =
          dialogTodos.where((t) => t.days.contains(weekday)).toList();

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
  }

  Future<void> syncSpecificDays(List<int> daysToUpdate) async {
    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
    if (dialogTodos.isEmpty) return;

    final dailyBox = await _openDailyBox();
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

      final weeklyForDay =
          dialogTodos.where((t) => t.days.contains(date.weekday)).toList();

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
  }


  Future<void> refreshColorsFromDialog() async {
    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
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
      await box.put('todos', current);
    }
  }
  // ─────────────────────────────────────────────
    // ✅ 날짜별 Todo 상태 관리 (핵심 추가)
    Future<void> saveDailyState(DateTime date, List<Todo> todos) async {
      final box = await _openDailyBox();
      final key = _dateKey(date);

      // ✅ 순서 및 체크 상태를 JSON으로 저장
      final data = todos.map((t) => t.toJson()).toList();
      await box.put(key, jsonEncode(data));
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

    Future<void> clearDailyStates() async {
      final box = await _openDailyBox();
      await box.clear();
    }

    String _dateKey(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

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
        await saveMainTodos(list);
      }
    } else {
      final box = await _openBox(fromMain: false);
      final list =
          List<WeeklyTodo>.from(box.get('todos', defaultValue: []));
      final i = list.indexWhere((t) => t.id == id);
      if (i != -1) {
        list[i].isCompleted = value;
        await box.put('todos', list);
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
      list.removeWhere((t) => t.id == id);
      await box.put('todos', list);
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
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 전체 초기화

  Future<void> clearAll({bool fromMain = false}) async {
    final box = await _openBox(fromMain: fromMain);
    await box.clear();
  }

  // ─────────────────────────────────────────────
  // ✅ 오늘 요일 
  Future<void> syncTodayFromDialog({bool forceRefresh = false}) async {
    final dialogBox = await _openBox(fromMain: false);
    final dialogTodos =
        List<WeeklyTodo>.from(dialogBox.get('todos', defaultValue: []));
    final today = DateTime.now();
    final weekday = today.weekday;

    // ✅ 강제 새로고침 모드면 오늘 데이터 완전히 삭제
    if (forceRefresh) {
      print("🌀 강제 새로고침: 오늘자 DailyBox 데이터 초기화 중...");
      final dailyBox = await _openDailyBox();
      await dailyBox.delete(_dateKey(today));
    }

    final todays = dialogTodos.where((t) => t.days.contains(weekday)).toList();
    if (todays.isEmpty) {
      print("📭 오늘 요일(${weekday})에 해당하는 WeeklyTodo 없음");
      return;
    }

    // ✅ 이미 dailyBox에 저장된 데이터가 있어도 강제 덮어쓰기 허용
    final existingDaily = await loadDailyState(today);
    if (existingDaily.isNotEmpty && !forceRefresh) {
      print("🛑 ${_dateKey(today)}의 DailyBox 데이터 존재 → 덮어쓰기 방지 (forceRefresh=false)");
      return;
    }

    // ✅ WeeklyTodo → Todo 변환
    final generated = todays
        .map((w) => Todo(
              w.id,
              w.title,
              isDone: false,
              dueTime: w.startTime,
              textTime: w.textTime,
              color: w.color, // ✅ 주간 투두 색상 동기화
            ))
        .toList();

    await saveMainTodos(generated);
    await saveDailyState(today, generated);
    print("🆕 오늘(${weekday}) 요일 투두 ${forceRefresh ? '강제' : '최초'} 생성 완료 (${generated.length}개)");
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

    final legacy = await Hive.openBox(legacyName);
    if (targetBox.isEmpty && legacy.isNotEmpty) {
      await targetBox.putAll(legacy.toMap());
      await legacy.clear();
    }

    if (legacy.isOpen) {
      await legacy.close();
    }
  }
}

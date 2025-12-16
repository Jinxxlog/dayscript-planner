import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';
import 'local_scope.dart';

class StorageService {
  static const String _legacyTodosKey = "todos";
  static const String _legacyMemoKey = "memo";

  // 📅 오늘 전용 투두 관련 키
  static const String _legacyTodayTodosKey = "today_todos";
  static const String _legacyLastWeeklySyncDateKey = "lastWeeklySyncDate";

  static String get _todosKey => LocalScope.todosKey;
  static String get _memoKey => LocalScope.memoPadKey;
  static String get _todayTodosKey => LocalScope.todayTodosKey;
  static String get _lastWeeklySyncDateKey => LocalScope.lastWeeklySyncDateKey;

  // ✅ 일반 할 일 저장
  static Future<void> saveTodos(List<Todo> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final todoList = todos.map((todo) => todo.toJson()).toList();
    await prefs.setString(_todosKey, jsonEncode(todoList));
    await prefs.remove(_legacyTodosKey);
  }

  // ✅ 일반 할 일 불러오기 (이전 버전 호환)
  static Future<List<Todo>> loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? todosString =
        await _readWithMigration(prefs, _todosKey, _legacyTodosKey);
    if (todosString == null) return [];

    try {
      final List decoded = jsonDecode(todosString);
      return decoded.map((e) {
        // ✅ 예전 데이터에 id가 없을 경우 안전하게 생성
        final map = Map<String, dynamic>.from(e);
        final id = map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        final title = map['title'] ?? '';
        final done = map['isDone'] ?? false;
        return Todo(id, title, isDone: done);
      }).toList();
    } catch (e) {
      print("❌ [StorageService] loadTodos error: $e");
      return [];
    }
  }

  // ✅ 메모 저장
  static Future<void> saveMemo(String memo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoKey, memo);
    await prefs.remove(_legacyMemoKey);
  }

  // ✅ 메모 불러오기
  static Future<String?> loadMemo() async {
    final prefs = await SharedPreferences.getInstance();
    return _readWithMigration(prefs, _memoKey, _legacyMemoKey);
  }

  // ─────────────────────────────────────────────
  // 🌙 오늘자 투두 (자정마다 갱신되는 임시 저장소)
  // ─────────────────────────────────────────────

  /// ✅ 오늘자 투두 저장 (ReorderableListView 갱신용)
  static Future<void> saveTodayTodos(List<Todo> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(todos.map((t) => t.toJson()).toList());
    await prefs.setString(_todayTodosKey, encoded);
    await prefs.remove(_legacyTodayTodosKey);
  }

  /// ✅ 오늘자 투두 불러오기 (모델 리스트)
  static Future<List<Todo>> loadTodayTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final s = await _readWithMigration(
        prefs, _todayTodosKey, _legacyTodayTodosKey);
    if (s == null) return [];
    final List decoded = jsonDecode(s);
    return decoded.map((e) {
      final map = Map<String, dynamic>.from(e);
      final id = map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final title = map['title'] ?? '';
      final done = map['isDone'] ?? false;
      return Todo(id, title, isDone: done);
    }).toList();
  }

  /// ✅ 마지막 주간-투두 동기화 날짜 기록
  static Future<void> setLastWeeklySyncDate(String yyyymmdd) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWeeklySyncDateKey, yyyymmdd);
    await prefs.remove(_legacyLastWeeklySyncDateKey);
  }

  /// ✅ 마지막 주간-투두 동기화 날짜 불러오기
  static Future<String?> getLastWeeklySyncDate() async {
    final prefs = await SharedPreferences.getInstance();
    return _readWithMigration(
        prefs, _lastWeeklySyncDateKey, _legacyLastWeeklySyncDateKey);
  }

  static Future<String?> _readWithMigration(
      SharedPreferences prefs, String scopedKey, String legacyKey) async {
    final scoped = prefs.getString(scopedKey);
    if (scoped != null) return scoped;

    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      await prefs.setString(scopedKey, legacy);
      await prefs.remove(legacyKey);
    }
    return legacy;
  }
}

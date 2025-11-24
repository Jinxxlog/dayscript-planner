import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo.dart';

class StorageService {
  static const String todosKey = "todos";
  static const String memoKey = "memo";

  // 📅 오늘 전용 투두 관련 키
  static const String todayTodosKey = "today_todos";
  static const String lastWeeklySyncDateKey = "lastWeeklySyncDate";

  // ✅ 일반 할 일 저장
  static Future<void> saveTodos(List<Todo> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final todoList = todos.map((todo) => todo.toJson()).toList();
    await prefs.setString(todosKey, jsonEncode(todoList));
  }

  // ✅ 일반 할 일 불러오기 (이전 버전 호환)
  static Future<List<Todo>> loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? todosString = prefs.getString(todosKey);
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
    await prefs.setString(memoKey, memo);
  }

  // ✅ 메모 불러오기
  static Future<String?> loadMemo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(memoKey);
  }

  // ─────────────────────────────────────────────
  // 🌙 오늘자 투두 (자정마다 갱신되는 임시 저장소)
  // ─────────────────────────────────────────────

  /// ✅ 오늘자 투두 저장 (ReorderableListView 갱신용)
  static Future<void> saveTodayTodos(List<Todo> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(todos.map((t) => t.toJson()).toList());
    await prefs.setString(todayTodosKey, encoded);
  }

  /// ✅ 오늘자 투두 불러오기 (모델 리스트)
  static Future<List<Todo>> loadTodayTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(todayTodosKey);
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
    await prefs.setString(lastWeeklySyncDateKey, yyyymmdd);
  }

  /// ✅ 마지막 주간-투두 동기화 날짜 불러오기
  static Future<String?> getLastWeeklySyncDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastWeeklySyncDateKey);
  }
}

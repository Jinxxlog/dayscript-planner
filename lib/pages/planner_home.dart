import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'dart:async';
import 'dart:ui'; // 🔹 Blur 효과를 위한 ImageFilter
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weekly_todo.dart';
import '../models/todo.dart';
import '../services/todo_service.dart';
import '../widgets/weekly_todo_dialog.dart';
import '../widgets/calendar_widget.dart';
import '../widgets/memo_pad.dart';
import '../widgets/todo_list.dart';
import '../services/overlay_control_service.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) '../desktop_multi_window_stub.dart';
import 'dart:convert';
import '../widgets/ui/macos_panel_style.dart';

// ✅ 키보드 단축키용 Intent 정의
class PrevMonthIntent extends Intent {
  const PrevMonthIntent();
}

class NextMonthIntent extends Intent {
  const NextMonthIntent();
}

class GoTodayIntent extends Intent {
  const GoTodayIntent();
}

class PlannerHomePage extends StatefulWidget {
  final void Function(String) onThemeChange;
  const PlannerHomePage({super.key, required this.onThemeChange});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage> {
  final _todoService = TodoService();

  bool _todoCollapsed = false; // 투두 접힘 여부
  bool _memoCollapsed = false; // 메모 접힘 여부

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  DateTime _currentDate = DateTime.now();
  Timer? _midnightTimer;
  bool _isGoingBack = false;

  bool _isLoading = true; // ✅ 로딩 상태
  List<Todo> _todos = [];

  // ✅ 오버레이 관련 상태
  bool _isOverlay = false;   // 오버레이 모드 상태
  double _opacityValue = 1.0; // 투명도 슬라이더 값
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    OverlayControlService.init(); // 🪟 window_manager 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      await OverlayControlService.init(); // ✅ 윈도우 초기화
      await _initializeData();
      await Future.delayed(const Duration(milliseconds: 200));
      await _loadTodosByDate(DateTime.now());
      if (kDebugMode) {
        print("✅ 초기 로드 완료 (오늘 투두 표시)");
      }
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // ✅ 초기화
  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await _todoService.cleanLegacyTitles();

    // ✅ 박스 로딩 보장
    await Future.delayed(const Duration(milliseconds: 100));
    await _todoService.syncTodayFromDialog();

    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    await _loadTodosByDate(_selectedDay);

    _startMidnightWatcher();
    setState(() => _isLoading = false);
  }

  Future<void> _init() async {
    await _checkNewDay();
    await _todoService.cleanLegacyTitles();
    await _todoService.syncTodayFromDialog();
  }

  Future<void> _checkNewDay() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString('last_date');
    final today = DateTime.now();
    final todayKey = "${today.year}-${today.month}-${today.day}";

    if (lastDate != todayKey) {
      await _todoService.syncTodayFromDialog();
      await prefs.setString('last_date', todayKey);
    }
  }

  // ✅ 자정 감시 타이머
  void _startMidnightWatcher() {
    _midnightTimer?.cancel();
    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final now = DateTime.now();
      if (now.day != _currentDate.day) {
        _currentDate = now;
        await _todoService.syncTodayFromDialog();
        await _loadTodosByDate(now);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'last_date', "${now.year}-${now.month}-${now.day}");
      }
    });
  }

  Future<void> _loadTodosByDate(DateTime date) async {
    final todos = await _todoService.loadDailyState(date);

    if (todos.isNotEmpty) {
      // ✅ 이미 해당 날짜의 투두가 dailyBox에 저장돼 있음
      setState(() {
        _todos = todos;
      });
      return;
    }

    // ✅ 저장된 데이터가 없으면 WeeklyTodo 기반으로 생성
    final weeklyTodos = await _todoService.loadTodos(fromMain: false);
    final weekday = date.weekday;

    final matched = weeklyTodos.where((t) => t.days.contains(weekday)).toList();
    final generated = matched
        .map((t) => Todo(
              t.id,
              t.title,
              isDone: t.isCompleted,
              dueTime: t.startTime,
              textTime: t.textTime,
              color: t.color, // ✅ 색상 유지
            ))
        .toList();

    // ✅ 새로 생성된 데이터를 dailyBox에도 저장
    await _todoService.saveDailyState(date, generated);

    setState(() {
      _todos = generated;
    });
  }

  // ✅ 완료 상태 토글 (체크 반영 즉시 저장)
  Future<void> _toggleComplete(Todo todo, bool value) async {
    final updatedList = List<Todo>.from(_todos);
    final index = updatedList.indexWhere((t) => t.id == todo.id);
    if (index != -1) {
      updatedList[index].isDone = value;
      setState(() => _todos = updatedList);

      // ✅ 날짜별 상태 즉시 저장
      await _todoService.saveDailyState(_selectedDay, updatedList);
      if (kDebugMode) {
        print("☑️ ${todo.title} → ${value ? '완료' : '미완료'} 저장됨");
      }
    }
  }

  // ✅ 순서 변경 (드래그 후 즉시 저장)
  void _reorderTodos(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _todos.removeAt(oldIndex);
      _todos.insert(newIndex, item);
    });

    // ✅ 날짜별 순서 반영 저장
    await _todoService.saveDailyState(_selectedDay, _todos);
    if (kDebugMode) {
      print("🔄 ${_selectedDay.toIso8601String()} 투두 순서 변경 및 저장됨");
    }
  }

  // ✅ 시간순 정렬
  Future<void> _sortTodosByTime() async {
    int getGroupIndex(Todo t) {
      // 1) 시간이 있는 경우
      if (t.dueTime != null) {
        final hour = t.dueTime!.hour;
        if (hour < 8) return 1; // 아침
        if (hour < 12) return 2; // 점심
        if (hour < 18) return 3; // 저녁
        return 4; // 아무때나
      }

      // 2) 텍스트 기반
      final txt = (t.textTime ?? "").trim();
      switch (txt) {
        case "아침":
          return 1;
        case "점심":
          return 2;
        case "저녁":
          return 3;
        case "아무때나":
          return 4;
      }

      return 5; // 분류 불가 → 제일 뒤
    }

    setState(() {
      _todos.sort((a, b) {
        final ai = getGroupIndex(a);
        final bi = getGroupIndex(b);

        // 1차 정렬: 그룹 우선순위
        if (ai != bi) return ai.compareTo(bi);

        // 2차 정렬: 같은 그룹 내에서 dueTime 비교
        if (a.dueTime != null && b.dueTime != null) {
          return a.dueTime!.compareTo(b.dueTime!);
        }

        // 3차 정렬: a만 시간 있음 → a 먼저
        if (a.dueTime != null) return -1;

        // 4차 정렬: b만 시간 있음 → b 먼저
        if (b.dueTime != null) return 1;

        // 5차: 둘 다 텍스트만 있을 경우 → 그대로 유지
        return 0;
      });
    });

    // 정렬 후 저장
    await _todoService.saveDailyState(_selectedDay, _todos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("투두 정렬 완료!"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  // ✅ UI 구성
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: false,

      // 🔹 배경 투명도(오버레이)
      backgroundColor: _isOverlay
          ? (isDark
              ? Colors.black.withOpacity(0.85)
              : Colors.white.withOpacity(0.9))
          : theme.scaffoldBackgroundColor,

      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.account_circle, size: 26),
          tooltip: "프로필 / 설정",
          onPressed: () async {
            if (!_isDesktop) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("데스크톱 전용 기능입니다."),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            // 👉 새 설정창 띄우기 (desktop_multi_window)
            final window = await DesktopMultiWindow.createWindow(
              jsonEncode({
                'page': 'settings',
              }),
            );

            window
              ..setFrame(const Offset(100, 100) & const Size(600, 700))
              ..setTitle("Settings - DayScript")
              ..show();

            debugPrint("🪟 설정 창 생성 완료!");
          },
        ),
        title: const Text("DayScript"),
        backgroundColor: _isOverlay
            ? (isDark
                ? Colors.black.withOpacity(0.6)
                : Colors.white.withOpacity(0.7))
            : theme.appBarTheme.backgroundColor,
        elevation: _isOverlay ? 0 : 2,
        actions: [
          // 🔹 투명도 슬라이더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.opacity_rounded,
                    size: 20, color: Colors.blueAccent),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.blueAccent,
                    inactiveTrackColor:
                        Colors.blueAccent.withOpacity(0.2),
                    thumbColor: Colors.blueAccent,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _opacityValue,
                    min: 0.3,
                    max: 1.0,
                    divisions: 7,
                    label: "${(_opacityValue * 100).toInt()}%",
                    onChanged: !_isDesktop
                        ? null
                        : (v) {
                            setState(() => _opacityValue = v);
                            WidgetsBinding.instance
                                .addPostFrameCallback((_) async {
                              await OverlayControlService
                                  .setBackgroundOpacity(v);
                            });
                          },
                  ),
                ),
              ),
              Text(
                "${(_opacityValue * 100).toInt()}%",
                  style: const TextStyle(
                      fontSize: 13, color: Colors.blueAccent),
                ),
              ],
            ),
          ),

          // 🔹 오버레이 모드 버튼
          IconButton(
            tooltip: _isOverlay ? "일반 모드로 복귀" : "오버레이 모드 전환",
            icon: Icon(
              _isOverlay ? Icons.desktop_windows : Icons.layers,
              color: _isOverlay ? Colors.greenAccent : Colors.blueAccent,
            ),
            onPressed: () async {
              if (!_isDesktop) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("오버레이는 데스크톱에서만 지원됩니다."),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setState(() => _isOverlay = !_isOverlay);
              if (_isOverlay) {
                await OverlayControlService.enterOverlayMode();
              } else {
                await OverlayControlService.exitOverlayMode();
              }
            },
          ),
        ],
      ),

      // 🧩 메인 내용부
      body: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isOverlay
                ? (isDark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.white.withOpacity(0.4))
                : theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: _isOverlay
                ? Border.all(color: Colors.white.withOpacity(0.25), width: 1)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _buildMainBody(),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ✅ 레이아웃 상태 헬퍼
  bool get _showCalendarFull => _todoCollapsed && _memoCollapsed;
  bool get _showTodoOnly => !_todoCollapsed && _memoCollapsed;
  bool get _showMemoOnly => _todoCollapsed && !_memoCollapsed;
  bool get _showBoth => !_todoCollapsed && !_memoCollapsed;

  // ─────────────────────────────────────────────
  Widget _buildMainBody() {
    return Padding(
      padding: const EdgeInsets.only(left: 20.0),
      child: Row(
        children: [
          // 📅 캘린더 영역
          Expanded(
          flex: _showCalendarFull ? 10 : 7,
            child: Column(
              children: [
                _buildCalendarHeader(),
                Expanded(
                  child: CalendarWidget(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    isGoingBack: _isGoingBack,
                    onDaySelected: (selectedDay, focusedDay) async {
                      setState(() {
                        _isGoingBack = focusedDay.isBefore(_focusedDay);
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                      await _loadTodosByDate(selectedDay);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // 📐 오른쪽 패널 / 사이드 레일
          if (_showCalendarFull)
            _buildCollapsedSideRail()
          else
            Expanded(
              flex: _showCalendarFull ? 0 : 3,
              child: _buildRightPanel(),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ✅ 오른쪽 패널 (투두 + 메모)
  Widget _buildRightPanel() {
    if (_showBoth) {
      // 둘 다 펼쳐진 기본 상태
      return Column(
        children: [
          Expanded(
            flex: 5,
            child: _buildTodoPanel(showBody: true),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 5,
            child: _buildMemoPanel(showBody: true),
          ),
        ],
      );
    } else if (_showTodoOnly) {
      // 메모만 접힘 → 투두가 오른쪽 전체, 메모 헤더는 아래
      return Column(
        children: [
          Expanded(
            flex: 10,
            child: _buildTodoPanel(showBody: true),
          ),
          const SizedBox(height: 4),
          _buildMemoPanel(showBody: false), // 헤더만
        ],
      );
    } else if (_showMemoOnly) {
      // 투두만 접힘 → 투두 헤더만 위, 메모가 오른쪽 전체
      return Column(
        children: [
          _buildTodoPanel(showBody: false), // 헤더만
          const SizedBox(height: 4),
          Expanded(
            flex: 10,
            child: _buildMemoPanel(showBody: true),
          ),
        ],
      );
    }

    // 이 경우는 _showCalendarFull에서 이미 처리됨
    return const SizedBox.shrink();
  }

  // ─────────────────────────────────────────────
  // ✅ 둘 다 접혔을 때: 오른쪽 얇은 세로 레일
  Widget _buildCollapsedSideRail() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);

    Widget buildRailButton({
      required String label,
      required VoidCallback onTap,
      IconData icon = Icons.view_list,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          buildRailButton(
            label: "To-do",
            icon: Icons.checklist,
            onTap: () {
              setState(() {
                _todoCollapsed = false;
              });
            },
          ),
          buildRailButton(
            label: "Memo",
            icon: Icons.notes,
            onTap: () {
              setState(() {
                _memoCollapsed = false;
              });
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ✅ 투두 패널 (헤더 + 본문)
  Widget _buildTodoPanel({required bool showBody}) {
    return Container(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      "To-do list",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "- ${_selectedDay.month}월 ${_selectedDay.day}일"
                      "${DateUtils.isSameDay(_selectedDay, DateTime.now()) ? " (오늘)" : ""}",
                      style: TextStyle(
                        fontSize: 15,
                        color: DateUtils.isSameDay(
                                _selectedDay, DateTime.now())
                            ? Colors.blueAccent
                            : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _todoCollapsed
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.blueAccent,
                      ),
                      onPressed: () {
                        setState(() => _todoCollapsed = !_todoCollapsed);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _sortTodosByTime,
                      icon: const Icon(FeatherIcons.clock, size: 18),
                      label: const Text("시간 순 정렬"),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_view_week,
                          color: Colors.blueAccent),
                      tooltip: "투두리스트 관리",
                      onPressed: () async {
                        await showDialog(
                          context: context,
                          builder: (context) => WeeklyTodoDialog(
                            onChanged: () async {
                              await _todoService.syncAllFromDialog();
                              await _loadTodosByDate(_selectedDay);
                            },
                          ),
                        );
                        await Future.delayed(
                            const Duration(milliseconds: 150));
                        await _loadTodosByDate(_selectedDay);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 본문
          if (showBody && !_todoCollapsed) ...[
            const SizedBox(height: 4),
            Expanded(child: _buildTodoList()),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
Widget _buildMemoPanel({required bool showBody}) {
  final theme = Theme.of(context);
  final titleStyle = theme.textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.w700,
    color: theme.colorScheme.onSurface,
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Text("Memo Pad", style: titleStyle),
            const Spacer(),
            IconButton(
              tooltip: _memoCollapsed ? "펼치기" : "접기",
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: Icon(
                _memoCollapsed
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
                color: theme.colorScheme.primary,
              ),
              onPressed: () =>
                  setState(() => _memoCollapsed = !_memoCollapsed),
            ),
          ],
        ),
      ),
      if (showBody && !_memoCollapsed)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: MemoPad(showInlineTitle: false),
          ),
        ),
    ],
  );
}


  // ─────────────────────────────────────────────
  // ✅ 달력 이동 기능
  void _goPrevMonth() {
    setState(() {
      _isGoingBack = true;
      _focusedDay =
          DateTime(_focusedDay.year, _focusedDay.month - 1, _focusedDay.day);
    });
  }

  void _goNextMonth() {
    setState(() {
      _isGoingBack = false;
      _focusedDay =
          DateTime(_focusedDay.year, _focusedDay.month + 1, _focusedDay.day);
    });
  }

  void _goToday() {
    setState(() {
      final now = DateTime.now();
      _isGoingBack = now.isBefore(_focusedDay);
      _focusedDay = now;
      _selectedDay = now;
    });
    _loadTodosByDate(DateTime.now()); // ✅ 오늘 기준 다시 로드
  }

  // ─────────────────────────────────────────────
  // ✅ 캘린더 헤더
  Widget _buildCalendarHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ⬅ 이전 달
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _goPrevMonth,
        ),

        // 🏠 오늘로 이동
        IconButton(
          icon: const Icon(Icons.home, color: Colors.blue),
          onPressed: _goToday,
        ),

        // 📅 현재 월 표시 + 클릭으로 선택
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _focusedDay,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDatePickerMode: DatePickerMode.year, // ✅ 연도부터 선택
            );

            if (picked != null) {
              setState(() {
                _focusedDay = DateTime(picked.year, picked.month, 1);
              });
            }
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                "${_focusedDay.year}. ${_focusedDay.month.toString().padLeft(2, '0')}.",
                key:
                    ValueKey("${_focusedDay.year}-${_focusedDay.month}"),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ),
        ),

        // ➡ 다음 달
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _goNextMonth,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // ✅ 투두 리스트 + 로딩 애니메이션
  Widget _buildTodoList() {
    final hasTodos = _todos.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isLoading
          ? const Center(key: ValueKey("loading"), child: LoadingText())
          : hasTodos
              ? TodoList(
                  key: ValueKey(
                    "todos-${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}",
                  ),
                  todos: _todos,
                  onTodosChanged: (updatedTodos) async {
                    setState(
                        () => _todos = List<Todo>.from(updatedTodos));
                    await _todoService.saveDailyState(
                        _selectedDay, updatedTodos);
                    if (kDebugMode) {
                      print(
                          "💾 ${_selectedDay.toIso8601String()} 순서 변경 저장됨");
                    }
                  },
                )
              : const Center(
                  key: ValueKey("empty"),
                  child: Text(
                    "오늘의 할 일이 없습니다 😊",
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────
// ✨ 로딩 텍스트 애니메이션 위젯
class LoadingText extends StatefulWidget {
  const LoadingText({super.key});

  @override
  State<LoadingText> createState() => _LoadingTextState();
}

class _LoadingTextState extends State<LoadingText>
    with SingleTickerProviderStateMixin {
  int _dotCount = 1;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _dotCount = _dotCount % 3 + 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: 1.0,
      child: Text(
        '오늘 하루를 준비하는 중${'.' * _dotCount}',
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }
}

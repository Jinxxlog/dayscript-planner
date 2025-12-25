import 'dart:io' if (dart.library.html) 'platform_stub.dart' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart'; // for isSameDay helper
import '../widgets/calendar_widget.dart';
import '../widgets/memo_pad.dart';
import '../services/todo_service.dart';
import '../widgets/todo_list.dart';
import '../models/todo.dart';
import '../widgets/weekly_todo_dialog.dart';
import '../multi_window.dart' show SettingsHomePage;
import '../services/sync_coordinator.dart';
import '../services/local_change_notifier.dart';
import '../widgets/ads/ad_floating_banner.dart';

class MobileHomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final Future<void> Function(String mode) onThemeChange;

  const MobileHomePage({
    super.key,
    required this.themeMode,
    required this.onThemeChange,
  });

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  int _currentIndex = 0;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final _sync = SyncCoordinator();

  @override
  void initState() {
    super.initState();
    _sync.startNetworkListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _sync.syncAll();
    });
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAd = _currentIndex != 3;
    final pages = [
      _CalendarTab(
        focusedDay: _focusedDay,
        selectedDay: _selectedDay,
        onDaySelected: _onDaySelected,
        onPageChanged: (fd) => setState(() => _focusedDay = fd),
      ),
      _TodoTab(
        selectedDay: _selectedDay,
        onSelectDay: (d) => setState(() => _selectedDay = d),
      ),
      const _MemoTab(),
      _SettingsTab(
        currentMode: widget.themeMode,
        onThemeChange: widget.onThemeChange,
      ),
    ];

    final items = const [
      BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: '캘린더'),
      BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'To-do'),
      BottomNavigationBarItem(icon: Icon(Icons.note_alt_outlined), label: '메모'),
      BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
    ];

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: pages,
                ),
              ),
              if (showAd) const AdFloatingBanner(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: items,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class _CalendarTab extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  const _CalendarTab({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  final prevMonth =
                      DateTime(focusedDay.year, focusedDay.month - 1, 1);
                  onDaySelected(prevMonth, prevMonth);
                },
              ),
              Column(
                children: [
                  Text(
                    "${focusedDay.year}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    "${focusedDay.month.toString().padLeft(2, '0')}월",
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final nextMonth =
                      DateTime(focusedDay.year, focusedDay.month + 1, 1);
                  onDaySelected(nextMonth, nextMonth);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: CalendarWidget(
            focusedDay: focusedDay,
            selectedDay: selectedDay,
            onDaySelected: onDaySelected,
            onPageChanged: onPageChanged,
            isGoingBack: false,
            compact: true,
            rowHeight: 95,
            useBottomSheetForMemo: false,
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _TodoTab extends StatefulWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  const _TodoTab({
    required this.selectedDay,
    required this.onSelectDay,
  });

  @override
  State<_TodoTab> createState() => _TodoTabState();
}

class _TodoTabState extends State<_TodoTab> {
  final _todoService = TodoService();
  List<Todo> _todos = [];
  late DateTime _weekStart;
  StreamSubscription<String>? _localSub;

  @override
  void initState() {
    super.initState();
    _weekStart = _getWeekStart(widget.selectedDay);
    _loadTodos(widget.selectedDay);
    _localSub ??= LocalChangeNotifier.stream.listen((area) async {
      if (!mounted) return;
      if (area == 'todos') {
        await _loadTodos(widget.selectedDay);
      }
    });
  }

  @override
  void dispose() {
    _localSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TodoTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _weekStart = _getWeekStart(widget.selectedDay);
      _loadTodos(widget.selectedDay);
    }
  }

  DateTime _getWeekStart(DateTime day) {
    final offset = day.weekday % 7; // Sunday=7 -> 0
    return DateTime(day.year, day.month, day.day - offset);
  }

  Future<void> _loadTodos(DateTime day) async {
    final list = await _todoService.loadDailyTodosMerged(day);
    if (!mounted) return;
    setState(() => _todos = list);
  }

  Future<void> _sortTodosByTime() async {
    int getGroupIndex(Todo t) {
      if (t.dueTime != null) {
        final hour = t.dueTime!.hour;
        if (hour < 8) return 1;
        if (hour < 12) return 2;
        if (hour < 18) return 3;
        return 4;
      }
      final txt = (t.textTime ?? "").trim();
      switch (txt) {
        case "아침":
        case "아침 ":
          return 1;
        case "점심":
          return 2;
        case "저녁":
          return 3;
        default:
          return 5;
      }
    }

    setState(() {
      _todos.sort((a, b) {
        final ai = getGroupIndex(a);
        final bi = getGroupIndex(b);
        if (ai != bi) return ai.compareTo(bi);
        if (a.dueTime != null && b.dueTime != null) {
          return a.dueTime!.compareTo(b.dueTime!);
        }
        if (a.dueTime != null) return -1;
        if (b.dueTime != null) return 1;
        return 0;
      });
    });
    await _todoService.saveDailyState(widget.selectedDay, _todos);
  }

  Future<void> _openWeeklyManage() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => WeeklyTodoDialog(
        onChanged: () => _loadTodos(widget.selectedDay),
      ),
    );
    await _loadTodos(widget.selectedDay);
    if (!mounted) return;
    if (result == 'added') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('투두가 추가되었습니다.')),
      );
    }
  }

  void _changeWeek(int delta) {
    final newDay = _weekStart.add(Duration(days: 7 * delta));
    final newSelected = newDay;
    setState(() {
      _weekStart = _getWeekStart(newSelected);
    });
    widget.onSelectDay(newSelected);
    _loadTodos(newSelected);
  }

  @override
  Widget build(BuildContext context) {
    final weekDays =
        List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final title =
        "${_weekStart.year}. ${_weekStart.month.toString().padLeft(2, '0')}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ?? ??: ?? ??? + ???
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeWeek(-1),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "To-do",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeWeek(1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                // ?? ??: ??/?? ??
                Positioned(
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: "??? ??",
                        icon: const Icon(Icons.access_time),
                        onPressed: _sortTodosByTime,
                      ),
                      IconButton(
                        tooltip: "?? ??",
                        icon: const Icon(Icons.build),
                        onPressed: _openWeeklyManage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 72,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: ListView.builder(
              key: ValueKey(_weekStart),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: weekDays.length,
              itemBuilder: (context, index) {
                final day = weekDays[index];
                final isSelected = isSameDay(day, widget.selectedDay);
                final isSunday = day.weekday % 7 == 0;
                final isSaturday = day.weekday == DateTime.saturday;
                final colorScheme = Theme.of(context).colorScheme;
                final labelColor = isSelected
                    ? colorScheme.primary
                    : isSunday
                        ? Colors.redAccent
                        : isSaturday
                            ? Colors.blueAccent
                            : colorScheme.onSurface;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () {
                      widget.onSelectDay(day);
                      _loadTodos(day);
                    },
                    child: Container(
                      width: 70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: colorScheme.primary, width: 1)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${day.month}/${day.day}",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: labelColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _weekdayLabel(day.weekday),
                            style: TextStyle(
                              fontSize: 12,
                              color: labelColor.withOpacity(isSelected ? 0.9 : 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TodoList(
            todos: _todos,
            onTodosChanged: (updated) async {
              setState(() => _todos = List<Todo>.from(updated));
              await _todoService.saveDailyState(widget.selectedDay, updated);
            },
          ),
        ),
      ],
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    return labels[weekday % 7];
  }
}

class _MemoTab extends StatelessWidget {
  const _MemoTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            'Memo Pad.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MemoPad(showInlineTitle: false),
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  final ThemeMode currentMode;
  final Future<void> Function(String mode) onThemeChange;

  const _SettingsTab({
    required this.currentMode,
    required this.onThemeChange,
  });

  @override
  Widget build(BuildContext context) {
    final authEnabled =
        Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    return SettingsHomePage(
      currentMode: currentMode,
      onThemeChange: (mode) => onThemeChange(mode.name),
      authEnabled: authEnabled,
    );
  }
}

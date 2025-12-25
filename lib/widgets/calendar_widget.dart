// lib/widgets/calendar_widget.dart

import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'dart:async';
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:table_calendar/table_calendar.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lunar/lunar.dart';

import '../models/recurring_event.dart';
import '../models/calendar_memo.dart';
import '../services/holiday_service.dart';
import '../services/calendar_data_service.dart';
import '../services/recurring_service.dart';
import '../services/memo_store.dart';
import '../services/local_change_notifier.dart';
import '../widgets/memo_side_sheet.dart';
import '../theme/custom_colors.dart';

// ─────────────────────────────────────────────
// 📅 CalendarWidget
// ─────────────────────────────────────────────
class CalendarWidget extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Function(DateTime, DateTime) onDaySelected;
  final VoidCallback? onHolidayAdded;
  final bool isGoingBack;
  final bool compact; // 모바일 소형 뷰 여부
  final bool useBottomSheetForMemo; // 모바일 메모 바텀시트 사용 여부
  final bool openMemoOnDayTap;
  final double? rowHeight;
  final ValueChanged<DateTime>? onPageChanged;

  const CalendarWidget({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    this.onHolidayAdded,
    this.isGoingBack = false,
    this.compact = false,
    this.useBottomSheetForMemo = false,
    this.openMemoOnDayTap = true,
    this.rowHeight,
    this.onPageChanged,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

// ─────────────────────────────────────────────
// 🔧 State
// ─────────────────────────────────────────────
class _CalendarWidgetState extends State<CalendarWidget> {
  // ─── 데이터 맵 ───
  Map<String, List<CalendarMemo>> _memos = {};
  Map<String, String> _holidays = {};
  Map<String, String> _icsHolidays = {};
  List<CustomHoliday> _customHolidays = [];
  List<RecurringEvent> _recurrings = [];
  final _calendarDataService = CalendarDataService();
  final _memoStore = CalendarMemoStore();

  // ─── 컨트롤러/서비스 ───
  final holidayService = HolidayService();
  final _recurringService = RecurringService();

  // ─── 상태 변수 ───
  bool _isDialogOpen = false;
  DateTime? _selectedDay;
  int _calendarVersion = 0; // TableCalendar 강제 리빌드용
  StreamSubscription<String>? _localSub;

  // 📝 사이드 메모 시트 상태
  bool _isMemoSheetOpen = false;
  DateTime? _memoSelectedDay;

  Color _parseColor(String hex, Color fallback) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xff')));
    } catch (_) {
      return fallback;
    }
  }

  // ─────────────────────────────────────────────
  // 🏁 초기화
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _selectedDay = widget.selectedDay ?? DateTime.now();
    _bootstrap();
    _localSub ??= LocalChangeNotifier.stream.listen((area) async {
      if (!mounted) return;
      switch (area) {
        case 'holidays':
          await _loadCustomHolidays();
          break;
        case 'recurring':
          await _recurringService.init();
          await _loadRecurringEvents();
          break;
        case 'memos':
          await _loadMemos();
          break;
      }
    });
  }

  @override
  void dispose() {
    _localSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await holidayService.init();
    await _recurringService.init();
    await _loadMemos();
    await _loadHolidays();
    await _loadCustomHolidays();
    await _loadRecurringEvents();
  }

  // ─────────────────────────────────────────────
  // 🗓 Date <-> Key 변환
  // ─────────────────────────────────────────────
  String _formatDateKey(DateTime date) =>
      "${date.year.toString().padLeft(4, '0')}-"
      "${date.month.toString().padLeft(2, '0')}-"
      "${date.day.toString().padLeft(2, '0')}";

  // ─────────────────────────────────────────────
  // 💾 메모 저장/로드
  // ─────────────────────────────────────────────
  Future<void> _saveMemos() async {
    await _memoStore.saveByDate(_memos);
  }

  Future<void> _loadMemos() async {
    final decoded = await _memoStore.loadByDate();

    if (!mounted) return;
    setState(() {
      _memos = decoded;
    });
  }

  Future<void> _clearAllMemos() async {
    final confirm = await _showConfirmDialog(
      title: "모든 메모 삭제",
      content: "정말로 모든 날짜의 메모를 삭제할까요?\n이 작업은 되돌릴 수 없어요.",
    );
    if (!confirm) return;

    setState(() {
      _memos.clear();
    });
    await _memoStore.saveByDate(_memos);
  }

  Future<void> _showMemoBottomSheet(DateTime day) async {
    final memos = _getMemos(day);
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    "${day.year}.${day.month}.${day.day}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (memos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    "메모가 없습니다.",
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: memos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final memo = memos[index];
                    return ListTile(
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _parseColor(
                              memo.color, colorScheme.primary),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: TextField(
                        controller:
                            TextEditingController(text: memo.text),
                        maxLines: null,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                        ),
                        onChanged: (v) {
                          _updateMemoForDay(
                              day, memo.copyWith(text: v));
                        },
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          _deleteMemoForDay(day, memo.id);
                          Navigator.pop(context);
                          _showMemoBottomSheet(day);
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: "새 메모 추가",
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      _addMemoForDay(day, text, '#FFA000');
                      controller.clear();
                      Navigator.pop(context);
                      _showMemoBottomSheet(day);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // 💾 사용자 정의 휴일 저장
  // ─────────────────────────────────────────────
  Future<void> _saveHolidays() async {
    debugPrint("💾 사용자 정의 휴일 저장 시작");
    final box = await Hive.openBox('custom_holidays');
    await box.clear();

    for (final h in _customHolidays) {
      await box.put(_formatDateKey(h.date), h.title);
    }

    debugPrint("✅ 사용자 정의 휴일 저장 완료 (${_customHolidays.length}건)");
  }

  bool isValidDate(int year, int month, int day) {
    final dt = DateTime(year, month, day);
    return dt.month == month && dt.day == day;
  }

  // ─────────────────────────────────────────────
  // 메모 조작 함수 (날짜별 N개)
// ─────────────────────────────────────────────
  void _addMemoForDay(DateTime day, String text, String color) {
    final key = _formatDateKey(day);
    final memo = CalendarMemo(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      createdAt: DateTime.now(),
      color: color,
      dateKey: key,
      updatedAt: DateTime.now(),
    );

    setState(() {
      final list = _memos[key] ?? [];
      list.add(memo);
      _memos[key] = list;
    });

    _saveMemos();
  }

  void _updateMemoForDay(DateTime day, CalendarMemo updated) {
    final key = _formatDateKey(day);
    final list = _memos[key];
    if (list == null) return;

    setState(() {
      final idx = list.indexWhere((m) => m.id == updated.id);
      if (idx != -1) {
        list[idx] = updated.copyWith(updatedAt: DateTime.now());
      }
    });

    _saveMemos();
  }

  void _deleteMemoForDay(DateTime day, String memoId) {
    final key = _formatDateKey(day);
    final list = _memos[key];
    if (list == null) return;

    setState(() {
      final idx = list.indexWhere((m) => m.id == memoId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(
          deleted: true,
          updatedAt: DateTime.now(),
        );
      }
    });

    _saveMemos();
  }

  List<CalendarMemo> _getMemos(DateTime day) {
    final key = _formatDateKey(day);
    final list = _memos[key] ?? const <CalendarMemo>[];
    return list.where((m) => m.deleted != true).toList();
  }

  // ─────────────────────────────────────────────
  // 📦 데이터 로드 (ICS / 휴일 / 반복 일정)
  // ─────────────────────────────────────────────
  Future<void> _loadHolidays() async {
    debugPrint("🔄 _loadHolidays() start");

    _icsHolidays.clear();
    _holidays.clear();

    // 1) ICS 로드
    final parsed = await _calendarDataService.loadIcsHolidays();
    if (parsed.isNotEmpty) {
      _icsHolidays.addAll(parsed);
      debugPrint("✅ ICS 휴일 로드 완료: ${_icsHolidays.length}건");
    }

    // 2) 사용자 지정 휴일
    await _loadCustomHolidays(rebuild: false);

    // 3) 통합
    final merged =
        _calendarDataService.mergeHolidays(_icsHolidays, _customHolidays);

    if (!mounted) return;
    setState(() {
      _holidays = merged;
      _calendarVersion++;
    });

    debugPrint("✅ HolidayService 동기화 완료 (ICS + 사용자 통합 ${_holidays.length}건)");
  }

  Future<void> _loadCustomHolidays({bool rebuild = true}) async {
    debugPrint("🔄 _loadCustomHolidays() from Hive start");
    await holidayService.init();

    final holidays = await holidayService.loadCustomHolidays();
    if (!mounted) return;
    setState(() {
      _customHolidays = holidays;
      if (rebuild) {
        _rebuildHolidayMap();
        _calendarVersion++;
      }
    });

    debugPrint("✅ 사용자 휴일 로드 완료: ${holidays.length}건");
    for (final h in holidays) {
      debugPrint("   • ${h.title} @ ${h.date.toIso8601String()}");
    }
  }

  void _rebuildHolidayMap() {
    final merged =
        _calendarDataService.mergeHolidays(_icsHolidays, _customHolidays);
    if (!mounted) return;
    setState(() => _holidays = merged);
  }

  Future<void> _loadRecurringEvents() async {
    if (!mounted) return;
    setState(() => _recurrings = _recurringService.getEvents());
  }

  // ─────────────────────────────────────────────
  // 반복 일정 헬퍼
  // ─────────────────────────────────────────────
  List<RecurringEvent> _recurringEventsFor(DateTime day) {
    final List<RecurringEvent> hits = [];
    for (final e in _recurrings) {
      if (_matchesRecurring(day, e)) hits.add(e);
    }
    hits.sort((a, b) => a.title.compareTo(b.title));
    return hits;
  }

  Color _recurringTextColorFor(RecurringEvent e) {
    final rule = (e.rule ?? '').toUpperCase();
    final isWeekly =
        e.cycleType == RecurringCycleType.weekly || rule.contains('FREQ=WEEKLY');
    final isMonthly = e.cycleType == RecurringCycleType.monthly ||
        rule.contains('FREQ=MONTHLY');
    final isYearly = e.cycleType == RecurringCycleType.yearly ||
        rule.contains('FREQ=YEARLY');

    if (isWeekly) return const Color(0xFF4FC3F7); // sky blue
    if (isMonthly) return const Color(0xFF1E88E5); // blue
    if (isYearly) return const Color(0xFF9575CD); // soft purple
    return const Color(0xFF2E7D32); // fallback
  }

  bool _matchesRecurring(DateTime day, RecurringEvent e) {
    final rule = (e.rule ?? '').toUpperCase();

    // WEEKLY
    if (rule.contains('FREQ=WEEKLY')) {
      final codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      final codeForDay = codes[day.weekday - 1];
      final m = RegExp(r'BYDAY=([A-Z,]+)').firstMatch(rule);
      if (m != null) {
        final list = m.group(1)!.split(',');
        return list.contains(codeForDay);
      }
      return false;
    }

    // MONTHLY
    if (rule.contains('FREQ=MONTHLY')) {
      final m = RegExp(r'BYMONTHDAY=([\d,]+)').firstMatch(rule);
      if (m != null) {
        final days = m.group(1)!.split(',').map(int.parse).toList();
        return days.contains(day.day);
      }
      return false;
    }

    // YEARLY (새 구조)
    if (e.cycleType == RecurringCycleType.yearly &&
        e.yearMonth != null &&
        e.yearDay != null) {
      if (e.isLunar == false) {
        return (day.month == e.yearMonth && day.day == e.yearDay);
      } else {
        try {
          final lunar = Lunar.fromYmd(day.year, e.yearMonth!, e.yearDay!);
          final solar = lunar.getSolar();
          return (day.month == solar.getMonth() &&
              day.day == solar.getDay());
        } catch (err) {
          debugPrint('음력 변환 오류: $err');
          return false;
        }
      }
    }

    if (e.cycleType == RecurringCycleType.daily) {
      return true;
    }

    if (e.cycleType == RecurringCycleType.weekly) {
      return day.weekday == e.startDate.weekday;
    }

    if (e.cycleType == RecurringCycleType.monthly) {
      return day.day == e.startDate.day;
    }

    return false;
  }

  String _formatRecurringEventTitle(RecurringEvent e) {
    final rule = e.rule ?? '';
    String details = "";

    if (rule.contains("FREQ=WEEKLY")) {
      final match = RegExp(r"BYDAY=([A-Z,]+)").firstMatch(rule);
      if (match != null) {
        final codes = match.group(1)!.split(",");
        const map = {
          "MO": "월",
          "TU": "화",
          "WE": "수",
          "TH": "목",
          "FR": "금",
          "SA": "토",
          "SU": "일",
        };
        final dayNames =
            codes.map((d) => map[d] ?? d).join(", ");
        details = "(매주 $dayNames)";
      } else {
        details = "(매주)";
      }
    } else if (rule.contains("FREQ=MONTHLY")) {
      final match = RegExp(r"BYMONTHDAY=([\d,]+)").firstMatch(rule);
      if (match != null) {
        final days = match.group(1)!.split(",");
        final formatted = days.map((d) => "${d}일").join(", ");
        details = "(매월 $formatted)";
      } else {
        details = "(매월)";
      }
    } else if (e.cycleType == RecurringCycleType.yearly) {
      final m = e.yearMonth ?? 1;
      final d = e.yearDay ?? 1;
      final lunarLabel = e.isLunar ? "음력" : "양력";
      details = "(매년 ${m}월 ${d}일, $lunarLabel)";
    } else {
      details = "(반복 주기 없음)";
    }

    return "${e.title} $details";
  }

  // ─────────────────────────────────────────────
  // 반복 일정 다이얼로그 (기존 코드 유지, 메모와 무관)
// ─────────────────────────────────────────────
  Future<void> _showRecurringDialog({RecurringEvent? event, int? index}) async {
    bool isLunar = false;
    int selectedMonth = 1;
    int selectedDay = 1;

    if (_isDialogOpen) return;
    setState(() => _isDialogOpen = true);
    final isEdit = event != null;
    final titleController =
        TextEditingController(text: event?.title ?? "");

    String frequency;
    if (event?.rule?.contains('FREQ=WEEKLY') == true) {
      frequency = 'WEEKLY';
    } else if (event?.rule?.contains('FREQ=MONTHLY') == true) {
      frequency = 'MONTHLY';
    } else if (event?.rule?.contains('FREQ=YEARLY') == true ||
        event?.cycleType == RecurringCycleType.yearly) {
      frequency = 'YEARLY';
    } else {
      frequency = 'WEEKLY';
    }
    Set<String> selectedDays = {};

    if (isEdit && event != null) {
      final rule = event.rule ?? '';
      if (frequency == 'WEEKLY') {
        final m =
            RegExp(r'BYDAY=([A-Z,]+)').firstMatch(rule.toUpperCase());
        if (m != null) {
          selectedDays = m.group(1)!.split(',').toSet();
        }
      } else if (frequency == 'MONTHLY') {
        final m =
            RegExp(r'BYMONTHDAY=([\d,]+)').firstMatch(rule);
        if (m != null) {
          selectedDays = m.group(1)!.split(',').toSet();
        }
      } else if (frequency == 'YEARLY') {
        selectedMonth = event.yearMonth ?? event.startDate.month;
        selectedDay = event.yearDay ?? event.startDate.day;
        isLunar = event.isLunar;
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? "반복 일정 수정" : "반복 일정 추가"),
          content: SizedBox(
            width: 520,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration:
                        const InputDecoration(labelText: "일정 이름"),
                  ),
                  const SizedBox(height: 10),
                  DropdownButton<String>(
                    value: frequency,
                    items: const [
                      DropdownMenuItem(
                          value: "WEEKLY", child: Text("주간")),
                      DropdownMenuItem(
                          value: "MONTHLY", child: Text("월간")),
                      DropdownMenuItem(
                          value: "YEARLY", child: Text("연간")),
                    ],
                    onChanged: (val) =>
                        setState(() => frequency = val!),
                  ),
                  const SizedBox(height: 10),

                  // WEEKLY
                  if (frequency == "WEEKLY") ...[
                    const Text("요일 선택",
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: ["월", "화", "수", "목", "금", "토", "일"]
                            .map((label) {
                          final index = ["월", "화", "수", "목", "금",
                            "토", "일"].indexOf(label);
                          final dayCode = [
                            "MO",
                            "TU",
                            "WE",
                            "TH",
                            "FR",
                            "SA",
                            "SU"
                          ][index];
                          final selected =
                              selectedDays.contains(dayCode);
                          final isDark =
                              Theme.of(context).brightness ==
                                  Brightness.dark;

                          return FilterChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            label: Text(label),
                            selected: selected,
                            selectedColor: Theme.of(context)
                                .colorScheme
                                .secondary,
                            labelStyle: TextStyle(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSecondary
                                  : (isDark
                                      ? Colors.white70
                                      : Colors.black87),
                            ),
                            backgroundColor: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.shade200,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  selectedDays.add(dayCode);
                                } else {
                                  selectedDays.remove(dayCode);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ]

                  // MONTHLY
                  else if (frequency == "MONTHLY") ...[
                    const Text("날짜 선택 (달력에서 선택)",
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    StatefulBuilder(
                      builder: (context, setInnerState) {
                        DateTime focusedMonth = DateTime.now();
                        Set<int> selectedDaysInMonth = selectedDays
                            .map((d) => int.tryParse(d) ?? 0)
                            .toSet();

                        return TableCalendar(
                          key: ValueKey(_calendarVersion),
                          headerVisible: true,
                          focusedDay: focusedMonth,
                          firstDay: DateTime(
                              focusedMonth.year,
                              focusedMonth.month,
                              1),
                          lastDay: DateTime(
                              focusedMonth.year,
                              focusedMonth.month + 1,
                              0),
                          rowHeight: 42,
                          headerStyle: const HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            selectedDecoration:
                                BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondary,
                              shape: BoxShape.circle,
                            ),
                            todayDecoration:
                                BoxDecoration(
                              color: Theme.of(context)
                                      .extension<CustomColors>()
                                      ?.calendarTodayFill ??
                                  Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              shape: BoxShape.circle,
                            ),
                          ),
                          selectedDayPredicate: (day) =>
                              selectedDaysInMonth
                                  .contains(day.day),
                          onDaySelected: (selectedDay, _) {
                            setInnerState(() {
                              if (selectedDaysInMonth
                                  .contains(selectedDay.day)) {
                                selectedDaysInMonth
                                    .remove(selectedDay.day);
                                selectedDays.remove(
                                    selectedDay.day.toString());
                              } else {
                                selectedDaysInMonth
                                    .add(selectedDay.day);
                                selectedDays.add(
                                    selectedDay.day.toString());
                              }
                            });
                          },
                        );
                      },
                    ),
                  ]

                  // YEARLY
                  else if (frequency == "YEARLY") ...[
                    const Text("날짜 선택",
                        style: TextStyle(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        DropdownButton<int>(
                          value: selectedMonth,
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child:
                                  Text('${i + 1}월'),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() =>
                                selectedMonth = val ?? 1);
                          },
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: selectedDay,
                          items: List.generate(
                            31,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child:
                                  Text('${i + 1}일'),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() =>
                                selectedDay = val ?? 1);
                          },
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text("기준",
                                style: TextStyle(
                                    fontWeight:
                                        FontWeight.w600)),
                            const SizedBox(height: 4),
                            ToggleButtons(
                              isSelected: [!isLunar, isLunar],
                              onPressed: (i) {
                                setState(() =>
                                    isLunar = (i == 1));
                              },
                              children: const [
                                Padding(
                                  padding: EdgeInsets
                                      .symmetric(
                                          horizontal: 8),
                                  child: Text("양력"),
                                ),
                                Padding(
                                  padding: EdgeInsets
                                      .symmetric(
                                          horizontal: 8),
                                  child: Text("음력"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const Divider(thickness: 1),
                  const Text(
                    "📋 기존 반복 일정",
                    style: TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  ValueListenableBuilder(
                    valueListenable:
                        Hive.box<RecurringEvent>(
                                RecurringService.boxName)
                            .listenable(),
                    builder: (context,
                        Box<RecurringEvent> box, _) {
                      final events = box.values
                          .where((e) => e.deleted != true)
                          .toList();

                      if (events.isEmpty) {
                        return const Text(
                            "등록된 반복 일정이 없습니다.");
                      }

                      return SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final e = events[index];
                            return ListTile(
                              dense: true,
                              contentPadding:
                                  EdgeInsets.zero,
                              title: Text(
                                  _formatRecurringEventTitle(
                                      e)),
                              trailing: Row(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        FeatherIcons
                                            .edit3,
                                        color:
                                            Colors.blue),
                                    onPressed:
                                        () async {
                                      Navigator.of(
                                              context)
                                          .pop();
                                      setState(() =>
                                          _isDialogOpen =
                                              false);
                                      await _showRecurringDialog(
                                          event: e,
                                          index:
                                              index);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        FeatherIcons
                                            .trash2,
                                        color: Colors
                                            .redAccent),
                                    onPressed:
                                        () async {
                                      final colorScheme =
                                          Theme.of(
                                                  context)
                                              .colorScheme;

                                      final confirm =
                                          await showDialog<
                                              bool>(
                                        context:
                                            context,
                                        builder: (context) =>
                                            AlertDialog(
                                          title:
                                              Row(
                                            children: const [
                                              Icon(
                                                  FeatherIcons
                                                      .alertTriangle,
                                                  color:
                                                      Colors.redAccent),
                                              SizedBox(
                                                  width:
                                                      8),
                                              Text(
                                                "일정 삭제",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                          content:
                                              Text(
                                            "‘${e.title}’ 일정을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
                                            style:
                                                const TextStyle(height: 1.4),
                                          ),
                                          actionsAlignment:
                                              MainAxisAlignment
                                                  .end,
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context,
                                                      false),
                                              style:
                                                  TextButton.styleFrom(
                                                foregroundColor:
                                                    colorScheme.outline,
                                              ),
                                              child:
                                                  const Text("취소"),
                                            ),
                                            FilledButton
                                                .icon(
                                              onPressed: () =>
                                                  Navigator.pop(context,
                                                      true),
                                              icon: const Icon(
                                                  FeatherIcons
                                                      .trash2,
                                                  size:
                                                      18),
                                              label:
                                                  const Text("삭제"),
                                              style:
                                                  ButtonStyle(
                                                backgroundColor:
                                                    MaterialStateProperty.resolveWith((states) {
                                                  if (states.contains(MaterialState.pressed)) {
                                                    return Colors
                                                        .red
                                                        .shade700;
                                                  }
                                                  return Colors
                                                      .redAccent;
                                                }),
                                                foregroundColor:
                                                    MaterialStateProperty.all(Colors.white),
                                                overlayColor:
                                                    MaterialStateProperty.all(Colors.red.withOpacity(0.2)),
                                                shadowColor:
                                                    MaterialStateProperty.all(Colors.transparent),
                                                elevation:
                                                    MaterialStateProperty.all(0),
                                                shape:
                                                    MaterialStateProperty.all(
                                                  RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(10),
                                                  ),
                                                ),
                                                padding:
                                                    MaterialStateProperty.all(
                                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                        if (confirm ==
                                            true) {
                                          await _recurringService
                                              .removeEventByEvent(e);
                                          await _loadRecurringEvents();
                                          setState(() =>
                                            _calendarVersion++);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final title =
                        titleController.text.trim();

                    if (title.isEmpty ||
                        (frequency != "YEARLY" &&
                            selectedDays
                                .isEmpty)) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                            content: Text(
                                "일정 이름과 날짜를 모두 입력해주세요.")),
                      );
                      return;
                    }

                    late RecurringCycleType
                        selectedCycleType;
                    switch (frequency) {
                      case "MONTHLY":
                        selectedCycleType =
                            RecurringCycleType
                                .monthly;
                        break;
                      case "YEARLY":
                        selectedCycleType =
                            RecurringCycleType
                                .yearly;
                        break;
                      default:
                        selectedCycleType =
                            RecurringCycleType
                                .weekly;
                        break;
                    }

                    if (selectedCycleType ==
                        RecurringCycleType
                            .yearly) {
                      if (!isValidDate(
                          DateTime.now().year,
                          selectedMonth,
                          selectedDay)) {
                        ScaffoldMessenger.of(
                                context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                                "❌ 잘못된 날짜입니다. 입력 값을 확인해주세요."),
                            backgroundColor:
                                Colors.redAccent,
                          ),
                        );
                        return;
                      }
                    }

                    final service =
                        RecurringService();

                    try {
                      if (selectedCycleType ==
                          RecurringCycleType
                              .weekly) {
                        const order = [
                          "MO",
                          "TU",
                          "WE",
                          "TH",
                          "FR",
                          "SA",
                          "SU"
                        ];
                        final sortedList =
                            selectedDays.toList()
                              ..sort((a, b) => order
                                  .indexOf(a)
                                  .compareTo(order
                                      .indexOf(
                                          b)));
                        selectedDays =
                            sortedList.toSet();
                      }

                      await service
                          .addEventWithInfo(
                        id: event?.id,
                        title: title,
                        cycleType:
                            selectedCycleType,
                        startDate: selectedCycleType ==
                                RecurringCycleType
                                    .weekly
                            ? _getNextDateFromSelectedDays(
                                selectedDays)
                            : null,
                        day: selectedCycleType ==
                                RecurringCycleType
                                    .monthly
                            ? null
                            : (selectedCycleType ==
                                    RecurringCycleType
                                        .yearly
                                ? (selectedDay ??
                                    DateTime.now()
                                        .day)
                                : null),
                        month: selectedCycleType ==
                                RecurringCycleType
                                    .yearly
                            ? (selectedMonth ??
                                DateTime.now()
                                    .month)
                            : null,
                        isLunar:
                            selectedCycleType ==
                                    RecurringCycleType
                                        .yearly
                                ? isLunar
                                : false,
                        color: Theme.of(context)
                            .colorScheme
                            .secondary,
                        byDays: selectedCycleType ==
                                RecurringCycleType
                                    .weekly
                            ? selectedDays
                                .map((d) => [
                                      "MO",
                                      "TU",
                                      "WE",
                                      "TH",
                                      "FR",
                                      "SA",
                                      "SU"
                                    ]
                                    .indexOf(d) +
                                    1)
                                .where((i) => i > 0)
                                .toList()
                            : null,
                        byMonthDays: selectedCycleType ==
                                RecurringCycleType
                                    .monthly
                            ? selectedDays
                                .map((d) =>
                                    int.tryParse(d) ??
                                    0)
                                .where((i) => i > 0)
                                .toList()
                            : null,
                      );

                      await _loadRecurringEvents();
                      setState(() {});

                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        SnackBar(
                          content: Text(
                              "‘$title’ 일정이 추가되었습니다."),
                          behavior: SnackBarBehavior
                              .floating,
                        ),
                      );
                    } catch (e) {
                      debugPrint(
                          "❌ 반복 일정 추가 오류: $e");
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        SnackBar(
                          content: Text(
                              "❌ 오류: ${e.toString()}"),
                          backgroundColor:
                              Colors.redAccent,
                          behavior:
                              SnackBarBehavior
                                  .floating,
                        ),
                      );
                    }

                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(
                      FeatherIcons.plus),
                  label: const Text("추가"),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context),
                  child: const Text("취소"),
                ),
              ],
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ─────────────────────────────────────────────
  // 사용자 휴일 추가 다이얼로그 (기존 그대로)
// ─────────────────────────────────────────────
  Future<void> _showAddCustomHolidayDialog() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    int filterIndex = 1;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            List<CustomHoliday> _filteredAndSorted() {
              final now = DateTime.now();
              final sorted = List<CustomHoliday>.from(
                  _customHolidays)
                ..sort((a, b) =>
                    a.date.compareTo(b.date));
              if (filterIndex == 0) return sorted;
              if (filterIndex == 1) {
                return sorted.where((h) => !h.date
                        .isBefore(DateTime(now.year,
                    now.month, now.day)))
                    .toList();
              }
              return sorted.where((h) => h.date
                  .isBefore(DateTime(
                      now.year,
                      now.month,
                      now.day))).toList();
            }

            return AlertDialog(
              backgroundColor: isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              title: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text('휴일 추가'),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.delete_forever,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    label: const Text(
                      '지정 휴일 전체 삭제',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13),
                    ),
                    onPressed: () async {
                      final confirm =
                          await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title:
                              const Text("지정 휴일 전체 삭제"),
                          content: const Text(
                              "모든 사용자 지정 휴일을 삭제하시겠습니까?"),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(
                                      context,
                                      false),
                              child: const Text("취소"),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(
                                      context,
                                      true),
                              child:
                                  const Text("삭제"),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await holidayService
                            .clearCustomHolidays();
                        await _loadCustomHolidays();
                        setState(() {});

                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                                "모든 공휴일이 삭제되었습니다."),
                            backgroundColor:
                                Colors.redAccent,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration:
                            const InputDecoration(
                          labelText: '휴일 이름',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("날짜 선택",
                          style: TextStyle(
                              fontWeight:
                                  FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: isDark
                                  ? Colors.white
                                      .withOpacity(0.1)
                                  : Colors.grey
                                      .shade300),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: TableCalendar(
                          key: ValueKey(
                              _calendarVersion),
                          headerVisible: true,
                          availableGestures:
                              AvailableGestures.all,
                          firstDay: DateTime.utc(
                              2000, 1, 1),
                          lastDay: DateTime.utc(
                              2100, 12, 31),
                          focusedDay: selectedDate,
                          selectedDayPredicate: (day) =>
                              isSameDay(
                                  day, selectedDate),
                          onDaySelected:
                              (selectedDay, _) =>
                                  setState(() =>
                                      selectedDate =
                                          selectedDay),
                          headerStyle:
                              const HeaderStyle(
                            formatButtonVisible:
                                false,
                            titleCentered: true,
                          ),
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: Theme.of(context)
                                      .extension<CustomColors>()
                                      ?.calendarTodayFill ??
                                  Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondary,
                              shape: BoxShape.circle,
                            ),
                            outsideDaysVisible: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          "선택된 날짜: ${selectedDate.year}-${selectedDate.month}-${selectedDate.day}",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : Colors
                                      .grey.shade800),
                        ),
                      ),
                      const Divider(height: 32),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                              value: 0,
                              label: Text('전체')),
                          ButtonSegment(
                              value: 1,
                              label: Text('예정')),
                          ButtonSegment(
                              value: 2,
                              label: Text('과거')),
                        ],
                        selected: <int>{filterIndex},
                        onSelectionChanged:
                            (newSet) {
                          setState(() =>
                              filterIndex =
                                  newSet.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text(
                            "📅 등록된 사용자 지정 휴일 (${_customHolidays.length}개)",
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.w600,
                              fontSize: 15,
                              color: isDark
                                  ? Colors.white
                                  : Colors
                                      .black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Builder(builder: (_) {
                        final filtered =
                            _filteredAndSorted();
                        if (filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets
                                .symmetric(
                                    vertical: 8),
                            child: Text(
                              "표시할 휴일이 없습니다.",
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13),
                            ),
                          );
                        }
                        return Column(
                          children:
                              filtered.map((h) {
                            final dateStr =
                                "${h.date.year}.${h.date.month.toString().padLeft(2, '0')}.${h.date.day.toString().padLeft(2, '0')}";
                            return ListTile(
                              dense: true,
                              contentPadding:
                                  EdgeInsets.zero,
                              title: Text(
                                "$dateStr  -  ${h.title.replaceFirst('(사용자) ', '')}",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors
                                          .white70
                                      : Colors
                                          .black87,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  FeatherIcons
                                      .trash2,
                                  color:
                                      Colors.redAccent,
                                ),
                                tooltip: "삭제",
                                onPressed:
                                    () async {
                                  final confirm =
                                      await showDialog<
                                          bool>(
                                    context:
                                        context,
                                    builder: (context) =>
                                        AlertDialog(
                                      backgroundColor:
                                          isDark
                                              ? const Color(
                                                  0xFF1E1E1E)
                                              : Colors
                                                  .white,
                                      title: Row(
                                        children: const [
                                          Icon(
                                              FeatherIcons
                                                  .alertTriangle,
                                              color:
                                                  Colors.redAccent),
                                          SizedBox(
                                              width:
                                                  8),
                                          Text(
                                            "휴일 삭제",
                                            style: TextStyle(
                                                fontWeight:
                                                    FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      content:
                                          Text(
                                        "‘${h.title.replaceFirst('(사용자) ', '')}’ 휴일을 삭제하시겠습니까?",
                                        style:
                                            TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      actionsAlignment:
                                          MainAxisAlignment
                                              .end,
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                              context,
                                              false),
                                          style: TextButton
                                              .styleFrom(
                                            foregroundColor:
                                                isDark
                                                    ? Colors.white70
                                                    : Colors.grey.shade700,
                                          ),
                                          child:
                                              const Text("취소"),
                                        ),
                                        FilledButton
                                            .icon(
                                          onPressed: () => Navigator.pop(
                                              context,
                                              true),
                                          icon: const Icon(
                                              FeatherIcons
                                                  .trash2,
                                              size:
                                                  18),
                                          label:
                                              const Text("삭제"),
                                          style:
                                              ButtonStyle(
                                            backgroundColor:
                                                MaterialStateProperty.resolveWith(
                                                    (states) {
                                              if (states.contains(
                                                  MaterialState
                                                      .pressed)) {
                                                return Colors
                                                    .red
                                                    .shade700;
                                              }
                                              return Colors
                                                  .redAccent;
                                            }),
                                            foregroundColor:
                                                MaterialStateProperty.all(
                                                    Colors.white),
                                            overlayColor:
                                                MaterialStateProperty.all(
                                                    Colors.red.withOpacity(0.2)),
                                            shape:
                                                MaterialStateProperty.all(
                                              RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm ==
                                      true) {
                                    await holidayService
                                        .removeHoliday(
                                            h.date);
                                    await _loadCustomHolidays();
                                    setState(() {});
                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            "‘${h.title}’ 휴일이 삭제되었습니다."),
                                        backgroundColor:
                                            Colors
                                                .redAccent,
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final title =
                            titleController.text
                                .trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(
                                  context)
                              .showSnackBar(
                            const SnackBar(
                                content: Text(
                                    "휴일 이름을 입력하세요.")),
                          );
                          return;
                        }

                        final holiday =
                            CustomHoliday(
                          date: selectedDate,
                          title: title,
                          color: "#FF0000",
                        );

                        await holidayService.init();
                        await holidayService
                            .addHoliday(holiday);
                        await _loadCustomHolidays();
                        setState(() {
                          _calendarVersion++;
                        });

                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          SnackBar(
                            content: Text(
                                "‘$title’ 휴일이 추가되었습니다."),
                            behavior:
                                SnackBarBehavior
                                    .floating,
                            duration:
                                const Duration(
                                    seconds: 2),
                          ),
                        );

                        titleController.clear();
                        setState(() {
                          selectedDate =
                              DateTime.now();
                        });
                      },
                      icon: const Icon(
                          FeatherIcons.plus,
                          size: 18),
                      label: const Text('추가'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            colorScheme.primary,
                        foregroundColor:
                            colorScheme.onPrimary,
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.white70
                            : Colors
                                .grey.shade700,
                      ),
                      child: const Text('취소'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  // ─────────────────────────────────────────────
  // 📅 캘린더 렌더링
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysOfWeekHeight = widget.compact ? 32.0 : 50.0;
    final desiredRowHeight =
        (widget.rowHeight ?? (widget.compact ? 80 : 160)).toDouble();

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(colorScheme),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxH = constraints.maxHeight;
                  final desiredTableHeight =
                      desiredRowHeight * 6.0 + daysOfWeekHeight;

                  final calendar = TableCalendar(
                key: ValueKey(_calendarVersion),
                headerVisible: false,
                firstDay: DateTime.utc(2000, 1, 1),
                lastDay: DateTime.utc(2100, 12, 31),
                focusedDay: widget.focusedDay,
                selectedDayPredicate: (day) =>
                    isSameDay(_selectedDay, day),
                onDaySelected:
                    (selectedDay, focusedDay) {
                  if (selectedDay.month !=
                      widget.focusedDay.month) {
                    return;
                  }

                  HapticFeedback.lightImpact();

                  widget.onDaySelected(selectedDay, focusedDay);
                  final shouldOpenMemo = widget.openMemoOnDayTap &&
                      (Platform.isAndroid || Platform.isIOS);

                  setState(() {
                    _selectedDay = selectedDay;
                    if (shouldOpenMemo) {
                      _memoSelectedDay = selectedDay;
                      // PC에서 자동으로 메모 사이드 시트를 열지 않도록 기본값은 닫힘 유지.
                      _isMemoSheetOpen = true;
                    }
                    _calendarVersion++;
                  });

                  if (shouldOpenMemo &&
                      widget.useBottomSheetForMemo) {
                    _showMemoBottomSheet(selectedDay);
                  }
                },
                rowHeight: desiredRowHeight,
                daysOfWeekHeight: daysOfWeekHeight,
                availableGestures:
                    AvailableGestures.horizontalSwipe,
                onPageChanged: (fd) {
                  setState(() {
                    _calendarVersion++;
                  });
                  widget.onPageChanged?.call(fd);
                },
                sixWeekMonthsEnforced: true,
                calendarStyle: CalendarStyle(
                  tableBorder: TableBorder.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant,
                    width: 0.5,
                  ),
                ),
                calendarBuilders: CalendarBuilders(
                  outsideBuilder:
                      (context, day, _) {
                    return AbsorbPointer(
                      child: Opacity(
                        opacity: 0.4,
                        child: _buildDayCell(
                          context,
                          day,
                          isOutside: true,
                        ),
                      ),
                    );
                  },
                  dowBuilder: _buildDayOfWeek,
                  defaultBuilder:
                      (context, day, _) =>
                          _buildDayCell(
                              context, day),
                  todayBuilder:
                      (context, day, _) =>
                          _buildDayCell(
                        context,
                        day,
                        isToday: true,
                      ),
                  selectedBuilder:
                      (context, day, _) =>
                          _buildDayCell(
                        context,
                        day,
                        isSelected: true,
                      ),
                ),
                  );

                  if (desiredTableHeight <= maxH) return calendar;
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: calendar,
                  );
                },
              ),
            ),
          ],
        ),

        // ─────────────────────────────────────
        // 📝 오른쪽 메모 사이드시트 + 슬라이드 애니메이션
        // ─────────────────────────────────────
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          right: _isMemoSheetOpen ? 0 : -420,
          child: (!_isMemoSheetOpen || _memoSelectedDay == null)
              ? const SizedBox.shrink()
              : MemoSideSheet(
                  selectedDay: _memoSelectedDay!,
                  memos: _getMemos(_memoSelectedDay!),
                  onAdd: (text, color) =>
                      _addMemoForDay(
                          _memoSelectedDay!, text, color),
                  onUpdate: (memo) =>
                      _updateMemoForDay(
                          _memoSelectedDay!, memo),
                  onDelete: (id) =>
                      _deleteMemoForDay(
                          _memoSelectedDay!, id),
                  onClose: () {
                    setState(() {
                      _isMemoSheetOpen = false;
                      _memoSelectedDay = null; // 블러/터치 차단 해제
                    });
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // 음력 표시
  // ─────────────────────────────────────────────
  String _convertToLunar(DateTime solar) {
    final lunar = Lunar.fromDate(solar);
    final month = lunar.getMonth();
    final day = lunar.getDay();
    String special = "";
    if (day == 15) {
      special = "🌕";
    }
    return "(음 $month.$day${special.isNotEmpty ? ' $special' : ''})";
  }

  // ─────────────────────────────────────────────
  // 날짜 셀 렌더링
  // ─────────────────────────────────────────────
  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
    bool isOutside = false,
  }) {
    if (widget.compact) {
      final key = _formatDateKey(day);
      final holiday = _holidays[key];
      final memos = _getMemos(day);
      final recurringEvents = _recurringEventsFor(day);
      final colorScheme = Theme.of(context).colorScheme;
      final custom = Theme.of(context).extension<CustomColors>();
      final isSunday = day.weekday == DateTime.sunday;
      final isSaturday = day.weekday == DateTime.saturday;
      final selected = isSameDay(day, _selectedDay);

      // Keep compact cells from overflowing when holiday/recurring/memos stack up.
      final showHoliday = holiday != null;
      final showRecurring = recurringEvents.isNotEmpty;
      const maxInfoLines = 3; // below the day number row
      var remainingInfoLines = maxInfoLines - (showHoliday ? 1 : 0);
      if (remainingInfoLines < 0) remainingInfoLines = 0;
      final recurringLimit = showRecurring
          ? (recurringEvents.length > remainingInfoLines
              ? remainingInfoLines
              : recurringEvents.length)
          : 0;

      var memoLimit = remainingInfoLines - recurringLimit;
      if (memoLimit < 0) memoLimit = 0;
      final hasMoreMemos = memos.length > memoLimit;
      final safeMemoLimit = memoLimit > memos.length ? memos.length : memoLimit;
      final lastShownMemo =
          safeMemoLimit > 0 ? memos[safeMemoLimit - 1] : null;

      Color textColor;
      if (isOutside) {
        textColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade600
            : Colors.grey.shade400;
      } else if (holiday != null || isSunday) {
        textColor = Colors.redAccent;
      } else if (isSaturday) {
        textColor = Colors.blueAccent;
      } else {
        textColor = colorScheme.onSurface;
      }

      Color bgColor = Colors.transparent;
      if (selected) {
        bgColor = custom?.calendarSelectedFill ??
            colorScheme.primaryContainer.withOpacity(0.35);
      } else if (isToday || isSameDay(day, DateTime.now())) {
        bgColor = custom?.calendarTodayFill ??
            colorScheme.primary.withOpacity(0.12);
      } else if (holiday != null || isSunday) {
        bgColor = Colors.redAccent.withOpacity(0.06);
      } else if (isSaturday) {
        bgColor = Colors.blueAccent.withOpacity(0.06);
      }

      return Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 0.4,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "${day.day}",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                if (memos.isNotEmpty) ...[
                  const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
                if (recurringEvents.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            if (holiday != null)
              Text(
                holiday.replaceFirst("(사용자) ", ""),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: holiday.startsWith("(사용자)")
                    ? Colors.deepOrange
                    : Colors.red,
                ),
              ),
            ...recurringEvents.take(recurringLimit).map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: _recurringTextColorFor(e),
                  ),
                ),
              ),
            ),
            ...memos.take(memoLimit).map((m) {
              final txt = m.text;
              if (txt.isEmpty) return const SizedBox.shrink();
              var preview = txt.length > 4 ? "${txt.substring(0, 4)}..." : txt;
              if (hasMoreMemos && lastShownMemo != null && m == lastShownMemo) {
                preview = "$preview...";
              }
              final c = _parseColor(m.color, colorScheme.primary);
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: c,
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }

    final key = _formatDateKey(day);
    final holiday = _holidays[key];
    final recurringEvents = _recurringEventsFor(day);
    final colorScheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<CustomColors>();

    final isSunday = day.weekday == DateTime.sunday;
    final isSaturday = day.weekday == DateTime.saturday;
    final memos = _getMemos(day);

    Color textColor;
    if (isOutside) {
      textColor = Theme.of(context).brightness ==
              Brightness.dark
          ? Colors.grey.shade600
          : Colors.grey.shade400;
    } else if (holiday != null || isSunday) {
      textColor = Colors.redAccent;
    } else if (isSaturday) {
      textColor = Colors.blueAccent;
    } else {
      textColor = colorScheme.onBackground;
    }

    Color bgColor = Colors.transparent;

    if (isOutside) {
      final bool isDark =
          Theme.of(context).brightness ==
              Brightness.dark;
      bgColor = isDark
          ? Colors.blueGrey.withOpacity(0.1)
          : const Color(0xFFE4E9F4)
              .withOpacity(0.3);
    } else if (isSelected ||
        isSameDay(day, _selectedDay)) {
      bgColor = custom?.calendarSelectedFill ??
          colorScheme.primaryContainer.withOpacity(0.7);
    } else if (isToday ||
        isSameDay(day, DateTime.now())) {
      bgColor = custom?.calendarTodayFill ??
          colorScheme.primary.withOpacity(0.12);
    } else if (holiday != null || isSunday) {
      bgColor = Colors.redAccent.withOpacity(0.08);
    } else if (isSaturday) {
      bgColor = Colors.blueAccent.withOpacity(0.08);
    }

    Widget inner = Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
        color: bgColor,
      ),
      padding: const EdgeInsets.all(6),
      alignment: Alignment.topLeft,
      child: Stack(
        children: [
          // ---- 날짜/휴일/메모 정보는 Column으로 묶기 ----
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "${day.day}",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _convertToLunar(day),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),

              if (holiday != null)
                Text(
                  holiday.replaceFirst("(사용자) ", ""),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: holiday.startsWith("(사용자)")
                        ? Colors.deepOrange
                        : Colors.red,
                  ),
                ),

              if (recurringEvents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: recurringEvents.map((e) {
                      return Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _recurringTextColorFor(e),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              if (memos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: memos.take(3).map((memo) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                color: _parseColor(memo.color,
                                    Theme.of(context).colorScheme.primary),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                memo.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),

          // ---- 펜 버튼을 Stack의 상단에 Positioned로 배치 ----
          if (!widget.compact &&
              day.month == widget.focusedDay.month)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _memoSelectedDay = day;
                    _selectedDay = day;
                    _isMemoSheetOpen = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    FeatherIcons.edit3,
                    size: 15,
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (isSameDay(day, _selectedDay)) {
      inner = inner
          .animate(
            onPlay: (controller) =>
                controller.forward(from: 0),
          )
          .scale(
            duration: 250.ms,
            begin: const Offset(0.92, 0.92),
            end: const Offset(1.0, 1.0),
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 150.ms);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) async {
        final target = _customHolidays.firstWhere(
          (h) =>
              h.date.year == day.year &&
              h.date.month == day.month &&
              h.date.day == day.day,
          orElse: () => CustomHoliday(
              date: DateTime(1900),
              title: "",
              color: ""),
        );
        if (target.title.isEmpty) return;

        final colorScheme =
            Theme.of(context).colorScheme;
        final isDark =
            Theme.of(context).brightness ==
                Brightness.dark;

        final confirm =
            await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            title: Row(
              children: const [
                Icon(
                  FeatherIcons.alertTriangle,
                  color: Colors.redAccent,
                ),
                SizedBox(width: 8),
                Text(
                  "사용자 지정 휴일 삭제",
                  style: TextStyle(
                      fontWeight:
                          FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              "‘${target.title.replaceFirst("(사용자) ", "")}’ 휴일을 삭제하시겠습니까?",
              style: TextStyle(
                color: isDark
                    ? Colors.white70
                    : Colors.black87,
                height: 1.4,
              ),
            ),
            actionsAlignment:
                MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                        context, false),
                style: TextButton.styleFrom(
                  foregroundColor:
                      colorScheme.outline,
                ),
                child: const Text("취소"),
              ),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(
                        context, true),
                icon: const Icon(
                    FeatherIcons.trash2,
                    size: 18),
                label: const Text("삭제"),
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStateProperty
                          .resolveWith(
                              (states) {
                    if (states.contains(
                        MaterialState
                            .pressed)) {
                      return Colors
                          .red.shade700;
                    }
                    return Colors
                        .redAccent;
                  }),
                  foregroundColor:
                      MaterialStateProperty.all(
                          Colors.white),
                  overlayColor:
                      MaterialStateProperty.all(
                          Colors.red
                              .withOpacity(
                                  0.2)),
                  shadowColor:
                      MaterialStateProperty.all(
                          Colors
                              .transparent),
                  elevation:
                      MaterialStateProperty.all(
                          0),
                  shape:
                      MaterialStateProperty
                          .all(
                    RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                              10),
                    ),
                  ),
                  padding:
                      MaterialStateProperty
                          .all(
                    const EdgeInsets
                        .symmetric(
                            horizontal: 16,
                            vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await holidayService.removeHoliday(day);
          await _loadCustomHolidays();
          ScaffoldMessenger.of(context)
              .showSnackBar(
            SnackBar(
              content: Text(
                  "‘${target.title.replaceFirst("(사용자) ", "")}’ 휴일이 삭제되었습니다."),
              backgroundColor:
                  Colors.redAccent,
              behavior:
                  SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: inner,
    );
  }

  // ─────────────────────────────────────────────
  // 헤더 툴바
  // ─────────────────────────────────────────────
  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Calendar",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  FeatherIcons.plus,
                  color: colorScheme.primary,
                ),
                tooltip: "휴일 추가",
                onPressed: _showAddCustomHolidayDialog,
              ),
              IconButton(
                icon: Icon(
                  Icons.autorenew,
                  color: colorScheme.secondary,
                ),
                tooltip: "반복 일정 추가",
                onPressed: _showRecurringDialog,
              ),
              IconButton(
                icon: Icon(
                  FeatherIcons.trash2,
                  color: colorScheme.error,
                ),
                tooltip: "모든 메모 삭제",
                onPressed: _clearAllMemos,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 요일 렌더러
  // ─────────────────────────────────────────────
  Widget _buildDayOfWeek(BuildContext context, DateTime day) {
    final isSunday = day.weekday == DateTime.sunday;
    final isSaturday = day.weekday == DateTime.saturday;
    final text = ['일', '월', '화', '수', '목', '금', '토']
        [day.weekday % 7];
    final color = isSunday
        ? Colors.red
        : isSaturday
            ? Colors.blue
            : Theme.of(context)
                .colorScheme
                .onBackground;
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // WEEKLY 시작 날짜 계산
  // ─────────────────────────────────────────────
  DateTime _getNextDateFromSelectedDays(
      Set<String> selectedDays) {
    if (selectedDays.isEmpty) {
      return DateTime.now();
    }
    const codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
    final firstDayCode = selectedDays.first;
    final today = DateTime.now();
    final todayWeekday = today.weekday;
    final targetWeekday =
        codes.indexOf(firstDayCode) + 1;
    int diff = targetWeekday - todayWeekday;
    if (diff < 0) diff += 7;
    return today.add(Duration(days: diff));
  }
}

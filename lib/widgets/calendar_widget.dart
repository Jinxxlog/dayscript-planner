import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart'; // ✅ 꼭 추가!
import 'package:lunar/lunar.dart';
import 'package:flutter/cupertino.dart';

import '../models/recurring_event.dart';
import '../services/holiday_service.dart';
import '../services/recurring_service.dart';


// ─────────────────────────────────────────────
// 📅 CalendarWidget
// ─────────────────────────────────────────────
class CalendarWidget extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Function(DateTime, DateTime) onDaySelected;
  final VoidCallback? onHolidayAdded;
  final bool isGoingBack;

  const CalendarWidget({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    this.onHolidayAdded,
    this.isGoingBack = false,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

// ─────────────────────────────────────────────
// 🔧 State
// ─────────────────────────────────────────────
class _CalendarWidgetState extends State<CalendarWidget> {

  // ─── 데이터 맵 ───
  Map<String, String> _events = {};
  Map<String, String> _holidays = {};
  Map<String, String> _icsHolidays = {};
  List<CustomHoliday> _customHolidays = [];
  List<RecurringEvent> _recurrings = [];

  // ─── 컨트롤러/서비스 ───
  final Map<String, TextEditingController> _controllers = {};
  final holidayService = HolidayService();
  final _recurringService = RecurringService();

  // ─── 상태 변수 ───
  Timer? _saveDebounce;
  String? _editingKey;
  bool _isDialogOpen = false;
  DateTime? _selectedDay;
  Offset _lastTapPosition = Offset.zero;
  Set<DateTime> _selectedDays = {};
  int _calendarVersion = 0; // state에 추가

  // ─────────────────────────────────────────────
  // 🏁 초기화
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _selectedDay = widget.selectedDay ?? DateTime.now();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
  await holidayService.init();           // ✅ 먼저 박스 오픈
  await _loadEvents();
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
  // 💾 저장 관련 함수
  // ─────────────────────────────────────────────
  Future<void> _saveEventsDebounced() async {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("calendar_events", json.encode(_events));
    });
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("calendar_events", json.encode(_events));
  }

  /// 사용자 지정 휴일 저장 (HolidayService 연동)
  Future<void> _saveHolidays() async {
    debugPrint("💾 사용자 정의 휴일 저장 시작");
    final box = await Hive.openBox('custom_holidays');
    await box.clear(); // 기존 사용자 휴일 덮어쓰기

    for (final h in _customHolidays) {
      await box.put(_formatDateKey(h.date), h.title);
    }

    debugPrint("✅ 사용자 정의 휴일 저장 완료 (${_customHolidays.length}건)");
  }

  bool isValidDate(int year, int month, int day) {
    final dt = DateTime(year, month, day);

    // month/day가 입력과 다르면 → 자동 보정된 것 → 잘못된 날짜
    return dt.month == month && dt.day == day;
  }



  // ─────────────────────────────────────────────
  // 📦 데이터 로드
  // ─────────────────────────────────────────────
  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString("calendar_events");
    if (jsonString == null) return;
    setState(() => _events = Map<String, String>.from(json.decode(jsonString)));
  }

  /// 📅 ICS 문자열을 파싱하여 <"YYYY-MM-DD", "휴일명"> 형태로 반환
  Map<String, String> _parseICS(String icsContent) {
    final Map<String, String> holidays = {};

    // ✅ ICS 한 줄씩 파싱
    final lines = icsContent.split(RegExp(r'\r?\n'));
    String? summary;
    DateTime? date;

    for (final line in lines) {
      if (line.startsWith("SUMMARY:")) {
        // 예: SUMMARY:노동절
        summary = line.replaceFirst("SUMMARY:", "").trim();
      } else if (line.startsWith("DTSTART")) {
        // 예: DTSTART;VALUE=DATE:20250505 → 날짜 추출
        final match = RegExp(r':(\d{8})').firstMatch(line);
        if (match != null) {
          final raw = match.group(1)!;
          final year = int.parse(raw.substring(0, 4));
          final month = int.parse(raw.substring(4, 6));
          final day = int.parse(raw.substring(6, 8));
          date = DateTime(year, month, day);
        }
      } else if (line.startsWith("END:VEVENT")) {
        // ✅ 이벤트 하나 완성 시 holidays에 추가
        if (summary != null && date != null) {
          final key = _formatDateKey(date);
          holidays[key] = summary;
          summary = null;
          date = null;
        }
      }
    }

    debugPrint("📘 ICS 파싱 완료 (${holidays.length}건)");
    return holidays;
  }

  Future<void> _loadHolidays() async {
    debugPrint("🔄 _loadHolidays() start");

    _icsHolidays.clear();
    _holidays.clear();

    // ✅ 1. ICS (assets/basic.ics) 로드 → 메모리 전용
    try {
      final ics = await rootBundle.loadString('assets/basic.ics');
      final parsed = _parseICS(ics); // 네가 이미 구현한 ICS 파서
      _icsHolidays.addAll(parsed);
      debugPrint("✅ ICS 휴일 로드 완료: ${_icsHolidays.length}건");
    } catch (e) {
      debugPrint("❌ ICS 로드 실패: $e");
    }

    // ✅ 2. 사용자 정의 휴일만 Hive에서 불러오기
    await _loadCustomHolidays();

    // ✅ 3. 통합 (ICS + 사용자)
    _holidays = {
      ..._icsHolidays,
      ...{for (final h in _customHolidays) _formatDateKey(h.date): h.title},
    };

    debugPrint("✅ HolidayService 동기화 완료 (ICS + 사용자 통합 ${_holidays.length}건)");
    setState(() {});
  }


  Future<void> _loadCustomHolidays() async {
    debugPrint("🔄 _loadCustomHolidays() from Hive start");
    await holidayService.init(); // 안전하게 보강

    final holidays = await holidayService.loadCustomHolidays(); // ✅ 비동기 호출로 교체
    setState(() {
      _customHolidays = holidays;
      _rebuildHolidayMap();     // ics + custom merge
      _calendarVersion++;       // TableCalendar 강제 리빌드
    });

    debugPrint("✅ 사용자 휴일 로드 완료: ${holidays.length}건");
    for (final h in holidays) {
      debugPrint("   • ${h.title} @ ${h.date.toIso8601String()}");
    }
  }

  void _rebuildHolidayMap() {
    final merged = Map<String, String>.from(_icsHolidays);
    for (final h in _customHolidays) {
      final key = _formatDateKey(h.date);
      merged[key] = h.title;
    }
    setState(() => _holidays = merged);
  }

  Future<void> _loadRecurringEvents() async {
    setState(() => _recurrings = _recurringService.getEvents());
  }


    // ─────────────────────────────────────────────
    // 🧹 전체 메모 삭제
    // ─────────────────────────────────────────────
    Future<void> _clearEvents() async {
      final colorScheme = Theme.of(context).colorScheme;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: const [
              Icon(FeatherIcons.alertTriangle, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                '모든 메모 삭제',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            '⚠️ 정말로 모든 메모를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.end, // ✅ 오른쪽 정렬
          actions: [
            // ✅ 왼쪽: 취소 버튼
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent, // 살짝 흐린 회색
              ),
              child: const Text('취소'),
            ),

            // ✅ 오른쪽: 삭제 버튼 (강조)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(FeatherIcons.trash2, size: 18),
              label: const Text('영구 삭제'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("calendar_events");

      setState(() {
        _events.clear();
        _controllers.values.forEach((c) => c.dispose());
        _controllers.clear();
        _editingKey = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🗑️ 모든 메모가 완전히 삭제되었습니다."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }





  /// 📍 마우스 클릭 위치 → 해당 날짜 계산 (실제 셀 단위로 변환)
  DateTime? _hitTestDay(Offset globalPosition) {
    // TableCalendar의 RenderBox를 얻음
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final local = box.globalToLocal(globalPosition);
    final size = box.size;

    // 달력 전체 크기에서 셀 크기 계산 (7열 × 6행 기준)
    final cellWidth = size.width / 7;
    final cellHeight = (size.height - 50) / 6; // 50은 요일 헤더 높이

    final col = (local.dx / cellWidth).floor();
    final row = ((local.dy - 50) / cellHeight).floor(); // 헤더 아래부터 계산

    if (col < 0 || col > 6 || row < 0 || row > 5) return null;

    // 현재 focusedDay 기준으로 달력 첫 날짜 계산
    final firstOfMonth = DateTime(widget.focusedDay.year, widget.focusedDay.month, 1);
    final firstWeekday = firstOfMonth.weekday % 7; // 일요일=0
    final firstCellDate = firstOfMonth.subtract(Duration(days: firstWeekday));

    // 클릭한 셀의 날짜
    final clickedDate = firstCellDate.add(Duration(days: row * 7 + col));
    return clickedDate;
  }



  // ─────────────────────────────────────────────
  List<String> _recurringTitlesFor(DateTime day) {
    final List<String> hits = [];
    for (final e in _recurrings) {
      if (_matchesRecurring(day, e)) hits.add(e.title);
    }
    return hits;
  }

  bool _matchesRecurring(DateTime day, RecurringEvent e) {
    final rule = (e.rule ?? '').toUpperCase();

    // ──────────────────────────────
    // 1️⃣ RRULE 기반 WEEKLY 반복
    // ──────────────────────────────
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

    // ──────────────────────────────
    // 2️⃣ RRULE 기반 MONTHLY 반복
    // ──────────────────────────────
    if (rule.contains('FREQ=MONTHLY')) {
      final m = RegExp(r'BYMONTHDAY=([\d,]+)').firstMatch(rule);
      if (m != null) {
        final days = m.group(1)!.split(',').map(int.parse).toList();
        return days.contains(day.day);
      }
      return false;
    }

    // ──────────────────────────────
    // 3️⃣ 새 구조: YEARLY (양력/음력)
    // ──────────────────────────────
    if (e.cycleType == RecurringCycleType.yearly &&
        e.yearMonth != null &&
        e.yearDay != null) {
      if (e.isLunar == false) {
        // 🌞 양력 기준
        return (day.month == e.yearMonth && day.day == e.yearDay);
      } else {
        // 🌙 음력 기준 → 변환 필요
        // lunar_calendar_converter 패키지 사용 가정
          try {
          // day.year 기준으로 해당 해의 음력 날짜를 양력으로 변환
          final lunar = Lunar.fromYmd(day.year, e.yearMonth!, e.yearDay!);
          final solar = lunar.getSolar();
          return (day.month == solar.getMonth() && day.day == solar.getDay());
        } catch (err) {
          debugPrint('음력 변환 오류: $err');
          return false;
        }
      }
    }

    // ──────────────────────────────
    // 4️⃣ (옵션) 일간/주간/월간 확장 대응
    // ──────────────────────────────
    if (e.cycleType == RecurringCycleType.daily) {
      return true; // 매일
    }

    if (e.cycleType == RecurringCycleType.weekly) {
      return day.weekday == e.startDate.weekday;
    }

    if (e.cycleType == RecurringCycleType.monthly) {
      return day.day == e.startDate.day;
    }

    // 기본값: 매칭 안 됨
    return false;
  }


  // ─────────────────────────────────────────────

  /// ✅ 반복 일정의 제목을 보기 좋게 포맷팅
  String _formatRecurringEventTitle(RecurringEvent e) {
    final rule = e.rule ?? '';
    String details = "";

    // ──────────────── WEEKLY
    if (rule.contains("FREQ=WEEKLY")) {
      final match = RegExp(r"BYDAY=([A-Z,]+)").firstMatch(rule);
      if (match != null) {
        final codes = match.group(1)!.split(",");
        const map = {
          "MO": "월", "TU": "화", "WE": "수",
          "TH": "목", "FR": "금", "SA": "토", "SU": "일",
        };
        final dayNames = codes.map((d) => map[d] ?? d).join(", ");
        details = "(매주 $dayNames)";
      } else {
        details = "(매주)";
      }
    }

    // ──────────────── MONTHLY
    else if (rule.contains("FREQ=MONTHLY")) {
      final match = RegExp(r"BYMONTHDAY=([\d,]+)").firstMatch(rule);
      if (match != null) {
        final days = match.group(1)!.split(",");
        final formatted = days.map((d) => "${d}일").join(", ");
        details = "(매월 $formatted)";
      } else {
        details = "(매월)";
      }
    }

    // ──────────────── YEARLY
    else if (e.cycleType == RecurringCycleType.yearly) {
      final m = e.yearMonth ?? 1;
      final d = e.yearDay ?? 1;
      final lunarLabel = e.isLunar ? "음력" : "양력";
      details = "(매년 ${m}월 ${d}일, $lunarLabel)";
    }

    // ──────────────── 기본값
    else {
      details = "(반복 주기 없음)";
    }

    return "${e.title} $details";
  }
 
  Future<void> _showRecurringDialog({RecurringEvent? event, int? index}) async {
  bool isLunar = false;      // 🌕 양력/음력 여부
  int selectedMonth = 1;     // 선택된 월
  int selectedDay = 1;       // 선택된 일
  
  if (_isDialogOpen) return; // 이미 열려 있으면 실행하지 않음
  setState(() => _isDialogOpen = true);
  final isEdit = event != null;
  final titleController = TextEditingController(text: event?.title ?? "");

  String frequency;
  if (event?.rule?.contains('FREQ=WEEKLY') == true) {
    frequency = 'WEEKLY';
  } else if (event?.rule?.contains('FREQ=MONTHLY') == true) {
    frequency = 'MONTHLY';
  } else if (event?.rule?.contains('FREQ=YEARLY') == true ||
            event?.cycleType == RecurringCycleType.yearly) {
    frequency = 'YEARLY';
  } else {
    frequency = 'WEEKLY'; // 기본값
  }
  Set<String> selectedDays = {};

  // ✅ 기존 데이터 파싱
  if (isEdit && event != null) {
    final rule = event.rule ?? ''; // ✅ null-safe

    if (frequency == 'WEEKLY') {
      final m = RegExp(r'BYDAY=([A-Z,]+)').firstMatch(rule.toUpperCase());
      if (m != null) {
        selectedDays = m.group(1)!.split(',').toSet();
      }
    } else if (frequency == 'MONTHLY') {
      final m = RegExp(r'BYMONTHDAY=([\d,]+)').firstMatch(rule);
      if (m != null) {
        selectedDays = m.group(1)!.split(',').toSet();
      }
    }
  }
    await showDialog(
    
      context: context,
      barrierDismissible: true, // ✅ 바깥 클릭으로 닫기 허용
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? "반복 일정 수정" : "반복 일정 추가"),
          content: SizedBox(
            width: 520,
            height: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: "일정 이름"),
                  ),
                  const SizedBox(height: 10),

                  // 반복 주기 선택
                  DropdownButton<String>(
                    value: frequency,
                    items: const [
                      DropdownMenuItem(value: "WEEKLY", child: Text("주간")),
                      DropdownMenuItem(value: "MONTHLY", child: Text("월간")),
                      DropdownMenuItem(value: "YEARLY", child: Text("연간")),
                    ],
                    onChanged: (val) => setState(() => frequency = val!),
                  ),

                  const SizedBox(height: 10),

                  // ✅ 주간 반복 UI
                  if (frequency == "WEEKLY") ...[
                    const Text("요일 선택", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    // ✅ 요일 선택 (더 깔끔한 디자인)
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: ["월", "화", "수", "목", "금", "토", "일"].map((label) {
                          final index = ["월", "화", "수", "목", "금", "토", "일"].indexOf(label);
                          final dayCode = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][index];
                          final selected = selectedDays.contains(dayCode);

                          final isDark = Theme.of(context).brightness == Brightness.dark;

                          return FilterChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            label: Text(label),
                            selected: selected,
                            selectedColor: Colors.indigoAccent,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
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

                  // ✅ 월간 반복 UI
                  else if (frequency == "MONTHLY") ...[
                    const Text("날짜 선택 (달력에서 선택)", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    StatefulBuilder(
                      builder: (context, setInnerState) {
                        DateTime focusedMonth = DateTime.now();
                        Set<int> selectedDaysInMonth =
                            selectedDays.map((d) => int.tryParse(d) ?? 0).toSet();

                        return TableCalendar(
                          key: ValueKey(_calendarVersion), // ✅ 리빌드 트리거
                          headerVisible: true,
                          focusedDay: focusedMonth,
                          firstDay: DateTime(focusedMonth.year, focusedMonth.month, 1),
                          lastDay: DateTime(focusedMonth.year, focusedMonth.month + 1, 0),
                          rowHeight: 42,
                          headerStyle: const HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            selectedDecoration: const BoxDecoration(
                              color: Color(0xFF6495ED),
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: const BoxDecoration(
                              color: Color(0xFFB4C7E7),
                              shape: BoxShape.circle,
                            ),
                          ),
                          selectedDayPredicate: (day) =>
                              selectedDaysInMonth.contains(day.day),
                          onDaySelected: (selectedDay, _) {
                            setInnerState(() {
                              if (selectedDaysInMonth.contains(selectedDay.day)) {
                                selectedDaysInMonth.remove(selectedDay.day);
                                selectedDays.remove(selectedDay.day.toString());
                              } else {
                                selectedDaysInMonth.add(selectedDay.day);
                                selectedDays.add(selectedDay.day.toString());
                              }
                            });
                          },
                        );
                      },
                    ),
                  ]

                  // ✅ 연간 반복 UI (휠 + 양력/음력 토글)
                  else if (frequency == "YEARLY") ...[
                    const Text("날짜 선택", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 월 선택
                        DropdownButton<int>(
                          value: selectedMonth,
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}월'),
                            ),
                          ),
                          onChanged: (val) {
                            // ✅ 바깥 setState 사용 (innerSetState 아님)
                            setState(() => selectedMonth = val ?? 1);
                          },
                        ),
                        const SizedBox(width: 12),

                        // 일 선택
                        DropdownButton<int>(
                          value: selectedDay,
                          items: List.generate(
                            31,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}일'),
                            ),
                          ),
                          onChanged: (val) {
                            // ✅ 바깥 setState 사용
                            setState(() => selectedDay = val ?? 1);
                          },
                        ),

                        const SizedBox(width: 16),

                        // 🌕 양력/음력 선택
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("기준", style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            ToggleButtons(
                              isSelected: [!isLunar, isLunar],
                              onPressed: (i) {
                                // ✅ 바깥 setState 사용
                                setState(() => isLunar = (i == 1));
                              },
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text("양력"),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
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
                  const Text("📋 기존 반복 일정",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),

                  ValueListenableBuilder(
                    valueListenable: Hive.box<RecurringEvent>('recurring_events').listenable(),
                    builder: (context, Box<RecurringEvent> box, _) {
                      final events = box.values.toList().cast<RecurringEvent>();

                      if (events.isEmpty) {
                        return const Text("등록된 반복 일정이 없습니다.");
                      }

                      return SizedBox(
                        height: 200,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final e = events[index];
                            final rule = e.rule ?? '';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_formatRecurringEventTitle(e)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(FeatherIcons.edit3, color: Colors.blue),
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      setState(() => _isDialogOpen = false);
                                      await _showRecurringDialog(event: e, index: index);
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(FeatherIcons.trash2, color: Colors.redAccent),
                                    tooltip: "삭제",
                                    onPressed: () async {
                                      final colorScheme = Theme.of(context).colorScheme;

                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Row(
                                            children: const [
                                              Icon(FeatherIcons.alertTriangle, color: Colors.redAccent),
                                              SizedBox(width: 8),
                                              Text("일정 삭제", style: TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          content: Text(
                                            "‘${e.title}’ 일정을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
                                            style: const TextStyle(height: 1.4),
                                          ),
                                          actionsAlignment: MainAxisAlignment.end,
                                          actions: [
                                            // 🔹 취소 버튼 (회색 계열)
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              style: TextButton.styleFrom(
                                                foregroundColor: colorScheme.outline, // 라이트/다크 자동 대응
                                                textStyle: const TextStyle(fontWeight: FontWeight.w500),
                                              ),
                                              child: const Text("취소"),
                                            ),

                                            // 🔸 삭제 버튼 (강조)
                                              FilledButton.icon(
                                                onPressed: () => Navigator.pop(context, true),
                                                icon: const Icon(FeatherIcons.trash2, size: 18),
                                                label: const Text("삭제"),
                                                style: ButtonStyle(
                                                  backgroundColor: MaterialStateProperty.resolveWith((states) {
                                                    if (states.contains(MaterialState.pressed)) {
                                                      return Colors.red.shade700; // 눌렀을 때 조금 어둡게
                                                    }
                                                    return Colors.redAccent; // 기본 진한 붉은색
                                                  }),
                                                  foregroundColor: MaterialStateProperty.all(Colors.white),
                                                  overlayColor: MaterialStateProperty.all(Colors.red.withOpacity(0.2)), // 눌렀을 때 효과
                                                  shadowColor: MaterialStateProperty.all(Colors.transparent),
                                                  elevation: MaterialStateProperty.all(0),
                                                  shape: MaterialStateProperty.all(
                                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                  ),
                                                  padding: MaterialStateProperty.all(
                                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                  ),
                                                ),
                                              ),

                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        final box = Hive.box<RecurringEvent>('recurring_events');
                                        await box.deleteAt(index); // 🔹 해당 인덱스 삭제
                                        await _loadRecurringEvents(); // ✅ 즉시 반영
                                        setState(() => _calendarVersion++); // ✅ 캘린더 리빌드 트리거

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("‘${e.title}’ 일정이 삭제되었습니다."),
                                            backgroundColor: Colors.redAccent,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
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
          // ✅ 하단 버튼 (추가 → 취소 순서)
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final title = titleController.text.trim();

                    // 기본 입력 체크
                    if (title.isEmpty ||
                        (frequency != "YEARLY" && selectedDays.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("일정 이름과 날짜를 모두 입력해주세요.")),
                      );
                      return;
                    }

                    // 반복 타입 판별
                    late RecurringCycleType selectedCycleType;
                    switch (frequency) {
                      case "MONTHLY":
                        selectedCycleType = RecurringCycleType.monthly;
                        break;
                      case "YEARLY":
                        selectedCycleType = RecurringCycleType.yearly;
                        break;
                      default:
                        selectedCycleType = RecurringCycleType.weekly;
                        break;
                    }

                    // ⛔ YEARLY일 때 날짜 유효성 검사 추가!!
                    if (selectedCycleType == RecurringCycleType.yearly) {
                      if (!isValidDate(DateTime.now().year, selectedMonth, selectedDay)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("❌ 잘못된 날짜입니다. 입력 값을 확인해주세요."),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return; // 추가 중단
                      }
                    }

                    final service = RecurringService();

                    try {
                      // 🟦 주간 정렬 (월 → 일)
                      if (selectedCycleType == RecurringCycleType.weekly) {
                        const order = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
                        final sortedList = selectedDays.toList()
                          ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
                        selectedDays = sortedList.toSet();
                      }

                      // 이벤트 추가
                      await service.addEventWithInfo(
                        title: title,
                        cycleType: selectedCycleType,
                        startDate: selectedCycleType == RecurringCycleType.weekly
                            ? _getNextDateFromSelectedDays(selectedDays)
                            : null,
                        day: selectedCycleType == RecurringCycleType.monthly
                            ? null
                            : (selectedCycleType == RecurringCycleType.yearly
                                ? (selectedDay ?? DateTime.now().day)
                                : null),
                        month: selectedCycleType == RecurringCycleType.yearly
                            ? (selectedMonth ?? DateTime.now().month)
                            : null,
                        isLunar: selectedCycleType == RecurringCycleType.yearly ? isLunar : false,
                        color: Colors.indigo,
                        byDays: selectedCycleType == RecurringCycleType.weekly
                            ? selectedDays
                                .map((d) => ["MO", "TU", "WE", "TH", "FR", "SA", "SU"].indexOf(d) + 1)
                                .where((i) => i > 0)
                                .toList()
                            : null,
                        byMonthDays: selectedCycleType == RecurringCycleType.monthly
                            ? selectedDays
                                .map((d) => int.tryParse(d) ?? 0)
                                .where((i) => i > 0)
                                .toList()
                            : null,
                      );

                      await _loadRecurringEvents();
                      setState(() {});

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("‘$title’ 일정이 추가되었습니다."),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );

                    } catch (e) {
                      print("❌ 반복 일정 추가 오류: $e");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("❌ 오류: ${e.toString()}"),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }

                    // 닫기
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  icon: const Icon(FeatherIcons.plus),
                  label: const Text("추가"),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey.shade700,
                    textStyle: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  child: const Text("취소"),
                ),
              ],
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // ✅ 어떤 이유로든 닫힐 때 무조건 false 복원
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.black)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // 🎨 사용자 정의 휴일 추가 다이얼로그
  Future<void> _showAddCustomHolidayDialog() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    int filterIndex = 1; // 0 = 전체, 1 = 예정, 2 = 과거

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // ✅ 정렬 + 필터 함수
            List<CustomHoliday> _filteredAndSorted() {
              final now = DateTime.now();
              final sorted = List<CustomHoliday>.from(_customHolidays)
                ..sort((a, b) => a.date.compareTo(b.date));
              if (filterIndex == 0) return sorted;
              if (filterIndex == 1) {
                return sorted.where((h) =>
                    !h.date.isBefore(DateTime(now.year, now.month, now.day))).toList();
              }
              return sorted.where((h) =>
                  h.date.isBefore(DateTime(now.year, now.month, now.day))).toList();
            }

            return AlertDialog(
              backgroundColor: isDark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('휴일 추가'),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 18),
                    label: const Text(
                      '지정 휴일 전체 삭제',
                      style: TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("지정 휴일 전체 삭제"),
                          content: const Text("모든 사용자 지정 휴일을 삭제하시겠습니까?"),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("취소"),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("삭제"),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await holidayService.clearCustomHolidays(); // ✅ 한 번에 날림
                        await _loadCustomHolidays();
                        setState(() {});

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("모든 공휴일이 삭제되었습니다."),
                            backgroundColor: Colors.redAccent,
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ 휴일 이름 입력
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: '휴일 이름',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("날짜 선택",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      // ✅ 달력
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TableCalendar(
                          key: ValueKey(_calendarVersion),
                          headerVisible: true,
                          availableGestures: AvailableGestures.all,
                          firstDay: DateTime.utc(2000, 1, 1),
                          lastDay: DateTime.utc(2100, 12, 31),
                          focusedDay: selectedDate,
                          selectedDayPredicate: (day) => isSameDay(day, selectedDate),
                          onDaySelected: (selectedDay, _) =>
                              setState(() => selectedDate = selectedDay),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                          ),
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: Colors.blue.shade200,
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Colors.blue.shade400,
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
                              fontWeight: FontWeight.w500,
                              color:
                                  isDark ? Colors.white70 : Colors.grey.shade800),
                        ),
                      ),
                      const Divider(height: 32),

                      // ✅ 필터 버튼
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('전체')),
                          ButtonSegment(value: 1, label: Text('예정')),
                          ButtonSegment(value: 2, label: Text('과거')),
                        ],
                        selected: <int>{filterIndex},
                        onSelectionChanged: (newSet) {
                          setState(() => filterIndex = newSet.first);
                        },
                        style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.selected)) {
                              return isDark
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.blue.shade50;
                            }
                            return Colors.transparent;
                          }),
                          foregroundColor:
                              MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.selected)) {
                              return isDark ? Colors.white : Colors.blueAccent;
                            }
                            return isDark ? Colors.white70 : Colors.black87;
                          }),
                          side: MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.selected)) {
                              return BorderSide(
                                color: isDark
                                    ? Colors.white.withOpacity(0.25)
                                    : Colors.blueAccent.withOpacity(0.4),
                                width: 1.2,
                              );
                            }
                            return BorderSide(
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.black.withOpacity(0.1),
                            );
                          }),
                          shape: MaterialStateProperty.all(
                            RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "📅 등록된 사용자 지정 휴일 (${_customHolidays.length}개)",
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // ✅ 리스트
                      Builder(builder: (_) {
                        final filtered = _filteredAndSorted();
                        if (filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text("표시할 휴일이 없습니다.",
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                          );
                        }
                        return Column(
                          children: filtered.map((h) {
                            final dateStr =
                                "${h.date.year}.${h.date.month.toString().padLeft(2, '0')}.${h.date.day.toString().padLeft(2, '0')}";
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                "$dateStr  -  ${h.title.replaceFirst('(사용자) ', '')}",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(FeatherIcons.trash2,
                                    color: Colors.redAccent),
                                tooltip: "삭제",
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: isDark
                                          ? const Color(0xFF1E1E1E)
                                          : Colors.white,
                                      title: Row(
                                        children: const [
                                          Icon(FeatherIcons.alertTriangle,
                                              color: Colors.redAccent),
                                          SizedBox(width: 8),
                                          Text("휴일 삭제",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      content: Text(
                                        "‘${h.title.replaceFirst('(사용자) ', '')}’ 휴일을 삭제하시겠습니까?",
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      actionsAlignment: MainAxisAlignment.end,
                                      actions: [
                                        // 취소
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          style: TextButton.styleFrom(
                                            foregroundColor: isDark
                                                ? Colors.white70
                                                : Colors.grey.shade700,
                                          ),
                                          child: const Text("취소"),
                                        ),
                                        // 삭제
                                        FilledButton.icon(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          icon: const Icon(FeatherIcons.trash2,
                                              size: 18),
                                          label: const Text("삭제"),
                                          style: ButtonStyle(
                                            backgroundColor:
                                                MaterialStateProperty.resolveWith(
                                                    (states) {
                                              if (states
                                                  .contains(MaterialState.pressed)) {
                                                return Colors.red.shade700;
                                              }
                                              return Colors.redAccent;
                                            }),
                                            foregroundColor:
                                                MaterialStateProperty.all(
                                                    Colors.white),
                                            overlayColor:
                                                MaterialStateProperty.all(
                                                    Colors.red.withOpacity(0.2)),
                                            shape: MaterialStateProperty.all(
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

                                  if (confirm == true) {
                                    await holidayService.removeHoliday(h.date);
                                    await _loadCustomHolidays();
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            "‘${h.title}’ 휴일이 삭제되었습니다."),
                                        backgroundColor: Colors.redAccent,
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

              // ✅ 하단 버튼 (추가 → 취소 순서)
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("휴일 이름을 입력하세요.")),
                          );
                          return;
                        }

                        final holiday = CustomHoliday(
                          date: selectedDate,
                          title: title,
                          color: "#FF0000",
                        );

                        await holidayService.init();
                        await holidayService.addHoliday(holiday);
                        await _loadCustomHolidays();

                        setState(() {
                          _calendarVersion++;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("‘$title’ 휴일이 추가되었습니다."),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );

                        titleController.clear();
                        setState(() {
                          selectedDate = DateTime.now();
                        });
                      },
                      icon: const Icon(FeatherIcons.plus, size: 18),
                      label: const Text('추가'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor:
                            isDark ? Colors.white70 : Colors.grey.shade700,
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



  /// 🖱 우클릭 시 사용자 정의 휴일 삭제 
  Future<void> _onRightClick(DateTime date) async {
    final key = _formatDateKey(date);

    // ✅ ICS 휴일은 삭제 금지
    final isCustom = _customHolidays.any((h) => _formatDateKey(h.date) == key);
    if (!isCustom) {
      debugPrint("🛑 ICS 휴일은 삭제 불가 ($key)");
      return;
    }

    // ✅ 사용자 휴일 삭제
    _customHolidays.removeWhere((h) => _formatDateKey(h.date) == key);
    await _saveHolidays();

    // ✅ 화면 반영
    setState(() {
      _holidays.remove(key);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("해당 휴일이 삭제되었습니다."),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );

    debugPrint("🗑 사용자 지정 휴일 삭제 완료: $key");
  }

  /// ✏️ 더블클릭 시 메모 수정 
  Future<void> _onDoubleClick(DateTime date) async { 
    final key = _formatDateKey(date); setState(() => _editingKey = key); 
    }

  // ─────────────────────────────────────────────
  // 📅 캘린더 렌더링
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 상단 툴바
        _buildHeader(colorScheme),

        // 메인 캘린더
        Expanded(
          child: Stack(
            children: [
              TableCalendar(
                key: ValueKey(_calendarVersion), // ✅ 강제 리빌드 트리거
                headerVisible: false,
                firstDay: DateTime.utc(2000, 1, 1),
                lastDay: DateTime.utc(2100, 12, 31),
                focusedDay: widget.focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  if (selectedDay.month != widget.focusedDay.month) return;

                  setState(() {
                    _selectedDay = selectedDay;
                    _calendarVersion++; // ✅ TableCalendar 강제 리빌드 → 녹색 반복 일정 표시 보장
                  });

                  widget.onDaySelected(selectedDay, focusedDay);
                },

                rowHeight: 160,
                daysOfWeekHeight: 50,

                // ✅ 달마다 주 수가 달라도 항상 6줄 유지
                sixWeekMonthsEnforced: true,

              
                calendarStyle: CalendarStyle(
                  tableBorder: TableBorder.all(
                    color: const Color.fromARGB(255, 208, 229, 255),
                    width: 0.5,
                  ),
                ),
                calendarBuilders: CalendarBuilders(
                  outsideBuilder: (context, day, _) {
                    // 이전/다음 달 날짜 (회색 표시 + 클릭 불가)
                    return AbsorbPointer( // 🚫 클릭 이벤트 차단
                      child: Opacity(
                        opacity: 0.4, // 살짝 흐리게 (UI 유지)
                        child: _buildDayCell(context, day, isOutside: true),
                      ),
                    );
                  },
                  
                  dowBuilder: _buildDayOfWeek, // 요일 헤더 그대로 유지

                  // ✅ 일반 날짜
                  defaultBuilder: (context, day, _) =>
                      _buildDayCell(context, day),

                  // ✅ 오늘 날짜 강조
                  todayBuilder: (context, day, _) =>
                      _buildDayCell(context, day, isToday: true),

                  // ✅ 선택된 날짜 강조
                  selectedBuilder: (context, day, _) =>
                      _buildDayCell(context, day, isSelected: true),


                ),
              ),

            // 🟩 투명 클릭 레이어
              // ✅ 투명 클릭 레이어 (더블클릭 / 우클릭 / 단일 클릭 모두 안전하게 동작)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) async {
                    // 🔹 마우스 오른쪽 클릭 시 → 사용자 휴일 삭제
                    if (event.kind == PointerDeviceKind.mouse &&
                        event.buttons == kSecondaryMouseButton) {
                      final date = _hitTestDay(event.position);
                      if (date != null) await _onRightClick(date);
                      return;
                    }

                    // 🔹 왼쪽 클릭 시 (단일/더블클릭 구분)
                    if (event.kind == PointerDeviceKind.mouse &&
                        event.buttons == kPrimaryMouseButton) {
                      final date = _hitTestDay(event.position);

                      // ✅ 더블클릭 시 메모창 오픈
                      if (event.down && event.buttons == kPrimaryMouseButton && event.timeStamp < const Duration(milliseconds: 300)) {
                        // (Flutter가 native 더블클릭 인식 안해서 직접 처리)
                        if (date != null) {
                          setState(() => _selectedDay = date);
                          await _onDoubleClick(date);
                          debugPrint("🟦 [DEBUG] 더블클릭 - 메모창 열림, 날짜 이동: $_selectedDay");
                        }
                      } else {
                        // ✅ 일반 클릭: 메모창 닫기 + 포커스 해제
                        if (_editingKey != null) {
                          setState(() => _editingKey = null);
                          FocusScope.of(context).unfocus();
                          debugPrint("🧩 [DEBUG] 일반 클릭 - 메모창 닫힘 및 포커스 해제");
                        }
                      }
                    }
                  },
                ),
              ),




            ],
          ),
        ),
      ],
    );
  }


  String _convertToLunar(DateTime solar) { 
    final lunar = Lunar.fromDate(solar); 
    final month = lunar.getMonth(); 
    final day = lunar.getDay(); String special = ""; 
    
    if (day == 15) { special = "🌕"; // 보름 표시 
    } 
    
    // "(음 9.15)" 또는 "(음 9.15 🌕)" 형식으로 반환 
    return "(음 $month.$day${special.isNotEmpty ? ' $special' : ''})"; 
  }


  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
    bool isOutside = false,
  }) {
    final key = _formatDateKey(day);
    _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _events[key] ?? ""),
    );

    final controller = _controllers[key]!;
    final notifier = ValueNotifier<String>(_events[key] ?? "");
    final holiday = _holidays[key];
    final recurringTitles = _recurringTitlesFor(day);
    final colorScheme = Theme.of(context).colorScheme;

    final isSunday = day.weekday == DateTime.sunday;
    final isSaturday = day.weekday == DateTime.saturday;
    final today = DateTime.now();

  // ✅ 글자색
  Color textColor;
  if (isOutside) {
    // 🔹 이전/다음 달 → 흐릿하게 + 낮은 명도
    textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade600
        : Colors.grey.shade400;
  } else if (holiday != null || isSunday) {
    textColor = Colors.redAccent;
  } else if (isSaturday) {
    textColor = Colors.blueAccent;
  } else {
    textColor = colorScheme.onBackground;
  }

  // ✅ 배경색 + 테두리 (블러 느낌)
  Color bgColor = Colors.transparent;
  Color borderColor = Colors.transparent;

  if (isOutside) {
    // 🔹 이번 달이 아닌 날짜 → 반투명+살짝 음영+연한 테두리 (블러 느낌)
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bgColor = isDark
        ? Colors.blueGrey.withOpacity(0.1)
        : const Color(0xFFE4E9F4).withOpacity(0.3);
    borderColor = isDark
        ? const Color(0xFFE4E9F4).withOpacity(0.3)
        : Colors.blueGrey.withOpacity(0.1);
  } else if (isSameDay(day, widget.selectedDay)) {
    bgColor = colorScheme.primaryContainer.withOpacity(0.7);
  } else if (isSameDay(day, DateTime.now())) {
    bgColor = colorScheme.primary.withOpacity(0.12);
  } else if (holiday != null || isSunday) {
    bgColor = Colors.redAccent.withOpacity(0.1);
  } else if (isSaturday) {
    bgColor = Colors.blueAccent.withOpacity(0.1);
  }

return ValueListenableBuilder<String>(
  valueListenable: notifier,
  builder: (context, value, _) {
    Widget inner = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // ✅ 클릭 시 날짜 선택 + 진동
        HapticFeedback.lightImpact();
        widget.onDaySelected(day, widget.focusedDay);
        debugPrint("👉 클릭 (${_formatDateKey(day)}) → onDaySelected 전달 완료");
      },
      onSecondaryTapDown: (details) async {
        final target = _customHolidays.firstWhere(
          (h) =>
              h.date.year == day.year &&
              h.date.month == day.month &&
              h.date.day == day.day,
          orElse: () => CustomHoliday(date: DateTime(1900), title: "", color: ""),
        );
        if (target.title.isEmpty) return;

        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark
                ? const Color(0xFF1E1E1E) // 다크모드용 배경
                : Colors.white,
            title: Row(
              children: const [
                Icon(FeatherIcons.alertTriangle, color: Colors.redAccent),
                SizedBox(width: 8),
                Text("사용자 지정 휴일 삭제",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "‘${target.title.replaceFirst("(사용자) ", "")}’ 휴일을 삭제하시겠습니까?",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              // 🔹 취소 버튼 (테마 자동 대응)
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.outline, // ✅ 다크/라이트 모두 자연스럽게
                  textStyle: const TextStyle(fontWeight: FontWeight.w500),
                ),
                child: const Text("취소"),
              ),

              // 🔸 삭제 버튼 (강조)
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(FeatherIcons.trash2, size: 18),
                label: const Text("삭제"),
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.pressed)) {
                      return Colors.red.shade700; // 눌렀을 때 약간 어둡게
                    }
                    return Colors.redAccent;
                  }),
                  foregroundColor: MaterialStateProperty.all(Colors.white),
                  overlayColor:
                      MaterialStateProperty.all(Colors.red.withOpacity(0.2)),
                  shadowColor: MaterialStateProperty.all(Colors.transparent),
                  elevation: MaterialStateProperty.all(0),
                  shape: MaterialStateProperty.all(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  padding: MaterialStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await holidayService.removeHoliday(day);
          await _loadCustomHolidays();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text("‘${target.title.replaceFirst("(사용자) ", "")}’ 휴일이 삭제되었습니다."),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },

      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400, width: 0.5),
          color: bgColor,
        ),
        padding: const EdgeInsets.all(6),
        alignment: Alignment.topLeft,
        child: Stack(
          children: [
            // 🔹 본문 내용
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
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),

                // 휴일
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

                // 반복 일정
                if (recurringTitles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      recurringTitles.join("\n"),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // ✅ 메모가 존재할 경우
                if (value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
              ],
            ),

            // 🔹 선택된 날짜에만 ✏️버튼 표시
            if (isSameDay(day, widget.selectedDay))
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    HapticFeedback.lightImpact(); // ✅ 메모 버튼 클릭 시도 진동
                    final result = await _showMemoDialog(context, day, controller);
                    if (result != null) notifier.value = result;
                  },
                  child: const Icon(
                    FeatherIcons.edit3,
                    size: 20,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // ✅ 선택된 날짜 클릭 시 "톡" 확대 애니메이션
    if (isSameDay(day, widget.selectedDay)) {
      inner = inner
          .animate(
            onPlay: (controller) => controller.forward(from: 0),
          )
          .scale(
            duration: 250.ms,
            begin: const Offset(0.92, 0.92),
            end: const Offset(1.0, 1.0),
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 150.ms);
    }

    return inner;
  },
);
  }

  Future<String?> _showMemoDialog(
    BuildContext context,
    DateTime day,
    TextEditingController controller,
  ) async {
    final tempController = TextEditingController(text: controller.text);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 다이얼로그 닫힐 때 최종적으로 저장 처리
    String? lastText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true, // ✅ 바깥 클릭 가능
      builder: (context) {
        return WillPopScope( // 뒤로가기 / 바깥 클릭 감지
          onWillPop: () async {
            lastText = tempController.text.trim(); // ✅ 닫힐 때 자동 저장용
            return true;
          },
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            title: Text("${day.month}.${day.day} 메모"),
            content: TextField(
              controller: tempController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "메모를 입력하세요...",
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              // ✅ 적용 버튼
              FilledButton(
                onPressed: () {
                  Navigator.pop(context, tempController.text.trim());
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text("적용"),
              ),

              // ✅ 취소 버튼
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                style: TextButton.styleFrom(
                  foregroundColor:
                      isDark ? Colors.white70 : Colors.grey.shade700,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                child: const Text('취소'),
              ),
            ],
          ),
        );
      },
    );

    // ✅ result: "적용" 클릭 시 값, "취소" 시 null
    // ✅ lastText: 바깥 클릭 / 뒤로가기 시 마지막 입력 내용

    final key = _formatDateKey(day);
    final newValue = result ?? lastText; // ✅ 적용 클릭 or 바깥 클릭 시 저장

    if (newValue != null) {
      if (newValue.isEmpty) {
        // 입력 없으면 삭제
        setState(() {
          _events.remove(key);
          controller.text = "";
        });
      } else {
        // 입력 있으면 저장
        setState(() {
          _events[key] = newValue;
          controller.text = newValue;
        });
      }
      await _saveEventsDebounced();
    }

    return newValue;
  }


  // ─────────────────────────────────────────────
  // 🧱 헤더 툴바
  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Calendar",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Row(
            children: [
              IconButton(
                icon: const Icon(FeatherIcons.plus, color: Colors.indigo),
                tooltip: "휴일 추가",
                onPressed: _showAddCustomHolidayDialog,
              ),
              IconButton(
                icon: const Icon(Icons.autorenew, color: Colors.green),
                tooltip: "반복 일정 추가",
                onPressed: _showRecurringDialog,
              ),
              IconButton(
                icon: const Icon(FeatherIcons.trash2, color: Colors.red),
                tooltip: "모든 메모 삭제",
                onPressed: _clearEvents,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 요일 렌더러
  Widget _buildDayOfWeek(BuildContext context, DateTime day) {
    final isSunday = day.weekday == DateTime.sunday;
    final isSaturday = day.weekday == DateTime.saturday;
    final text = ['일', '월', '화', '수', '목', '금', '토'][day.weekday % 7];
    final color = isSunday
        ? Colors.red
        : isSaturday
            ? Colors.blue
            : Theme.of(context).colorScheme.onBackground;
    return Center(
      child: Text(text,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ─────────────────────────────────────────────
  // 외부 클릭 시 메모 종료
  Future<void> _handleTapOutside() async {
    if (_editingKey == null) return;
    final prevKey = _editingKey!;
    final controller = _controllers[prevKey];
    if (controller != null) {
      _events[prevKey] = controller.text;
      await _saveEvents();
    }
    setState(() => _editingKey = null);
  }

  DateTime _getNextDateFromSelectedDays(Set<String> selectedDays) {
    if (selectedDays.isEmpty) return DateTime.now();
    // 첫 번째 선택 요일 코드 가져오기
    final firstDayCode = selectedDays.first;
    const codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
    final today = DateTime.now();
    final todayWeekday = today.weekday; // 1~7
    final targetWeekday = codes.indexOf(firstDayCode) + 1; // 1~7
    
    // 오늘 기준으로 가장 가까운 선택 요일 날짜 반환
    int diff = targetWeekday - todayWeekday;
    if (diff < 0) diff += 7;
    return today.add(Duration(days: diff));
  }

}


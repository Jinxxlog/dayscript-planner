import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../models/recurring_event.dart';

/// ✅ 반복 일정 관리 서비스 (v2)
class RecurringService {
  static const String boxName = 'recurring_events';
  static final RecurringService _instance = RecurringService._internal();
  factory RecurringService() => _instance;
  RecurringService._internal();

  Box<RecurringEvent>? _box;

  /// ✅ 초기화 (앱 시작 시 한 번만 호출)
  Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(RecurringEventAdapter());
    }

    _box ??= await Hive.openBox<RecurringEvent>(boxName);
  }

  Box<RecurringEvent> get _ensureBox {
    if (_box == null) {
      throw Exception("❌ RecurringService not initialized. Call init() first.");
    }
    return _box!;
  }

  // ───────────────────────────────
  // 🔹 CRUD: 기본 기능
  // ───────────────────────────────

  /// ✅ 모든 반복 일정 불러오기
  List<RecurringEvent> getEvents() {
    final box = _ensureBox;
    return box.values.toList();
  }

  /// ✅ 반복 일정 추가 (중복 검사 개선)
  Future<void> addEvent(RecurringEvent event) async {
    final box = _ensureBox;

    // 중복 기준:
    // - 같은 title
    // - 같은 cycleType & yearMonth & yearDay & isLunar
    // - 같은 rule (기존 RRULE 기반 데이터 호환)
    final existingKey = box.keys.firstWhere(
      (key) {
        final e = box.get(key);
        if (e == null) return false;

        // RRULE 기반 이벤트일 경우
        if (event.rule != null && event.rule!.isNotEmpty) {
          return e.title == event.title && e.rule == event.rule;
        }

        // 연간 반복 (양력/음력) 기반 이벤트일 경우
        if (event.cycleType == RecurringCycleType.yearly) {
          return e.title == event.title &&
              e.cycleType == event.cycleType &&
              e.yearMonth == event.yearMonth &&
              e.yearDay == event.yearDay &&
              e.isLunar == event.isLunar;
        }

        // 기본 fallback
        return false;
      },
      orElse: () => null,
    );

    if (existingKey != null) {
      await box.put(existingKey, event);
    } else {
      await box.add(event);
    }
  }

  /// ✅ 인덱스로 삭제
  Future<void> removeEvent(int index) async {
    final box = _ensureBox;
    if (index >= 0 && index < box.length) {
      await box.deleteAt(index);
    }
  }

  /// ✅ 제목으로 삭제 (RRULE 기반용)
  Future<void> removeEventByTitle(String title) async {
    final box = _ensureBox;
    final keysToDelete = <dynamic>[];
    for (var key in box.keys) {
      final e = box.get(key);
      if (e != null && e.title == title) {
        keysToDelete.add(key);
      }
    }
    for (var key in keysToDelete) {
      await box.delete(key);
    }
  }

  /// ✅ 특정 날짜 기반 삭제 (연간 일정 등)
  Future<void> removeEventByDate({
    required String title,
    required int month,
    required int day,
    bool isLunar = false,
  }) async {
    final box = _ensureBox;
    final keysToDelete = <dynamic>[];

    for (var key in box.keys) {
      final e = box.get(key);
      if (e == null) continue;

      final sameDate = (e.yearMonth == month &&
          e.yearDay == day &&
          e.isLunar == isLunar);

      if (e.title == title && sameDate) {
        keysToDelete.add(key);
      }
    }

    for (var key in keysToDelete) {
      await box.delete(key);
    }
  }

  /// ✅ 모든 반복 일정 초기화
  Future<void> clearAll() async {
    final box = _ensureBox;
    await box.clear();
  }

  /// ✅ 현재 달/연도의 반복 일정 가져오기
  List<RecurringEvent> getEventsForDate(DateTime date) {
    final events = getEvents();
    final List<RecurringEvent> result = [];

    for (final e in events) {
      switch (e.cycleType) {
        case RecurringCycleType.weekly:
          // 🟩 주간: 요일 비교
          if (e.rule?.contains("BYDAY") == true) {
            final code = _weekdayToCode(date.weekday);
            if (e.rule!.contains(code)) {
              result.add(e);
            }
          } else if (e.startDate.weekday == date.weekday) {
            result.add(e);
          }
          break;

        case RecurringCycleType.monthly:
          // 🟩 월간: 일(day) 비교
          if (e.rule?.contains("BYMONTHDAY") == true) {
            final m = RegExp(r'BYMONTHDAY=(\d+)').firstMatch(e.rule!);
            if (m != null && int.parse(m.group(1)!) == date.day) {
              result.add(e);
            }
          } else if (e.startDate.day == date.day) {
            result.add(e);
          }
          break;

        case RecurringCycleType.yearly:
          // 🟩 연간: 월+일 모두 비교
          if (e.rule?.contains("BYMONTH") == true &&
              e.rule?.contains("BYMONTHDAY") == true) {
            final m1 = RegExp(r'BYMONTH=(\d+)').firstMatch(e.rule!);
            final m2 = RegExp(r'BYMONTHDAY=(\d+)').firstMatch(e.rule!);
            if (m1 != null && m2 != null) {
              final month = int.parse(m1.group(1)!);
              final day = int.parse(m2.group(1)!);
              if (month == date.month && day == date.day) {
                result.add(e);
              }
            }
          } else if (e.startDate.month == date.month &&
              e.startDate.day == date.day) {
            result.add(e);
          }
          break;

        default:
          break;
      }
    }

    return result;
  }

  /// 🧭 요일 숫자 → RRULE 코드 변환
  String _weekdayToCode(int weekday) {
    const codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
    return codes[weekday - 1];
  }

  // ───────────────────────────────
  // 🆕 반복 일정 간편 추가 (멀티 요일/날짜 대응)
  // ───────────────────────────────
  Future<void> addEventWithInfo({
    required String title,
    required RecurringCycleType cycleType,
    DateTime? startDate,
    int? month,
    int? day,
    bool isLunar = false,
    Color? color,
    String? note,

    // ✅ 새로 추가된 필드
    List<int>? byDays,        // 주간 반복용: [1,3,5] → 월/수/금
    List<int>? byMonthDays,   // 월간 반복용: [1,15,28]
  }) async {
    print("🧩 [addEventWithInfo] type=$cycleType month=$month day=$day lunar=$isLunar");

    if (title.trim().isEmpty) {
      throw Exception("일정 이름을 입력해주세요.");
    }

    String rule = "FREQ=${cycleType.toString().split('.').last.toUpperCase()}";
    RecurringEvent e;

    switch (cycleType) {
      // ───────────────────────────────
      // 🗓 월간 반복
      // ───────────────────────────────
      case RecurringCycleType.monthly:
        if (byMonthDays != null && byMonthDays.isNotEmpty) {
          // ✅ 여러 날짜 지원
          final daysJoined = byMonthDays.join(',');
          rule += ";BYMONTHDAY=$daysJoined";
        } else {
          final validDay = day ?? DateTime.now().day;
          rule += ";BYMONTHDAY=$validDay";
          byMonthDays = [validDay];
        }

        e = RecurringEvent(
          title: title,
          rule: rule,
          startDate: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            byMonthDays!.first,
          ),
          color: color ?? Colors.blueAccent,
          cycleType: RecurringCycleType.monthly,
          yearDay: byMonthDays.first,
          note: note,
        );
        await addEvent(e);
        break;

      // ───────────────────────────────
      // 📅 연간 반복
      // ───────────────────────────────
      case RecurringCycleType.yearly:
        final validMonth = month ?? DateTime.now().month;
        final validDay2 = day ?? 1;
        rule += ";BYMONTH=$validMonth;BYMONTHDAY=$validDay2";

        e = RecurringEvent(
          title: title,
          rule: rule,
          startDate: DateTime(DateTime.now().year, validMonth, validDay2),
          color: color ?? Colors.redAccent,
          cycleType: RecurringCycleType.yearly,
          yearMonth: validMonth,
          yearDay: validDay2,
          isLunar: isLunar,
          note: note,
        );
        await addEvent(e);
        break;

      // ───────────────────────────────
      // 🧭 주간 반복
      // ───────────────────────────────
      case RecurringCycleType.weekly:
        if (byDays != null && byDays.isNotEmpty) {
          // ✅ 여러 요일 → MO,WE,FR 형태로 변환
          final weekdayCodes = byDays.map(_weekdayToCode).join(',');
          rule += ";BYDAY=$weekdayCodes";
        } else {
          // fallback: 단일 요일
          final weekdayCode = _weekdayToCode(startDate?.weekday ?? DateTime.now().weekday);
          rule += ";BYDAY=$weekdayCode";
        }

        e = RecurringEvent(
          title: title,
          rule: rule,
          startDate: startDate ?? DateTime.now(),
          color: color ?? Colors.greenAccent,
          cycleType: RecurringCycleType.weekly,
          note: note,
        );
        await addEvent(e);
        break;

      default:
        throw Exception("지원하지 않는 반복 유형입니다.");
    }
  }


String _getTodayCode() {
  const codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
  final weekday = DateTime.now().weekday; // 1=월 ~ 7=일
  return codes[weekday - 1];
}


} // 👈 RecurringService 클래스 닫힘은 여기!



/// ✅ Hive 어댑터 등록 (v2 확장 반영)
class RecurringEventAdapter extends TypeAdapter<RecurringEvent> {
  @override
  final int typeId = 7;

  @override
  RecurringEvent read(BinaryReader reader) {
    final title = reader.readString();
    final rule = reader.readString();
    final startDate = DateTime.parse(reader.readString());
    final colorValue = reader.readInt();

    RecurringCycleType cycleType = RecurringCycleType.none;
    int? yearMonth;
    int? yearDay;
    bool isLunar = false;
    String? id;
    String? note;

    try {
      cycleType = RecurringCycleType.values[reader.readInt()];
      yearMonth = reader.read() as int?;
      yearDay = reader.read() as int?;
      isLunar = reader.readBool();
      id = reader.read() as String?;
      note = reader.read() as String?;
    } catch (_) {}

    return RecurringEvent(
      title: title,
      rule: rule,
      startDate: startDate,
      color: Color(colorValue),
      cycleType: cycleType,
      yearMonth: (yearMonth == 0) ? null : yearMonth,
      yearDay: (yearDay == 0) ? null : yearDay,
      isLunar: isLunar,
      id: (id?.isEmpty ?? true) ? null : id,
      note: (note?.isEmpty ?? true) ? null : note,
    );
  }

  @override
  void write(BinaryWriter writer, RecurringEvent obj) {
    writer.writeString(obj.title);
    writer.writeString(obj.rule ?? '');
    writer.writeString(obj.startDate.toIso8601String());
    writer.writeInt(obj.color.value);

    // 🔹 enum null 방지
    final safeCycle = obj.cycleType ?? RecurringCycleType.none;
    writer.writeInt(safeCycle.index);

    // 🔹 primitive null 방지 (Hive는 null write 불가)
    writer.write(obj.yearMonth ?? 0);
    writer.write(obj.yearDay ?? 0);
    writer.writeBool(obj.isLunar);
    writer.write(obj.id ?? '');
    writer.write(obj.note ?? '');
  }
}

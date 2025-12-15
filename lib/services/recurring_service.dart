import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../models/recurring_event.dart';

/// 반복 일정 관리 (v2)
class RecurringService {
  static const String boxName = 'recurring_events';
  static final RecurringService _instance = RecurringService._internal();
  factory RecurringService() => _instance;
  RecurringService._internal();

  Box<RecurringEvent>? _box;

  /// Hive 초기화
  Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(RecurringEventAdapter());
    }

    _box ??= await Hive.openBox<RecurringEvent>(boxName);
  }

  Box<RecurringEvent> get _ensureBox {
    if (_box == null) {
      throw Exception("RecurringService not initialized. Call init() first.");
    }
    return _box!;
  }

  // =============================================================================
  // CRUD
  // =============================================================================

  /// 모든 반복 일정 조회 (deleted 제외)
  List<RecurringEvent> getEvents() {
    final box = _ensureBox;
    return box.values.where((e) => e.deleted != true).toList();
  }

  /// 반복 일정 추가/업서트
  Future<void> addEvent(RecurringEvent event) async {
    final box = _ensureBox;

    final existingKey = box.keys.firstWhere(
      (key) {
        final e = box.get(key);
        if (e == null) return false;

        // RRULE 기반 동일성 체크
        if (event.rule != null && event.rule!.isNotEmpty) {
          return e.title == event.title && e.rule == event.rule;
        }

        // 연간 반복 비교 (양/음력)
        if (event.cycleType == RecurringCycleType.yearly) {
          return e.title == event.title &&
              e.cycleType == event.cycleType &&
              e.yearMonth == event.yearMonth &&
              e.yearDay == event.yearDay &&
              e.isLunar == event.isLunar;
        }

        return false;
      },
      orElse: () => null,
    );

    final payload = event.copyWith(
      updatedAt: DateTime.now(),
      deleted: false,
    );

    if (existingKey != null) {
      await box.put(existingKey, payload);
    } else {
      await box.add(payload);
    }
  }

  /// 인덱스로 제거 (소프트 삭제)
  Future<void> removeEvent(int index) async {
    final box = _ensureBox;
    if (index >= 0 && index < box.length) {
      final current = box.getAt(index);
      if (current != null) {
        await box.putAt(
          index,
          current.copyWith(
            deleted: true,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        await box.deleteAt(index);
      }
    }
  }

  /// 제목으로 제거 (소프트 삭제)
  Future<void> removeEventByTitle(String title) async {
    final box = _ensureBox;
    for (var key in box.keys) {
      final e = box.get(key);
      if (e != null && e.title == title) {
        await box.put(
          key,
          e.copyWith(
            deleted: true,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
  }

  /// 월/일/음력 조건으로 제거 (소프트 삭제)
  Future<void> removeEventByDate({
    required String title,
    required int month,
    required int day,
    bool isLunar = false,
  }) async {
    final box = _ensureBox;

    for (var key in box.keys) {
      final e = box.get(key);
      if (e == null) continue;

      final sameDate =
          (e.yearMonth == month && e.yearDay == day && e.isLunar == isLunar);

      if (e.title == title && sameDate) {
        await box.put(
          key,
          e.copyWith(
            deleted: true,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
  }

  Future<void> clearAll() async {
    final box = _ensureBox;
    await box.clear();
  }

  /// 특정 날짜에 매칭되는 반복 일정 반환 (deleted 제외)
  List<RecurringEvent> getEventsForDate(DateTime date) {
    final events = getEvents();
    final List<RecurringEvent> result = [];

    for (final e in events) {
      switch (e.cycleType) {
        case RecurringCycleType.weekly:
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

  String _weekdayToCode(int weekday) {
    const codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];
    return codes[weekday - 1];
  }

  // =============================================================================
  // 편의: rule 구성
  // =============================================================================
  Future<void> addEventWithInfo({
    required String title,
    required RecurringCycleType cycleType,
    DateTime? startDate,
    int? month,
    int? day,
    bool isLunar = false,
    Color? color,
    String? note,
    List<int>? byDays, // weekly: [1,3,5] 등
    List<int>? byMonthDays, // monthly: [1,15,28] 등
  }) async {
    print("recurring addEventWithInfo type=$cycleType month=$month day=$day lunar=$isLunar");

    if (title.trim().isEmpty) {
      throw Exception("제목이 비어 있습니다.");
    }

    String rule = "FREQ=${cycleType.toString().split('.').last.toUpperCase()}";
    RecurringEvent e;

    switch (cycleType) {
      case RecurringCycleType.monthly:
        final effectiveDays = (byMonthDays != null && byMonthDays.isNotEmpty)
            ? byMonthDays
            : <int>[day ?? DateTime.now().day];
        final daysJoined = effectiveDays.join(',');
        rule += ";BYMONTHDAY=$daysJoined";

        e = RecurringEvent(
          title: title,
          rule: rule,
          startDate: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            effectiveDays.first,
          ),
          color: color ?? Colors.blueAccent,
          cycleType: RecurringCycleType.monthly,
          yearDay: effectiveDays.first,
          note: note,
        );
        await addEvent(e);
        break;

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

      case RecurringCycleType.weekly:
        if (byDays != null && byDays.isNotEmpty) {
          final weekdayCodes = byDays.map(_weekdayToCode).join(',');
          rule += ";BYDAY=$weekdayCodes";
        } else {
          final weekdayCode =
              _weekdayToCode(startDate?.weekday ?? DateTime.now().weekday);
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
        throw Exception("지원하지 않는 반복 타입입니다.");
    }
  }

} // end RecurringService

/// Hive 어댑터 (v2)
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
    DateTime? updatedAt;
    bool deleted = false;

    try {
      cycleType = RecurringCycleType.values[reader.readInt()];
      yearMonth = reader.read() as int?;
      yearDay = reader.read() as int?;
      isLunar = reader.readBool();
      id = reader.read() as String?;
      note = reader.read() as String?;
      final updatedRaw = reader.read() as String?;
      updatedAt = DateTime.tryParse(updatedRaw ?? '');
      deleted = reader.readBool();
    } catch (_) {
      updatedAt = updatedAt ?? DateTime.now();
    }

    return RecurringEvent(
      title: title,
      rule: rule.isEmpty ? null : rule,
      startDate: startDate,
      color: Color(colorValue),
      cycleType: cycleType,
      yearMonth: (yearMonth == 0) ? null : yearMonth,
      yearDay: (yearDay == 0) ? null : yearDay,
      isLunar: isLunar,
      id: (id?.isEmpty ?? true) ? null : id,
      note: (note?.isEmpty ?? true) ? null : note,
      updatedAt: updatedAt ?? DateTime.now(),
      deleted: deleted,
    );
  }

  @override
  void write(BinaryWriter writer, RecurringEvent obj) {
    writer.writeString(obj.title);
    writer.writeString(obj.rule ?? '');
    writer.writeString(obj.startDate.toIso8601String());
    writer.writeInt(obj.color.value);

    writer.writeInt(obj.cycleType.index);
    writer.write(obj.yearMonth ?? 0);
    writer.write(obj.yearDay ?? 0);
    writer.writeBool(obj.isLunar);
    writer.write(obj.id ?? '');
    writer.write(obj.note ?? '');
    writer.write(obj.updatedAt.toIso8601String());
    writer.writeBool(obj.deleted);
  }
}

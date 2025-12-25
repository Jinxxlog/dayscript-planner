import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import '../models/recurring_event.dart';
import 'local_scope.dart';
import 'local_change_notifier.dart';

/// 반복 일정 관리 (v2)
class RecurringService {
  static const String _legacyBoxName = 'recurring_events';
  static String get boxName => LocalScope.recurringEventsBox;
  static final RecurringService _instance = RecurringService._internal();
  factory RecurringService() => _instance;
  RecurringService._internal();

  static final Map<String, Box<RecurringEvent>> _cache = {};
  Box<RecurringEvent>? _box;

  /// Hive 초기화
  Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(RecurringEventAdapter());
    }

    final targetName = boxName;
    if (_box != null && _box!.name == targetName && _box!.isOpen) {
      await _ensureStableIds();
      return;
    }

    final cached = _cache[targetName];
    if (cached != null && cached.isOpen) {
      _box = cached;
      await _ensureStableIds();
      return;
    }

    final box = Hive.isBoxOpen(targetName)
        ? Hive.box<RecurringEvent>(targetName)
        : await Hive.openBox<RecurringEvent>(targetName);
    _cache[targetName] = box;
    _box = box;
    await _migrateLegacyIfNeeded(targetName);
    await _ensureStableIds();
  }

  Future<void> _migrateLegacyIfNeeded(String targetName) async {
    if (!await Hive.boxExists(_legacyBoxName)) return;

    final target = Hive.isBoxOpen(targetName)
        ? Hive.box<RecurringEvent>(targetName)
        : await Hive.openBox<RecurringEvent>(targetName);
    if (target.isNotEmpty) return;

    final legacy = await Hive.openBox<RecurringEvent>(_legacyBoxName);
    if (legacy.isEmpty) return;

    for (final e in legacy.values) {
      await target.add(e);
    }
  }

  String _stableIdFor(RecurringEvent e) {
    if (e.id != null && e.id!.trim().isNotEmpty) return e.id!.trim();
    final ym = e.yearMonth ?? 0;
    final yd = e.yearDay ?? 0;
    final rule = e.rule ?? '';
    return '${e.title}__${e.cycleType.name}__${ym}_${yd}__${rule.isEmpty ? e.startDate.toIso8601String() : rule}';
  }

  Future<void> _ensureStableIds() async {
    final box = _ensureBox;
    for (final key in box.keys) {
      final current = box.get(key);
      if (current == null) continue;
      if (current.id != null && current.id!.trim().isNotEmpty) continue;
      await box.put(key, current.copyWith(id: _stableIdFor(current)));
    }
  }

  dynamic _findKeyById(Box<RecurringEvent> box, String id) {
    for (final key in box.keys) {
      final e = box.get(key);
      if (e != null && e.id == id) return key;
    }
    return null;
  }

  dynamic _findKeyByLegacyIdentity(
    Box<RecurringEvent> box,
    RecurringEvent event,
  ) {
    return box.keys.firstWhere(
      (key) {
        final e = box.get(key);
        if (e == null) return false;

        if (event.rule != null && event.rule!.isNotEmpty) {
          return e.title == event.title && e.rule == event.rule;
        }

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

  /// 모든 반복 일정 조회
  List<RecurringEvent> getAllEvents({bool includeDeleted = false}) {
    final box = _ensureBox;
    return includeDeleted
        ? box.values.toList()
        : box.values.where((e) => e.deleted != true).toList();
  }

  /// 모든 반복 일정 조회 (deleted 제외)
  List<RecurringEvent> getEvents() => getAllEvents(includeDeleted: false);

  /// 반복 일정 추가/업서트
  Future<void> addEvent(RecurringEvent event) async {
    final box = _ensureBox;

    final id = event.id?.trim();
    dynamic existingKey;
    if (id != null && id.isNotEmpty) {
      existingKey = _findKeyById(box, id);
    }
    existingKey ??= box.keys.firstWhere(
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

    final existing = existingKey != null ? box.get(existingKey) : null;
    final payload = event.copyWith(
      id: (existing?.id != null && existing!.id!.trim().isNotEmpty)
          ? existing.id!.trim()
          : _stableIdFor(event),
      updatedAt: DateTime.now(),
      deleted: false,
    );

    if (existingKey != null) {
      await box.put(existingKey, payload);
    } else {
      await box.add(payload);
    }
    LocalChangeNotifier.notify('recurring');
  }

  Future<void> removeEventById(String id) async {
    final box = _ensureBox;
    final key = _findKeyById(box, id);
    if (key == null) return;
    final current = box.get(key);
    if (current == null) return;
    await box.put(
      key,
      current.copyWith(
        deleted: true,
        updatedAt: DateTime.now(),
      ),
    );
    LocalChangeNotifier.notify('recurring');
  }

  Future<void> removeEventByEvent(RecurringEvent event) async {
    final id = event.id?.trim();
    if (id != null && id.isNotEmpty) {
      return removeEventById(id);
    }
    final box = _ensureBox;
    final key = _findKeyByLegacyIdentity(box, event);
    if (key == null) return;
    final current = box.get(key);
    if (current == null) return;
    await box.put(
      key,
      current.copyWith(
        deleted: true,
        updatedAt: DateTime.now(),
      ),
    );
    LocalChangeNotifier.notify('recurring');
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
        LocalChangeNotifier.notify('recurring');
      } else {
        await box.deleteAt(index);
        LocalChangeNotifier.notify('recurring');
      }
    }
  }

  /// 제목으로 제거 (소프트 삭제)
  Future<void> removeEventByTitle(String title) async {
    final box = _ensureBox;
    bool changed = false;
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
        changed = true;
      }
    }
    if (changed) LocalChangeNotifier.notify('recurring');
  }

  /// 월/일/음력 조건으로 제거 (소프트 삭제)
  Future<void> removeEventByDate({
    required String title,
    required int month,
    required int day,
    bool isLunar = false,
  }) async {
    final box = _ensureBox;
    bool changed = false;

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
        changed = true;
      }
    }
    if (changed) LocalChangeNotifier.notify('recurring');
  }

  Future<void> clearAll() async {
    final box = _ensureBox;
    await box.clear();
    LocalChangeNotifier.notify('recurring');
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
    String? id,
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
          id: id,
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
          id: id,
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
          id: id,
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
      updatedAt = updatedAt ?? startDate;
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
      updatedAt: updatedAt ?? startDate,
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

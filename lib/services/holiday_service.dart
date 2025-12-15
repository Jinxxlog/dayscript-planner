import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';

/// ✅ 사용자 정의 휴일 모델
class CustomHoliday {
  final DateTime date;
  final String title;
  final String color; // "#FF0000" 같은 HEX 코드로 저장
  final DateTime updatedAt;
  final bool deleted;

  CustomHoliday({
    required this.date,
    required this.title,
    required this.color,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  CustomHoliday copyWith({
    DateTime? date,
    String? title,
    String? color,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return CustomHoliday(
      date: date ?? this.date,
      title: title ?? this.title,
      color: color ?? this.color,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'title': title,
        'color': color,
        'updatedAt': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  factory CustomHoliday.fromJson(Map<String, dynamic> json) => CustomHoliday(
        date: DateTime.parse(json['date']),
        title: json['title'],
        color: json['color'],
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        deleted: json['deleted'] == true,
      );
}

/// Hive Box 이름
const String _holidayBoxName = 'customHolidays';

/// ✅ HolidayService (Singleton)
class HolidayService {
  static final HolidayService _instance = HolidayService._internal();
  factory HolidayService() => _instance;
  HolidayService._internal();

  Box? _box;

  /// ✅ Hive 초기화
  Future<void> init() async {
    await Hive.initFlutter();
    _box ??= await Hive.openBox<Map>(_holidayBoxName);
  }

  Box get _ensureBox {
    if (_box == null) {
      throw Exception("❌ Hive box is not initialized. Call init() first.");
    }
    return _box!;
  }

  // ─────────────────────────────────────────────
  // ✅ 모든 사용자 정의 휴일 불러오기
  Future<List<CustomHoliday>> loadCustomHolidays() async {
    final box = _ensureBox;
    final holidays = <CustomHoliday>[];
    for (final e in box.values) {
      holidays.add(CustomHoliday.fromJson(Map<String, dynamic>.from(e)));
    }
    return holidays;
  }

  // ─────────────────────────────────────────────
  // ✅ 휴일 추가
  Future<void> addHoliday(CustomHoliday holiday) async {
    final box = _ensureBox;

    // 중복 방지 (같은 날짜는 덮어쓰기)
    final existingKey = box.keys.firstWhere(
      (k) {
        final value = box.get(k);
        if (value == null) return false;
        final data = Map<String, dynamic>.from(value);
        final date = DateTime.parse(data['date']);
        return _isSameDay(date, holiday.date);
      },
      orElse: () => null,
    );

    if (existingKey != null) {
      await box.delete(existingKey);
    }

    final payload = holiday.copyWith(
      updatedAt: DateTime.now(),
      deleted: false,
    );
    await box.put(holiday.date.toIso8601String(), payload.toJson());
  }

  // ─────────────────────────────────────────────
  // ✅ 휴일 삭제
  Future<void> removeHoliday(DateTime date) async {
    final box = _ensureBox;

    final targetKey = box.keys.firstWhere(
      (k) {
        final value = box.get(k);
        if (value == null) return false;
        final data = Map<String, dynamic>.from(value);
        final d = DateTime.parse(data['date']);
        return _isSameDay(d, date);
      },
      orElse: () => null,
    );

    if (targetKey != null) {
      await box.delete(targetKey);
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 특정 날짜의 휴일 검색
  Future<CustomHoliday?> getHolidayByDate(DateTime date) async {
    final box = _ensureBox;
    for (final e in box.values) {
      final data = Map<String, dynamic>.from(e);
      final d = DateTime.parse(data['date']);
      if (_isSameDay(d, date)) {
        return CustomHoliday.fromJson(data);
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // ✅ 모든 사용자 휴일 삭제
  Future<void> clearCustomHolidays() async {
    final box = _ensureBox;
    await box.clear();
    debugPrint('모든 사용자 지정 휴일이 삭제되었습니다.');
  }

  // ─────────────────────────────────────────────
  // ✅ 유틸리티
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color getColor(CustomHoliday holiday) {
    try {
      return Color(int.parse(holiday.color.replaceFirst('#', '0xff')));
    } catch (_) {
      return Colors.redAccent;
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 휴일 이름 수정
  Future<void> renameHoliday(DateTime date, String newTitle) async {
    final box = _ensureBox;

    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) continue;

      final data = Map<String, dynamic>.from(value);
      final savedDate = DateTime.parse(data['date']);

      if (_isSameDay(savedDate, date)) {
        data['title'] = newTitle;
        await box.put(key, data);
        debugPrint("✏️ ${date.toIso8601String()} 이름 수정됨 → $newTitle");
        return;
      }
    }
    debugPrint("⚠️ ${date.toIso8601String()} 해당 날짜를 찾을 수 없음");
  }

  // ─────────────────────────────────────────────
  // ✅ ICS 공휴일만 삭제
  Future<void> clearIcsHolidays() async {
    final box = _ensureBox;

    final toDelete = <dynamic>[];

    for (final entry in box.toMap().entries) {
      final data = Map<String, dynamic>.from(entry.value);
      final title = data['title'] ?? '';

      // 🔸 여기에서 기준 정의:
      // 예: title에 "설날", "추석", "광복절" 등 포함되면 ICS 공휴일로 간주
      if (_isPublicHoliday(title)) {
        toDelete.add(entry.key);
      }
    }

    for (final key in toDelete) {
      await box.delete(key);
    }

    debugPrint("🚫 ICS(공휴일)만 삭제 완료: ${toDelete.length}개 항목");
  }

  bool _isPublicHoliday(String title) {
    const knownHolidays = [
      '신정', '설날', '추석', '광복절', '현충일', '삼일절', '부처님오신날',
      '어린이날', '한글날', '크리스마스', '석가탄신일', '개천절',
    ];
    return knownHolidays.any((h) => title.contains(h));
  }

}

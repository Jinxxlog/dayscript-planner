// lib/models/recurring_event.dart
import 'package:flutter/material.dart';

/// 반복 일정의 주기 타입
enum RecurringCycleType { none, daily, weekly, monthly, yearly }

class RecurringEvent {
  // ───────── 기존 필드(역호환) ─────────
  final String title;          // 일정 제목
  final String? rule;          // RRULE (nullable로 변경)
  final DateTime startDate;    // 기준 시작일
  final Color color;           // 시각화용

  // ───────── v2 확장 필드 ─────────
  final RecurringCycleType cycleType; // none/daily/weekly/monthly/yearly
  final int? yearMonth;               // 연간 반복: 월(1~12)
  final int? yearDay;                 // 연간 반복: 일(1~31)
  final bool isLunar;                 // 음력 여부(연간 반복에서 유효)
  final String? id;                   // 선택: 식별자
  final String? note;                 // 선택: 메모

  const RecurringEvent({
    // 기존 필드
    required this.title,
    this.rule,
    required this.startDate,
    this.color = Colors.indigo,
    // 확장 필드
    this.cycleType = RecurringCycleType.none,
    this.yearMonth,
    this.yearDay,
    this.isLunar = false,
    this.id,
    this.note,
  });

  /// 기존 JSON 직렬화(필요 시 사용)
  Map<String, dynamic> toJson() => {
        "title": title,
        "rule": rule,
        "startDate": startDate.toIso8601String(),
        "color": color.value,
        "cycleType": cycleType.name,
        "yearMonth": yearMonth,
        "yearDay": yearDay,
        "isLunar": isLunar,
        "id": id,
        "note": note,
      }..removeWhere((_, v) => v == null);

  factory RecurringEvent.fromJson(Map<String, dynamic> json) {
    final cycleStr = json["cycleType"] as String?;
    final cycle = RecurringCycleType.values.firstWhere(
      (e) => e.name == (cycleStr ?? 'none'),
      orElse: () => RecurringCycleType.none,
    );

    return RecurringEvent(
      title: json["title"] as String,
      rule: json["rule"] as String?,
      startDate: DateTime.parse(json["startDate"] as String),
      color: Color(json["color"] as int),
      cycleType: cycle,
      yearMonth: json["yearMonth"] as int?,
      yearDay: json["yearDay"] as int?,
      isLunar: (json["isLunar"] as bool?) ?? false,
      id: json["id"] as String?,
      note: json["note"] as String?,
    );
  }

  RecurringEvent copyWith({
    String? title,
    String? rule,
    DateTime? startDate,
    Color? color,
    RecurringCycleType? cycleType,
    int? yearMonth,
    int? yearDay,
    bool? isLunar,
    String? id,
    String? note,
  }) {
    return RecurringEvent(
      title: title ?? this.title,
      rule: rule ?? this.rule,
      startDate: startDate ?? this.startDate,
      color: color ?? this.color,
      cycleType: cycleType ?? this.cycleType,
      yearMonth: yearMonth ?? this.yearMonth,
      yearDay: yearDay ?? this.yearDay,
      isLunar: isLunar ?? this.isLunar,
      id: id ?? this.id,
      note: note ?? this.note,
    );
  }
}

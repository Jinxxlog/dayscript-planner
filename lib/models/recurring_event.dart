// lib/models/recurring_event.dart
import 'package:flutter/material.dart';

/// 반복 일정 종류.
enum RecurringCycleType { none, daily, weekly, monthly, yearly }

class RecurringEvent {
  // 기본 정보
  final String title; // 일정 제목
  final String? rule; // RRULE (nullable)
  final DateTime startDate; // 반복 시작일
  final Color color; // 표시 색상

  // 반복 주기 정보
  final RecurringCycleType cycleType; // none/daily/weekly/monthly/yearly
  final int? yearMonth; // 연간 반복: 월(1~12)
  final int? yearDay; // 연간 반복: 일(1~31)
  final bool isLunar; // 음력 여부
  final String? id; // 식별자
  final String? note; // 메모

  // 동기화 메타
  final DateTime updatedAt;
  final bool deleted;

  RecurringEvent({
    // 기본 정보
    required this.title,
    this.rule,
    required this.startDate,
    this.color = Colors.indigo,
    // 반복 정보
    this.cycleType = RecurringCycleType.none,
    this.yearMonth,
    this.yearDay,
    this.isLunar = false,
    this.id,
    this.note,
    // 메타
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// JSON 직렬화
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
        "updatedAt": updatedAt.toIso8601String(),
        "deleted": deleted,
      }..removeWhere((_, v) => v == null);

  factory RecurringEvent.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDT(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final cycleStr = json["cycleType"] as String?;
    final cycle = RecurringCycleType.values.firstWhere(
      (e) => e.name == (cycleStr ?? 'none'),
      orElse: () => RecurringCycleType.none,
    );

    return RecurringEvent(
      title: json["title"] as String,
      rule: json["rule"] as String?,
      startDate: _parseDT(json["startDate"]) ?? DateTime.now(),
      color: Color(json["color"] as int),
      cycleType: cycle,
      yearMonth: json["yearMonth"] as int?,
      yearDay: json["yearDay"] as int?,
      isLunar: (json["isLunar"] as bool?) ?? false,
      id: json["id"] as String?,
      note: json["note"] as String?,
      updatedAt: _parseDT(json["updatedAt"]) ?? DateTime.now(),
      deleted: json["deleted"] == true,
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
    DateTime? updatedAt,
    bool? deleted,
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
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}

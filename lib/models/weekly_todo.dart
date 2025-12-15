import 'package:hive/hive.dart';

part 'weekly_todo.g.dart';

@HiveType(typeId: 1)
class WeeklyTodo extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  List<int> days; // 1=월 ~ 7=일

  @HiveField(3)
  bool isCompleted;

  @HiveField(4)
  DateTime? startTime;

  @HiveField(5)
  DateTime? endTime;

  @HiveField(6)
  String? textTime; // 예: 09:00/오전/커스텀 텍스트

  @HiveField(7)
  String? color; // HEX 코드 (기본: '#2196F3')

  @HiveField(8)
  DateTime? updatedAt;

  @HiveField(9)
  bool deleted;

  WeeklyTodo({
    required this.id,
    required this.title,
    required this.days,
    this.isCompleted = false,
    this.startTime,
    this.endTime,
    this.textTime,
    this.color = '#2196F3',
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// 얕은 복사
  WeeklyTodo copy() {
    return WeeklyTodo(
      id: id,
      title: title,
      days: List<int>.from(days),
      isCompleted: isCompleted,
      startTime: startTime != null
          ? DateTime.fromMillisecondsSinceEpoch(startTime!.millisecondsSinceEpoch)
          : null,
      endTime: endTime != null
          ? DateTime.fromMillisecondsSinceEpoch(endTime!.millisecondsSinceEpoch)
          : null,
      textTime: (textTime ?? '').trim().isEmpty ? null : textTime!.trim(),
      color: color,
      updatedAt: updatedAt,
      deleted: deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'days': days,
        'isCompleted': isCompleted,
        'startTime': startTime?.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'textTime': textTime,
        'color': color,
        'updatedAt': updatedAt?.toIso8601String(),
        'deleted': deleted,
      };

  factory WeeklyTodo.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDT(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return null;
    }

    final daysRaw = (json['days'] ?? []) as List;
    final days = daysRaw.map((e) {
      if (e is int) return e;
      if (e is String) return int.tryParse(e) ?? 0;
      if (e is double) return e.toInt();
      return 0;
    }).where((x) => x > 0).toList();

    return WeeklyTodo(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: (json['title'] ?? '').toString(),
      days: days,
      isCompleted: json['isCompleted'] == true,
      startTime: _parseDT(json['startTime']),
      endTime: _parseDT(json['endTime']),
      textTime: (json['textTime'] as String?)?.trim(),
      color: _validateColor(json['color']),
      updatedAt: _parseDT(json['updatedAt']) ?? DateTime.now(),
      deleted: json['deleted'] == true,
    );
  }

  static String _validateColor(dynamic v) {
    if (v == null || v.toString().toLowerCase() == 'null') return '#2196F3';
    final s = v.toString().trim();
    if (s.isEmpty) return '#2196F3';
    if (!s.startsWith('#')) return '#$s';
    return s;
  }

  @override
  String toString() {
    return 'WeeklyTodo(title: $title, days: $days, isCompleted: $isCompleted, color: $color, start: $startTime, textTime: $textTime)';
  }
}

// lib/models/calendar_memo.dart

class CalendarMemo {
  final String id; // 로컬 고유 ID
  final String text; // 내용
  final DateTime createdAt;
  final String color; // HEX (ex: #FF9800)
  final String? dateKey; // YYYY-MM-DD (동기화/매핑용)
  final DateTime updatedAt; // 최종 수정 시각
  final bool deleted; // soft delete

  CalendarMemo({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.color,
    this.dateKey,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  CalendarMemo copyWith({
    String? text,
    String? color,
    String? dateKey,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return CalendarMemo(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      color: color ?? this.color,
      dateKey: dateKey ?? this.dateKey,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  factory CalendarMemo.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return CalendarMemo(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      color: (json['color'] as String?)?.trim().isNotEmpty == true
          ? json['color'] as String
          : '#FFA000',
      dateKey: json['dateKey'] as String?,
      updatedAt: parseDate(json['updatedAt']) ?? DateTime.now(),
      deleted: json['deleted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'color': color,
      'dateKey': dateKey,
      'updatedAt': updatedAt.toIso8601String(),
      'deleted': deleted,
    };
  }
}

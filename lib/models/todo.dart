import 'package:hive/hive.dart';

part 'todo.g.dart'; // ✅ 코드 생성용 파일

@HiveType(typeId: 2)
class Todo extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  bool isDone;

  @HiveField(3)
  DateTime? dueTime;

  @HiveField(4)
  String? textTime;

  @HiveField(5)
  String? color;

  @HiveField(6)
  DateTime? updatedAt;

  @HiveField(7)
  bool deleted;

  Todo(
    this.id,
    this.title, {
    this.isDone = false,
    this.dueTime,
    this.textTime,
    this.color,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  // ✅ JSON 직렬화
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isDone': isDone,
        'dueTime': dueTime?.toIso8601String(),
        'textTime': textTime,
        'color': color,
        'updatedAt': updatedAt?.toIso8601String(),
        'deleted': deleted,
      };

  // ✅ JSON 역직렬화
  factory Todo.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDT(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return Todo(
      json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      json['title']?.toString() ?? '',
      isDone: json['isDone'] ?? false,
      dueTime: _parseDT(json['dueTime']),
      textTime: json['textTime']?.toString(),
      color: json['color']?.toString(),
      updatedAt: _parseDT(json['updatedAt']) ?? DateTime.now(),
      deleted: json['deleted'] == true,
    );
  }

  // ✅ 복제 기능
  Todo copy() => Todo(
        id,
        title,
        isDone: isDone,
        dueTime: dueTime,
        textTime: textTime,
        color: color,
        updatedAt: updatedAt,
        deleted: deleted,
      );

  @override
  String toString() {
    return 'Todo(title: $title, isDone: $isDone, textTime: $textTime, dueTime: $dueTime, color: $color)';
  }
}

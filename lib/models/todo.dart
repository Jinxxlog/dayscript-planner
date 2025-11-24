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

  // 🟩 추가: 색상 HEX 값 저장용
  @HiveField(5)
  String? color;

  Todo(
    this.id,
    this.title, {
    this.isDone = false,
    this.dueTime,
    this.textTime,
    this.color, // ✅ 생성자에도 추가
  });

  // ✅ JSON 직렬화
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isDone': isDone,
        'dueTime': dueTime?.toIso8601String(),
        'textTime': textTime,
        'color': color, // ✅ 추가
      };

  // ✅ JSON 역직렬화
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      json['title']?.toString() ?? '',
      isDone: json['isDone'] ?? false,
      dueTime: json['dueTime'] != null ? DateTime.tryParse(json['dueTime']) : null,
      textTime: json['textTime']?.toString(),
      color: json['color']?.toString(), // ✅ 추가
    );
  }

  // ✅ 복제 기능
  Todo copy() => Todo(
        id,
        title,
        isDone: isDone,
        dueTime: dueTime,
        textTime: textTime,
        color: color, // ✅ 추가
      );

  @override
  String toString() {
    return 'Todo(title: $title, isDone: $isDone, textTime: $textTime, dueTime: $dueTime, color: $color)';
  }
}

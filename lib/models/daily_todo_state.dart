import 'todo.dart';

class DailyTodoState {
  final String dateKey; // yyyy-mm-dd
  final List<Todo> items;
  final DateTime updatedAt;
  final bool deleted;

  DailyTodoState({
    required this.dateKey,
    required this.items,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? _maxUpdatedAt(items);

  DailyTodoState copyWith({
    String? dateKey,
    List<Todo>? items,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return DailyTodoState(
      dateKey: dateKey ?? this.dateKey,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'items': items.map((t) => t.toJson()).toList(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory DailyTodoState.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List?) ?? const [];
    final items = itemsRaw
        .map((e) => Todo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final dateKey = json['dateKey']?.toString() ?? '';
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        _maxUpdatedAt(items);

    return DailyTodoState(
      dateKey: dateKey,
      items: items,
      updatedAt: updatedAt,
      deleted: json['deleted'] == true,
    );
  }

  static DateTime _maxUpdatedAt(List<Todo> items) {
    DateTime max = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final t in items) {
      final ts = t.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (ts.isAfter(max)) max = ts;
    }
    return max;
  }
}


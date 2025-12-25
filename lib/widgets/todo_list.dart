import 'package:flutter/material.dart';
import '../models/todo.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TodoList extends StatefulWidget {
  final List<Todo> todos;
  final void Function(List<Todo>) onTodosChanged;

  const TodoList({
    super.key,
    required this.todos,
    required this.onTodosChanged,
  });

  @override
  State<TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<TodoList> {
  Future<void> _reorderTodos(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final newTodos = List<Todo>.from(widget.todos);
    final item = newTodos.removeAt(oldIndex);
    newTodos.insert(newIndex, item);
    widget.onTodosChanged(newTodos);
  }

  void _toggleTodoDone(int index) {
    final newTodos = List<Todo>.from(widget.todos);
    newTodos[index].isDone = !newTodos[index].isDone;
    widget.onTodosChanged(newTodos);
  }
  

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.todos.isEmpty) {
      return Center(
        child: Text(
          "오늘의 투두가 없습니다.",
          style: TextStyle(
            fontSize: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: true, // ✅ 기본 핸들 사용 (길게 눌러 어디서든 드래그 가능)
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onReorder: _reorderTodos,
      itemCount: widget.todos.length,
      itemBuilder: (context, index) {
        final todo = widget.todos[index];
        return KeyedSubtree( // 🔹 color가 변경될 때마다 자동 리빌드
          key: ValueKey('todo-${todo.id}-${todo.color ?? "none"}'),
          child: _AnimatedTodoTile(
            index: index, // 내부 드래그 핸들용
            title: todo.title,
            time: todo.dueTime,
            textTime: todo.textTime,
            isDone: todo.isDone,
            onToggle: () => _toggleTodoDone(index),
            theme: theme,
            color: todo.color,
          ).animate().fade(duration: 300.ms).slideY(begin: 0.2, duration: 300.ms),
        );
      },
    );
  }
}

class _AnimatedTodoTile extends StatefulWidget {
  final int index;
  final String title;
  final bool isDone;
  final DateTime? time;
  final String? textTime;
  final String? color;
  final VoidCallback onToggle;
  final ThemeData theme;

  const _AnimatedTodoTile({
    required this.index,
    required this.title,
    required this.isDone,
    required this.onToggle,
    required this.theme,
    this.time,
    this.textTime,
    this.color,
  });

  @override
  State<_AnimatedTodoTile> createState() => _AnimatedTodoTileState();
}


class _AnimatedTodoTileState extends State<_AnimatedTodoTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.theme.colorScheme;
    final textTheme = widget.theme.textTheme;

    String timeLabel = "아무때나";
    if (widget.time != null) {
      final t = TimeOfDay.fromDateTime(widget.time!);
      timeLabel = t.format(context);
    } else if ((widget.textTime ?? '').trim().isNotEmpty) {
      timeLabel = widget.textTime!.trim();
    }

    final dividerColor = colorScheme.brightness == Brightness.light
        ? colorScheme.outlineVariant.withOpacity(0.45)
        : colorScheme.outlineVariant.withOpacity(0.25);

    return Column(
      children: [
        ReorderableDragStartListener(
          index: widget.index,
          child: Listener( // 🔹 눌림 시 색상 반응 추가
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggle, // ✅ 체크 토글
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                color: _pressed
                    ? colorScheme.surfaceVariant.withOpacity(0.08)
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // 🎨 색상 원
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _parseColor(widget.color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.7),
                          width: 1,
                        ),
                      ),
                    ),

                    // ⏰ 시간 or 텍스트
                    SizedBox(
                      width: 70,
                      child: Text(
                        timeLabel,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // 📝 제목
                    Expanded(
                      child: Text(
                        widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: widget.isDone
                              ? FontWeight.normal
                              : FontWeight.w500,
                          decoration: widget.isDone
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: widget.isDone
                              ? colorScheme.secondary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Divider(
          height: 1,
          thickness: 0.5,
          indent: 70,
          color: dividerColor,
        ),
      ],
    );
  }

  Color _parseColor(String? raw) {
    // 기본색(파싱 실패 시)
    final fallback = widget.theme.colorScheme.tertiary;
    if (raw == null) return fallback;

    // 1) 문자열 정리
    var s = raw.trim();                 // 공백 제거
    if (s.isEmpty) return fallback;
    s = s.replaceAll(' ', '').toUpperCase();

    try {
      // 2) 이미 0x로 시작하면 그대로 파싱
      if (s.startsWith('0X')) {
        return Color(int.parse(s));
      }

      // 3) #RRGGBB or #AARRGGBB
      if (s.startsWith('#')) {
        s = s.substring(1); // '#' 제거
      }

      // 4) RRGGBB(6자리) → 불투명 alpha(FF) 붙여서 ARGB로
      if (RegExp(r'^[0-9A-F]{6}$').hasMatch(s)) {
        return Color(int.parse('0xFF$s'));
      }

      // 5) AARRGGBB(8자리) 그대로 사용
      if (RegExp(r'^[0-9A-F]{8}$').hasMatch(s)) {
        return Color(int.parse('0x$s'));
      }

      // 6) 그 외 형식(예: RRRGGGBBB 등) → 실패
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

}

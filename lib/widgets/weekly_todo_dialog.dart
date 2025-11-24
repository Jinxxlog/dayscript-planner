import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter/material.dart';
import '../services/todo_service.dart';
import '../models/weekly_todo.dart';
import '../models/color_category.dart'; // ✅ 추가

class WeeklyTodoDialog extends StatefulWidget {
  final VoidCallback onChanged;

  const WeeklyTodoDialog({super.key, required this.onChanged});

  @override
  State<WeeklyTodoDialog> createState() => _WeeklyTodoDialogState();
}

class _WeeklyTodoDialogState extends State<WeeklyTodoDialog> {
  final _controller = TextEditingController();
  final _customTextController = TextEditingController();
  final _todoService = TodoService();

  List<int> _selectedDays = [];
  List<WeeklyTodo> _weeklyTodos = [];

  bool _timeEnabled = false;
  bool _isTextMode = false; // ✅ 텍스트 모드 추가
  int? _hour;
  int? _minute;

  int _selectedColorIndex = 0; // ✅ 색상 인덱스 추가

  String? _selectedTextTime = '아침'; // ✅ 텍스트 모드 선택값
  final List<String> _textTimeOptions = ['아무때나', '아침', '점심', '저녁', '사용자 입력'];
  final List<String> _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  Future<void> _loadTodos() async {
    final todos = await _todoService.loadTodos(fromMain: false);
    if (mounted) setState(() => _weeklyTodos = todos);
  }

  /// ✅ 새 투두 추가
  Future<void> _addTodo() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _selectedDays.isEmpty) return;

    DateTime? startTime;
    String? textTime;

    if (_isTextMode) {
      textTime = _selectedTextTime == '사용자 입력'
          ? _customTextController.text.trim()
          : _selectedTextTime;
    } else if (_timeEnabled && _hour != null && _minute != null) {
      final now = DateTime.now();
      startTime = DateTime(now.year, now.month, now.day, _hour!, _minute!);
    }

    final colorHex = _colorToHex(ColorCategory.colors[_selectedColorIndex]); // ✅ 추가됨
    await _todoService.addTodo(
      title,
      List<int>.from(_selectedDays),
      startTime: startTime,
      textTime: textTime ?? '아무때나',
      fromMain: false,
      color: colorHex,
    );

    // ✅ 추가된 주간투두 → 오늘 날짜와 메인 투두에 즉시 반영
    await _todoService.syncSpecificDays(_selectedDays);

    _clearInput();
    await _loadTodos();
    widget.onChanged(); // 메인 화면 리프레시
    }

    String _colorToHex(Color color) =>
      '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    void _clearInput() {
      _controller.clear();
      _customTextController.clear();
      setState(() {
        _selectedDays.clear();
        _timeEnabled = false;
        _isTextMode = false;
        _selectedTextTime = '아침';
        _hour = null;
        _minute = null;
        _selectedColorIndex = 0;
      });
    }

    Future<void> _deleteTodo(WeeklyTodo todo) async {
      await _todoService.deleteTodo(todo.id, fromMain: false);
      await _todoService.deleteTodo(todo.id, fromMain: true);
      await _loadTodos();
      widget.onChanged();
    }

      /// ✅ 색상 선택 위젯
    Widget _buildColorPicker() {
      final colorScheme = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("색상 선택", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(ColorCategory.colors.length, (i) {
              final color = ColorCategory.colors[i];
              final isSelected = _selectedColorIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : Colors.grey.shade400,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      );
    }
    
    Future<String?> _showColorPickerDialog(String? currentHex) async {
      return showDialog<String>(
        context: context,
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('색상 선택'),
            content: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: defaultCategories.map((cat) {
                  final color = ColorCategory.fromHex(cat.color);
                  final name = cat.name;
                  final isSelected = currentHex == cat.color;
                  return ListTile(
                    leading: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : Colors.grey.shade400,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                    title: Text(name),
                    onTap: () => Navigator.pop(context, cat.color),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
            ],
          );
        },
      );
    }

  /// ✅ 수정
  Future<void> _editTodo(WeeklyTodo todo) async {
    final result = await _showEditDialog(todo);
    if (result == null) return;

    DateTime? newStart;
    String? newTextTime;

    if (result['isTextMode']) {
      newTextTime = result['selectedTextTime'] == '사용자 입력'
          ? result['customText']
          : result['selectedTextTime'];
    } else if (result['timeEnabled'] &&
        result['hour'] != null &&
        result['minute'] != null) {
      final now = DateTime.now();
      newStart = DateTime(now.year, now.month, now.day, result['hour'], result['minute']);
    }

    await _todoService.updateTodo(
      todo.id,
      title: result['title'],
      days: List<int>.from(result['days']),
      startTime: newStart,
      textTime: newTextTime, // ✅ 새 필드 저장
      fromMain: false,
    );

    await _loadTodos();
    widget.onChanged();
  }

  /// ✏️ 수정 다이얼로그
  Future<Map<String, dynamic>?> _showEditDialog(WeeklyTodo todo) async {
    final controller = TextEditingController(text: todo.title);
    final customTextCtrl = TextEditingController(text: todo.textTime ?? '');

    List<int> selectedDays = List.from(todo.days);
    bool timeEnabled = todo.startTime != null;
    bool isTextMode = todo.textTime != null;
    int? hour = todo.startTime?.hour;
    int? minute = todo.startTime?.minute;
    String? selectedText = todo.textTime;

    bool isWeekdaySelected = false;
    bool isWeekendSelected = false;
    bool isEverydaySelected = false;

    return showDialog<Map<String, dynamic>>(

      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('투두 수정'),
          content: StatefulBuilder(builder: (context, setStateDialog) {
            return SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: '할 일 제목'),
                    ),
                    const SizedBox(height: 12),

                    // 🔹 요일 칩
                    Wrap(
                      spacing: 6,
                      alignment: WrapAlignment.center,
                      children: List.generate(_dayLabels.length, (i) {
                        final dayIndex = i + 1;
                        final selected = selectedDays.contains(dayIndex);
                        return FilterChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          label: Text(_dayLabels[i]),
                          selected: selected,
                          selectedColor: Colors.blueAccent,
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.black,
                          ),
                          onSelected: (v) {
                            setStateDialog(() {
                              if (v) {
                                selectedDays.add(dayIndex);
                              } else {
                                selectedDays.remove(dayIndex);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 12),

                    // 🔹 시간 모드/텍스트 모드 전환 (ToggleButtons으로 교체)
                    Row(
                      children: [
                        ToggleButtons(
                          isSelected: [isTextMode, !isTextMode],
                          borderRadius: BorderRadius.circular(10),
                          selectedColor: Colors.white,
                          fillColor: isTextMode ? Colors.orangeAccent : Colors.blueAccent,
                          color: Colors.grey.shade600,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                          onPressed: (index) {
                            setStateDialog(() {
                              isTextMode = index == 0;
                              timeEnabled = !isTextMode;
                            });
                          },
                          children: const [
                            Icon(FeatherIcons.edit3),   // 📝 텍스트 모드
                            Icon(FeatherIcons.clock), // ⏰ 시간 모드
                          ],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isTextMode ? '텍스트 모드' : '시간 모드',
                          style: TextStyle(
                            color: isTextMode ? Colors.orangeAccent : Colors.blueAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    // 🔹 텍스트 모드
                    if (isTextMode)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        DropdownButton<String>(
                          value: _textTimeOptions.contains(selectedText)
                              ? selectedText
                              : _textTimeOptions.first,
                          items: [
                            "아무때나",
                            ..._textTimeOptions.where((e) => e != "아무때나"),
                          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) {
                            setStateDialog(() {
                              selectedText = v;
                            });
                          },
                        ),
                          if (selectedText == '사용자 입력')
                            TextField(
                              controller: customTextCtrl,
                              decoration: const InputDecoration(
                                  labelText: '직접 입력', hintText: '예: 새벽 운동'),
                            ),
                        ],
                      ),

                    // 🔹 시간 모드
                    if (!isTextMode)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              timeEnabled
                                  ? FeatherIcons.clock
                                  : FeatherIcons.clock,
                              color: timeEnabled ? Colors.blueAccent : Colors.grey,
                            ),
                            onPressed: () {
                              setStateDialog(() => timeEnabled = !timeEnabled);
                            },
                          ),
                          if (timeEnabled)
                            Row(
                              children: [
                                DropdownButton<int>(
                                  value: hour ?? 0,
                                  items: List.generate(
                                      24,
                                      (i) => DropdownMenuItem(
                                            value: i,
                                            child:
                                                Text(i.toString().padLeft(2, '0')),
                                          )),
                                  onChanged: (v) => setStateDialog(() => hour = v),
                                ),
                                const Text(':'),
                                DropdownButton<int>(
                                  value: minute ?? 0,
                                  items: List.generate(12, (i) {
                                    final mv = i * 5;
                                    return DropdownMenuItem(
                                      value: mv,
                                      child:
                                          Text(mv.toString().padLeft(2, '0')),
                                    );
                                  }),
                                  onChanged: (v) =>
                                      setStateDialog(() => minute = v),
                                ),
                              ],
                            )
                          else
                            const Text("아무때나",
                                style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context, {
                  'title': controller.text.trim(),
                  'days': selectedDays,
                  'timeEnabled': timeEnabled,
                  'hour': hour,
                  'minute': minute,
                  'isTextMode': isTextMode,
                  'selectedTextTime': selectedText,
                  'customText': customTextCtrl.text.trim(),
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary, // ✅ 메인 테마색 (라이트/다크 자동 대응)
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('저장'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error, // ✅ 닫기/취소는 붉은 계열
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  // ✅ 시간 or 텍스트 선택 행
  Widget _buildTimePickerRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ToggleButtons(
          isSelected: [_isTextMode, !_isTextMode],
          borderRadius: BorderRadius.circular(10),
          selectedColor: Colors.white,
          fillColor: _isTextMode ? Colors.orangeAccent : Colors.blueAccent,
          color: Colors.grey.shade600,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
          onPressed: (index) {
            setState(() {
              _isTextMode = index == 0;
              _timeEnabled = !_isTextMode;
            });
          },
          children: const [
            Icon(FeatherIcons.edit3),   // 📝 텍스트 모드
            Icon(FeatherIcons.clock), // ⏰ 시간 모드
          ],
        ),
        const SizedBox(width: 12),
        Text(
          _isTextMode ? '텍스트 모드' : '시간 모드',
          style: TextStyle(
            color: _isTextMode ? Colors.orangeAccent : Colors.blueAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),

        // 🔹 모드별 UI 표시
        if (_isTextMode)
          Row(
            children: [
            DropdownButton<String>(
              // ✅ value가 리스트 안에 없으면 기본값으로 대체
              value: _textTimeOptions.contains(_selectedTextTime)
                  ? _selectedTextTime
                  : _textTimeOptions.first,
              // ✅ "아무때나" 기본항목 항상 포함
              items: [
                "아무때나",
                ..._textTimeOptions.where((e) => e != "아무때나"),
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _selectedTextTime = v),
            ),
              if (_selectedTextTime == '사용자 입력')
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _customTextController,
                    decoration: const InputDecoration(
                      hintText: '직접 입력',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          )
        else
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _timeEnabled
                      ? FeatherIcons.clock
                      : FeatherIcons.clock,
                  color: _timeEnabled ? Colors.blueAccent : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _timeEnabled = !_timeEnabled;
                    if (_timeEnabled && (_hour == null || _minute == null)) {
                      _hour = 0;
                      _minute = 0;
                    }
                  });
                },
              ),
              if (_timeEnabled)
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _hour ?? 0,
                      items: List.generate(
                          24,
                          (i) => DropdownMenuItem(
                                value: i,
                                child: Text(i.toString().padLeft(2, '0')),
                              )),
                      onChanged: (v) => setState(() => _hour = v ?? 0),
                    ),
                    const Text(':'),
                    DropdownButton<int>(
                      value: _minute ?? 0,
                      items: List.generate(12, (i) {
                        final mv = i * 5;
                        return DropdownMenuItem(
                          value: mv,
                          child: Text(mv.toString().padLeft(2, '0')),
                        );
                      }),
                      onChanged: (v) => setState(() => _minute = v ?? 0),
                    ),
                  ],
                )
              else
                const Text("아무때나", style: TextStyle(color: Colors.grey)),
            ],
          ),
      ],
    );
  }


  // ✅ 이하 기존 코드 (요일/리스트 그대로 유지)
  // ─────────────────────────────────────────────
  Widget _buildInputField() => TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: '할 일 입력',
          border: OutlineInputBorder(),
        ),
      );

    

  Widget _buildDayChips() => Center(
        child: Wrap(
          spacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(_dayLabels.length, (i) {
            final dayIndex = i + 1;
            final selected = _selectedDays.contains(dayIndex);
            return FilterChip(
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              label: Text(_dayLabels[i]),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  v ? _selectedDays.add(dayIndex) : _selectedDays.remove(dayIndex);
                });
              },
            );
          }),
        ),
      );

  Widget _buildQuickSelectButtons() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isWeekdaySelected = _selectedDays.toSet().containsAll([1, 2, 3, 4, 5]);
    bool isWeekendSelected = _selectedDays.toSet().containsAll([6, 7]);
    bool isEverydaySelected =
        _selectedDays.length == 7 && _selectedDays.toSet().containsAll([1, 2, 3, 4, 5, 6, 7]);

    void toggleGroup(String group) {
      setState(() {
        if (group == "weekday") {
          if (isWeekdaySelected) {
            _selectedDays.removeWhere((d) => d >= 1 && d <= 5);
          } else {
            _selectedDays.addAll([1, 2, 3, 4, 5]);
          }
        } else if (group == "weekend") {
          if (isWeekendSelected) {
            _selectedDays.removeWhere((d) => d >= 6 && d <= 7);
          } else {
            _selectedDays.addAll([6, 7]);
          }
        } else if (group == "everyday") {
          if (isEverydaySelected) {
            _selectedDays.clear();
          } else {
            _selectedDays = [1, 2, 3, 4, 5, 6, 7];
          }
        }
      });
    }

    return Center(
      child: Wrap(
        spacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _buildToggleButton("평일", isWeekdaySelected, () => toggleGroup("weekday"), colorScheme),
          _buildToggleButton("주말", isWeekendSelected, () => toggleGroup("weekend"), colorScheme),
          _buildToggleButton("매일", isEverydaySelected, () => toggleGroup("everyday"), colorScheme),
        ],
      ),
    );
  }

  Widget _buildToggleButton(
  String label,
  bool isSelected,
  VoidCallback onTap,
  ColorScheme colorScheme,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // 🔹 글자색 / 배경색 설정
  final textColor = isSelected
      ? (isDark ? Colors.white : colorScheme.primary)
      : (isDark ? Colors.white70 : Colors.black87);

  final bgColor = isSelected
      ? (isDark
          ? Colors.white.withOpacity(0.15) // 다크모드 선택 시 은은한 흰빛
          : colorScheme.primary.withOpacity(0.15)) // 라이트모드 파란빛 강조
      : Colors.transparent;

  return AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: isSelected
            ? (isDark
                ? Colors.white.withOpacity(0.3)
                : colorScheme.primary.withOpacity(0.4))
            : Colors.transparent,
      ),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : colorScheme.primary.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
          : [],
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      splashColor: isDark
          ? Colors.white.withOpacity(0.05)
          : colorScheme.primary.withOpacity(0.15),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
          child: Text(label),
        ),
      ),
    ),
  );
}
  Widget _buildTodoList(ColorScheme colorScheme) => Expanded(
    child: ReorderableListView.builder(
      itemCount: _weeklyTodos.length,
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _weeklyTodos.removeAt(oldIndex);
          _weeklyTodos.insert(newIndex, item);
        });
        await _todoService.saveTodos(_weeklyTodos, fromMain: false);
        widget.onChanged();
      },
      itemBuilder: (context, i) {
        final todo = _weeklyTodos[i];
        final days = todo.days.map((d) => _dayLabels[d - 1]).join(', ');

        String timeText;
        if (todo.startTime != null) {
          timeText = TimeOfDay.fromDateTime(todo.startTime!).format(context);
        } else if (todo.textTime != null && todo.textTime!.trim().isNotEmpty) {
          timeText = todo.textTime!.trim();
        } else {
          timeText = '아무때나';
        }

        return Container(
          key: ValueKey(todo.id),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 8, right: 4),

            // 🟢 왼쪽 원 아이콘 추가
            leading: GestureDetector(
              onTap: () async {
                final selectedColor = await _showColorPickerDialog(todo.color);
                if (selectedColor != null) {
                  todo.color = selectedColor;

                  // ✅ WeeklyTodo 저장
                  await _todoService.saveTodos(_weeklyTodos, fromMain: false);

                  // ✅ 색상 변경 반영 (모든 날짜)
                  await _todoService.refreshColorsFromDialog(); // 🔹 추가 (전날~미래 전부)
                  await _todoService.syncAllFromDialog();       // 🔹 미래 날짜에도 적용

                  setState(() {});
                  widget.onChanged();
                }
              },
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _parseColor(todo.color ?? '#FF9E9E9E'),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 1),
                ),
              ),
            ),

            title: Text(todo.title, style: const TextStyle(fontSize: 15)),
            subtitle: Text(
              "$days · $timeText",
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(FeatherIcons.edit3, color: Colors.blueAccent),
                  onPressed: () => _editTodo(todo),
                ),
                IconButton(
                  icon: const Icon(FeatherIcons.trash2, color: Colors.redAccent),
                  onPressed: () => _deleteTodo(todo),
                ),
                const SizedBox(width: 8),
                ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle_rounded,
                      color: Colors.grey, size: 22),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );


  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceAll('#', '0xff')));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

      @override
      Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text('위클리 투두 관리'),
          content: SizedBox(
            width: 520,
            height: 540,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimePickerRow(),
                const SizedBox(height: 8),
                _buildInputField(),
                const SizedBox(height: 8),
                _buildDayChips(),
                const SizedBox(height: 8),
                _buildQuickSelectButtons(),
                const Divider(),
                _buildTodoList(colorScheme),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: _addTodo,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary, // ✅ 메인 버튼색
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('추가'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error, // ✅ 닫기 버튼은 붉은 계열
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              child: const Text('닫기'),
            ),
          ],
        );
      }


}

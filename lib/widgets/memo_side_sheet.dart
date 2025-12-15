// lib/widgets/memo_side_sheet.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/calendar_memo.dart';

class MemoSideSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<CalendarMemo> memos;
  final void Function(String text, String color) onAdd;
  final void Function(CalendarMemo updated) onUpdate;
  final void Function(String memoId) onDelete;
  final VoidCallback onClose;

  const MemoSideSheet({
    super.key,
    required this.selectedDay,
    required this.memos,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<MemoSideSheet> createState() => _MemoSideSheetState();
}

class _MemoSideSheetState extends State<MemoSideSheet> {
  final TextEditingController _newMemoController = TextEditingController();
  final List<String> _colorPalette = const [
    '#FF9800',
    '#E57373',
    '#64B5F6',
    '#81C784',
    '#BA68C8',
    '#FFD54F',
  ];
  String _newMemoColor = '#FF9800';

  @override
  void dispose() {
    _newMemoController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      "${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}";

  Color _parseColor(String hex, ThemeData theme) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xff')));
    } catch (_) {
      return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.12)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, minWidth: 340),
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "메모",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(widget.selectedDay),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: "닫기",
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),

                  // Memo list
                  Expanded(
                    child: widget.memos.isEmpty
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                "이 날짜에는 아직 메모가 없어요.\n아래 입력창에서 첫 메모를 추가해보세요.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: widget.memos.length,
                            itemBuilder: (context, index) {
                              final memo = widget.memos[index];
                              return Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant
                                      .withOpacity(isDark ? 0.35 : 0.65),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withOpacity(0.4),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin:
                                              const EdgeInsets.only(top: 10),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _parseColor(
                                                memo.color, theme),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: memo.text,
                                            maxLines: null,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme
                                                  .colorScheme.onSurface,
                                            ),
                                            decoration: const InputDecoration(
                                              isCollapsed: true,
                                              border: InputBorder.none,
                                              hintText: "메모 내용을 입력하세요",
                                            ),
                                            onChanged: (value) {
                                              widget.onUpdate(
                                                memo.copyWith(text: value),
                                              );
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: "삭제",
                                          onPressed: () =>
                                              widget.onDelete(memo.id),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                          color: Colors.redAccent,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _colorPalette.map((hex) {
                                        final selected = hex == memo.color;
                                        return GestureDetector(
                                          onTap: () {
                                            widget.onUpdate(
                                                memo.copyWith(color: hex));
                                          },
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color:
                                                  _parseColor(hex, theme),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: selected
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme
                                                        .outlineVariant,
                                                width: selected ? 2 : 1,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Input area
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withOpacity(0.5),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _colorPalette.map((hex) {
                            final selected = hex == _newMemoColor;
                            return GestureDetector(
                              onTap: () => setState(() => _newMemoColor = hex),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: _parseColor(hex, theme),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant,
                                    width: selected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    if (selected)
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.25),
                                        blurRadius: 8,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newMemoController,
                                maxLines: 2,
                                minLines: 1,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: "새 메모 추가...",
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: theme
                                          .colorScheme.outlineVariant,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () {
                                final text = _newMemoController.text.trim();
                                if (text.isEmpty) return;
                                widget.onAdd(text, _newMemoColor);
                                _newMemoController.clear();
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "추가",
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

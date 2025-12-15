import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/custom_colors.dart';

class MemoPad extends StatefulWidget {
  final bool showInlineTitle; // 상위에서 타이틀을 렌더링하면 false로 전달

  const MemoPad({
    super.key,
    this.showInlineTitle = true,
  });

  @override
  State<MemoPad> createState() => _MemoPadState();
}

class _MemoPadState extends State<MemoPad> {
  final TextEditingController _memoController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadMemo();
  }

  Future<void> _loadMemo() async {
    try {
      final savedMemo = await StorageService.loadMemo();
      if (savedMemo != null) {
        setState(() => _memoController.text = savedMemo);
      }
    } catch (e) {
      debugPrint("⚠️ 메모 로드 중 오류: $e");
    }
  }

  Future<void> _saveMemo() async {
    setState(() => _isSaving = true);
    try {
      await StorageService.saveMemo(_memoController.text);
    } catch (e) {
      debugPrint("⚠️ 메모 저장 오류: $e");
    } finally {
      await Future.delayed(const Duration(milliseconds: 300)); // UX용 딜레이
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showInlineTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              "Memo Pad.",
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        Expanded(
          child: TextField(
            controller: _memoController,
            onChanged: (_) => _saveMemo(),
            expands: true,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              hintText: "오늘 떠오른 생각이나 메모를 남겨보세요.",
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}

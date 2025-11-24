import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/custom_colors.dart';

class MemoPad extends StatefulWidget {
  const MemoPad({super.key});

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
    final colorScheme = Theme.of(context).colorScheme;
    final custom = Theme.of(context).extension<CustomColors>();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 헤더
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Notepad",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                if (_isSaving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 본문 TextField
            Expanded(
              child: TextField(
                controller: _memoController,
                onChanged: (_) => _saveMemo(),
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: "메모를 입력하세요...",
                  filled: true,
                  fillColor: Color.alphaBlend(
                    // 🎨 calendarTodayFill 색상을 반투명하게 섞음
                    (custom?.calendarTodayFill.withOpacity(0.3)) ?? Colors.transparent,
                    colorScheme.surface,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

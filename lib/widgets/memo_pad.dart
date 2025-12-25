import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Text;
import 'package:provider/provider.dart';

import '../services/entitlement_provider.dart';
import '../services/local_change_notifier.dart';
import '../services/storage_service.dart';
import 'memo_pad_codec.dart';

class MemoPad extends StatefulWidget {
  final bool showInlineTitle;

  const MemoPad({
    super.key,
    this.showInlineTitle = true,
  });

  @override
  State<MemoPad> createState() => _MemoPadState();
}

class _MemoPadState extends State<MemoPad> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  late final QuillController _controller;

  Timer? _debounce;
  StreamSubscription<String>? _sub;
  bool _suppressSave = false;
  String _lastSavedPayload = '';

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic(editorFocusNode: _focusNode);
    _controller.addListener(_onChanged);
    // ignore: discarded_futures
    _loadMemo();

    _sub = LocalChangeNotifier.stream.listen((area) async {
      if (!mounted) return;
      if (area != 'storage') return;
      if (_focusNode.hasFocus) return;
      await _loadMemo();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMemo() async {
    try {
      final saved = await StorageService.loadMemo() ?? '';
      final doc = MemoPadCodec.decodeToDocument(saved);

      _suppressSave = true;
      _controller.document = doc;
      _controller.readOnly = false;
      _lastSavedPayload = saved;
    } catch (e) {
      debugPrint('[MemoPad] load failed: $e');
    } finally {
      _suppressSave = false;
    }
  }

  void _onChanged() {
    if (_suppressSave) return;
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      try {
        final payload = MemoPadCodec.encodeDocument(_controller.document);
        if (payload == _lastSavedPayload) return;
        _lastSavedPayload = payload;
        await StorageService.saveMemo(payload, updatedAt: DateTime.now().toUtc());
      } catch (e) {
        debugPrint('[MemoPad] save failed: $e');
      }
    });
  }

  void _toggleStyle(Attribute attribute) {
    final attrs = _controller.getSelectionStyle().attributes;
    final active = attrs.containsKey(attribute.key);
    _controller.formatSelection(
      active ? Attribute.clone(attribute, null) : attribute,
    );
  }

  Future<void> _pickColorAndApply() async {
    final colors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.amber,
      Colors.green,
      Colors.teal,
      Colors.blueAccent,
      Colors.indigo,
      Colors.purpleAccent,
      Colors.pinkAccent,
      Colors.black87,
    ];

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('글자 색상'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in colors)
              InkWell(
                onTap: () => Navigator.pop(context, c),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );

    if (picked == null) return;
    final rgb = (picked.value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
    _controller.formatSelection(
      Attribute.clone(Attribute.color, '#${rgb.toUpperCase()}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final ent = context.watch<EntitlementProvider>();
    final canCustomize = ent.hydrated && ent.balanceAt(DateTime.now()).isAdFree;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showInlineTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Memo Pad.',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        if (canCustomize)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: '볼드',
                  onPressed: () => _toggleStyle(Attribute.bold),
                  icon: const Icon(Icons.format_bold),
                ),
                IconButton(
                  tooltip: '이탤릭',
                  onPressed: () => _toggleStyle(Attribute.italic),
                  icon: const Icon(Icons.format_italic),
                ),
                IconButton(
                  tooltip: '삭선',
                  onPressed: () => _toggleStyle(Attribute.strikeThrough),
                  icon: const Icon(Icons.strikethrough_s),
                ),
                IconButton(
                  tooltip: '색상',
                  onPressed: _pickColorAndApply,
                  icon: const Icon(Icons.format_color_text),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(color: Colors.transparent),
            child: QuillEditor.basic(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              configurations: QuillEditorConfigurations(
                expands: true,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                placeholder: '메모를 입력하세요.',
              ),
            ),
          ),
        ),
      ],
    );
  }
}


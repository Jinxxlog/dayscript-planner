import 'package:flutter/material.dart';

class MemoMarkup {
  static TextSpan parse(
    String input, {
    required TextStyle baseStyle,
  }) {
    final spans = <InlineSpan>[];
    final buf = StringBuffer();

    var bold = false;
    var italic = false;
    var strike = false;
    final colorStack = <Color>[];

    TextStyle currentStyle() {
      var style = baseStyle;
      if (bold) style = style.copyWith(fontWeight: FontWeight.w700);
      if (italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (strike) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (colorStack.isNotEmpty) {
        style = style.copyWith(color: colorStack.last);
      }
      return style;
    }

    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString(), style: currentStyle()));
      buf.clear();
    }

    int i = 0;
    while (i < input.length) {
      final rest = input.substring(i);

      if (rest.startsWith('**')) {
        flush();
        bold = !bold;
        i += 2;
        continue;
      }

      if (rest.startsWith('~~')) {
        flush();
        strike = !strike;
        i += 2;
        continue;
      }

      if (rest.startsWith('*')) {
        flush();
        italic = !italic;
        i += 1;
        continue;
      }

      if (rest.toLowerCase().startsWith('[color=#')) {
        final end = rest.indexOf(']');
        if (end > 8) {
          final token = rest.substring(0, end + 1);
          final hex = token.substring(8, token.length - 1);
          final color = _parseHexColor(hex);
          if (color != null) {
            flush();
            colorStack.add(color);
            i += token.length;
            continue;
          }
        }
      }

      if (rest.toLowerCase().startsWith('[/color]')) {
        flush();
        if (colorStack.isNotEmpty) {
          colorStack.removeLast();
        }
        i += '[/color]'.length;
        continue;
      }

      buf.write(input[i]);
      i += 1;
    }

    flush();
    return TextSpan(children: spans, style: baseStyle);
  }

  static Color? _parseHexColor(String hexRaw) {
    final hex = hexRaw.trim().replaceAll('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    if (hex.length == 6) return Color(0xFF000000 | v);
    return Color(v);
  }
}


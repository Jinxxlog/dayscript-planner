import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' hide Text;

class MemoPadCodec {
  static Document decodeToDocument(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.isEmpty) {
      return Document()..insert(0, '\n');
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final ops = decoded
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (ops.isNotEmpty) {
          return Document.fromJson(ops);
        }
      }
    } catch (_) {
      // Fall back to plain text.
    }

    final text = raw.endsWith('\n') ? raw : '$raw\n';
    return Document()..insert(0, text);
  }

  static String encodeDocument(Document doc) {
    return jsonEncode(doc.toDelta().toJson());
  }
}


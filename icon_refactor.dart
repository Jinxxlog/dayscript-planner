import 'dart:io';

/// Material Icons → Feather Icons 매핑 테이블
final Map<String, String> iconMap = {
  'FeatherIcons.plus': 'FeatherIcons.plus',
  'FeatherIcons.edit3': 'FeatherFeatherIcons.edit33',
  'FeatherIcons.edit3': 'FeatherFeatherIcons.edit33',
  'FeatherIcons.trash2': 'FeatherIcons.trash2',
  'FeatherIcons.trash2': 'FeatherIcons.trash2',
  'FeatherIcons.trash2': 'FeatherIcons.trash2',
  'FeatherIcons.calendar': 'FeatherIcons.calendar',
  'FeatherIcons.clock': 'FeatherIcons.clock',
  'FeatherIcons.clock': 'FeatherIcons.clock',
  'FeatherIcons.clock': 'FeatherIcons.clock',
  'FeatherIcons.check': 'FeatherFeatherIcons.check',
  'FeatherIcons.x': 'FeatherIcons.x',
  'FeatherIcons.alertTriangle': 'FeatherIcons.alertTriangle',
  'FeatherIcons.settings': 'FeatherFeatherIcons.settings',
  'FeatherIcons.search': 'FeatherFeatherIcons.search',
  'FeatherIcons.info': 'FeatherFeatherIcons.info',
  'FeatherIcons.star': 'FeatherFeatherIcons.star',
  'FeatherIcons.arrowLeft': 'FeatherIcons.arrowLeft',
  'FeatherIcons.arrowRight': 'FeatherIcons.arrowRight',
  'FeatherIcons.download': 'FeatherFeatherIcons.download',
  'FeatherIcons.upload': 'FeatherFeatherIcons.upload',
  'FeatherIcons.filePlus': 'FeatherIcons.filePlus',
  'FeatherFeatherIcons.checkCircle': 'FeatherFeatherIcons.checkCircle',
  'FeatherIcons.alertCircle': 'FeatherIcons.alertCircle',
  'FeatherIcons.list': 'FeatherFeatherIcons.list',
  'FeatherIcons.refreshCw': 'FeatherFeatherIcons.refreshCwCw',
};

void main() {
  final directory = Directory.current;
  print("🔍 Searching Dart files in: ${directory.path}");

  final dartFiles = directory
      .listSync(recursive: true)
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  for (final file in dartFiles) {
    final fileContent = File(file.path).readAsStringSync();
    String updatedContent = fileContent;

    for (final entry in iconMap.entries) {
      if (updatedContent.contains(entry.key)) {
        updatedContent = updatedContent.replaceAll(entry.key, entry.value);
      }
    }

    // 🔹 잘못된 suffix (예: _filled, _note, _forever 등) 자동 정리
    updatedContent = updatedContent.replaceAllMapped(
      RegExp(r'FeatherIcons\.(\w+?)_(note|filled|outlined|forever|rounded|outline)'),
      (match) => 'FeatherIcons.${match.group(1)}',
    );

    // 🔹 import 추가 (존재하지 않으면)
    if (updatedContent.contains('FeatherIcons.') &&
        !updatedContent.contains("flutter_feather_icons")) {
      updatedContent = "import 'package:flutter_feather_icons/flutter_feather_icons.dart';\n" +
          updatedContent;
    }

    File(file.path).writeAsStringSync(updatedContent);
  }

  print("✅ Icon replacement complete!");
}

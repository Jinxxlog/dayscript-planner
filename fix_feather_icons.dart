import 'dart:io';

void main() {
  final dir = Directory.current;
  final dartFiles = dir.listSync(recursive: true)
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final regex = RegExp(r'FeatherIcons\.(\w+?)_(note|rounded|outline|outlined|filled|forever|forever_rounded)');
  for (final file in dartFiles) {
    var content = File(file.path).readAsStringSync();
    if (regex.hasMatch(content)) {
      final newContent = content.replaceAllMapped(regex, (m) => 'FeatherIcons.${m.group(1)}');
      File(file.path).writeAsStringSync(newContent);
      print('✅ Fixed: ${file.path}');
    }
  }

  print('🎯 All invalid FeatherIcons suffixes cleaned up!');
}

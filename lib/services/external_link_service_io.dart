import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class ExternalLinkServiceImpl {
  ExternalLinkServiceImpl._();

  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    if (Platform.isWindows) {
      return _run('cmd', ['/c', 'start', '', uri.toString()]);
    } else if (Platform.isMacOS) {
      final ok = await _run('open', [uri.toString()]);
      if (ok) return true;
    } else if (Platform.isLinux) {
      final ok = await _run('xdg-open', [uri.toString()]);
      if (ok) return true;
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> _run(String executable, List<String> args) async {
    try {
      final result = await Process.run(
        executable,
        args,
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

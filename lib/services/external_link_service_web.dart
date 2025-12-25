import 'package:url_launcher/url_launcher.dart';

class ExternalLinkServiceImpl {
  ExternalLinkServiceImpl._();

  static Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


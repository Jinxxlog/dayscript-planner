import 'external_link_service_io.dart'
    if (dart.library.html) 'external_link_service_web.dart';

class ExternalLinkService {
  ExternalLinkService._();

  static Future<bool> open(String url) => ExternalLinkServiceImpl.open(url);
}


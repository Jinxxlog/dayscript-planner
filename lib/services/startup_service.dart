import 'startup_service_io.dart'
    if (dart.library.html) 'startup_service_stub.dart';

/// Thin wrapper that exposes static methods for platform-specific startup handling.
class StartupService {
  static Future<void> init() => StartupServiceImpl.init();
  static Future<void> setStartupEnabled(bool enable) =>
      StartupServiceImpl.setStartupEnabled(enable);
  static Future<bool> isStartupEnabled() => StartupServiceImpl.isStartupEnabled();
}

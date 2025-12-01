import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _EnableStartupNative = Void Function(Uint8);
typedef _EnableStartup = void Function(int);

typedef _IsStartupEnabledNative = Uint8 Function();
typedef _IsStartupEnabled = int Function();

class StartupService {
  static late final _EnableStartup _setStartup;
  static late final _IsStartupEnabled _getStartup;

  static Future<void> init() async {
    if (!Platform.isWindows) return;

    final lib = DynamicLibrary.open("startup.dll");

    _setStartup =
        lib.lookupFunction<_EnableStartupNative, _EnableStartup>("setStartup");
    _getStartup =
        lib.lookupFunction<_IsStartupEnabledNative, _IsStartupEnabled>("isStartupEnabled");
  }

  static Future<void> setStartupEnabled(bool enable) async {
    _setStartup(enable ? 1 : 0);

    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("startup_enabled", enable);
  }

  static Future<bool> isStartupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool("startup_enabled");

    if (cached != null) return cached;

    return _getStartup() == 1;
  }
}

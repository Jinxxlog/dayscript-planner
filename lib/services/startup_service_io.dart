import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _EnableStartupNative = Void Function(Uint8);
typedef _EnableStartup = void Function(int);

typedef _IsStartupEnabledNative = Uint8 Function();
typedef _IsStartupEnabled = int Function();

class StartupServiceImpl {
  static _EnableStartup _setStartup = (_) {};
  static _IsStartupEnabled _getStartup = () => 0;
  static bool _libAvailable = false;

  static Future<void> init() async {
    if (!Platform.isWindows) {
      _libAvailable = false;
      return;
    }

    try {
      const dllName = "startup.dll";
      if (!File(dllName).existsSync()) {
        debugPrint("startup.dll not found, skip startup registration.");
        _libAvailable = false;
        return;
      }

      final lib = DynamicLibrary.open(dllName);

      _setStartup =
          lib.lookupFunction<_EnableStartupNative, _EnableStartup>("setStartup");
      _getStartup = lib.lookupFunction<_IsStartupEnabledNative,
          _IsStartupEnabled>("isStartupEnabled");
      _libAvailable = true;
    } catch (e) {
      _libAvailable = false;
      debugPrint("startup.dll load failed: $e");
    }
  }

  static Future<void> setStartupEnabled(bool enable) async {
    if (!_libAvailable) return;
    _setStartup(enable ? 1 : 0);

    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("startup_enabled", enable);
  }

  static Future<bool> isStartupEnabled() async {
    if (!_libAvailable) return false;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool("startup_enabled");

    if (cached != null) return cached;

    return _getStartup() == 1;
  }
}

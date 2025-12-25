import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

typedef _EnableStartupNative = Void Function(Uint8);
typedef _EnableStartup = void Function(int);

typedef _IsStartupEnabledNative = Uint8 Function();
typedef _IsStartupEnabled = int Function();

class StartupServiceImpl {
  static _EnableStartup _setStartup = (_) {};
  static _IsStartupEnabled _getStartup = () => 0;
  static bool _libAvailable = false;
  static const _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValueName = 'DayScript';

  static Future<void> init() async {
    if (!Platform.isWindows) {
      _libAvailable = false;
      return;
    }

    try {
      const dllName = "startup.dll";
      if (!File(dllName).existsSync()) {
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
    if (!Platform.isWindows) return;

    if (_libAvailable) {
      _setStartup(enable ? 1 : 0);
    } else {
      final ok = _setStartupViaRegistry(enable);
      if (!ok) return;
    }

    final prefs = await SharedPreferences.getInstance();
    prefs.setBool("startup_enabled", enable);
  }

  static Future<bool> isStartupEnabled() async {
    if (!Platform.isWindows) return false;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool("startup_enabled");

    if (_libAvailable) {
      if (cached != null) return cached;
      return _getStartup() == 1;
    }

    final enabled = _isStartupEnabledViaRegistry();
    await prefs.setBool("startup_enabled", enabled);
    return enabled;
  }

  static bool _setStartupViaRegistry(bool enable) {
    try {
      final key = _openRunKey();
      if (key == 0) return false;
      try {
        final namePtr = _runValueName.toNativeUtf16();
        if (!enable) {
          try {
            RegDeleteValue(key, namePtr);
            return true;
          } finally {
            calloc.free(namePtr);
          }
        }

        final exePath = _currentExePath();
        if (exePath == null || exePath.isEmpty) return false;
        final value = '"$exePath"';
        final data = value.toNativeUtf16();
        try {
          final result = RegSetValueEx(
            key,
            namePtr,
            0,
            REG_SZ,
            data.cast<Uint8>(),
            value.length * sizeOf<WCHAR>(),
          );
          return result == ERROR_SUCCESS;
        } finally {
          calloc.free(namePtr);
          calloc.free(data);
        }
      } finally {
        RegCloseKey(key);
      }
    } catch (e) {
      debugPrint('Startup registry write failed: $e');
      return false;
    }
  }

  static bool _isStartupEnabledViaRegistry() {
    try {
      final key = _openRunKey();
      if (key == 0) return false;
      try {
        final valueName = _runValueName.toNativeUtf16();
        final dataSize = calloc<DWORD>()..value = 0;
        try {
          final query = RegQueryValueEx(
            key,
            valueName,
            nullptr,
            nullptr,
            nullptr,
            dataSize,
          );
          if (query != ERROR_SUCCESS || dataSize.value == 0) return false;
          return true;
        } finally {
          calloc.free(valueName);
          calloc.free(dataSize);
        }
      } finally {
        RegCloseKey(key);
      }
    } catch (_) {
      return false;
    }
  }

  static int _openRunKey() {
    final phkResult = calloc<HANDLE>();
    final subKey = _runKeyPath.toNativeUtf16();
    try {
      final result = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKey,
        0,
        KEY_READ | KEY_WRITE,
        phkResult,
      );
      if (result != ERROR_SUCCESS) return 0;
      return phkResult.value;
    } finally {
      calloc.free(subKey);
      calloc.free(phkResult);
    }
  }

  static String? _currentExePath() {
    final buffer = calloc<WCHAR>(MAX_PATH);
    try {
      final len = GetModuleFileName(0, buffer.cast<Utf16>(), MAX_PATH);
      if (len == 0) return null;
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }
}

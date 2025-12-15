import 'package:flutter/services.dart';

class DesktopMultiWindow {
  static Future<void> setMethodHandler(
    Future<dynamic> Function(MethodCall call, int fromWindowId)? handler,
  ) async {}

  static Future<dynamic> invokeMethod(
      int windowId, String method, dynamic args) async {}
}

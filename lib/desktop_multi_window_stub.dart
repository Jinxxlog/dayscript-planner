import 'package:flutter/services.dart';

class WindowController {
  Future<void> setFrame(dynamic frame) async {}
  Future<void> setTitle(String title) async {}
  Future<void> show() async {}
}

class DesktopMultiWindow {
  static void initialize() {}

  static Future<void> setMethodHandler(
    Future<dynamic> Function(MethodCall call, int fromWindowId)? handler,
  ) async {}

  static Future<WindowController> createWindow(String args) async {
    return WindowController();
  }

  static Future<dynamic> invokeMethod(
      int windowId, String method, dynamic args) async {}
}

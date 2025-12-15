import 'dart:ui';

class Screen {
  final Rect frame;
  Screen({required this.frame});
}

class WindowInfo {
  final Rect? frame;
  WindowInfo({this.frame});
}

Future<void> setWindowTitle(String title) async {}

Future<void> setWindowFrame(Rect frame) async {}

Future<void> setWindowMinSize(Size size) async {}

Future<void> setWindowMaxSize(Size size) async {}

Future<Screen?> getCurrentScreen() async => null;

Future<WindowInfo> getWindowInfo() async => WindowInfo(frame: null);

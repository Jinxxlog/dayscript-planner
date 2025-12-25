import 'dart:async';

/// Broadcasts local data changes so sync can be triggered (debounced).
class LocalChangeNotifier {
  LocalChangeNotifier._();

  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static void notify(String area) {
    if (_controller.isClosed) return;
    _controller.add(area);
  }
}


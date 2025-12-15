// lib/main.dart
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'platform_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/startup_service.dart';
import 'package:window_size/window_size.dart'
    if (dart.library.html) 'window_size_stub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/holiday_service.dart';
import 'services/recurring_service.dart';
import 'services/theme_service.dart';
import 'theme/themes.dart';
import 'models/weekly_todo.dart';
import 'pages/planner_home.dart';
import 'pages/mobile_home.dart';
import 'services/todo_service.dart';
import 'services/auth_provider.dart';
import 'pages/login_page.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// ë©€í‹°ìœˆë„ìš°
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) 'desktop_multi_window_stub.dart';
import 'multi_window.dart';


Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await StartupService.init();

  final bool firebaseSupported =
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  if (firebaseSupported && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // ðŸšª 1) ì„œë¸Œ ìœˆë„ìš° ì§„ìž… ë¶„ê¸° (settings ë“±)
  if (args.isNotEmpty && args.first == 'multi_window') {
    Map<String, dynamic> params = {};
    if (args.length > 1) {
      try {
        params = jsonDecode(args[1]) as Map<String, dynamic>;
      } catch (_) {}
    }

    runApp(MultiWindowApp(args: params));
    return; // â— ë©”ì¸ ì´ˆê¸°í™” ì½”ë“œë¡œ ë‚´ë ¤ê°€ì§€ ì•Šê²Œ ì—¬ê¸°ì„œ ëë‚´ê¸°
  }

  // ðŸšª 2) ì—¬ê¸°ë¶€í„°ëŠ” "ë©”ì¸ ìœˆë„ìš°" ì „ìš© ì´ˆê¸°í™”
  await Hive.initFlutter();

  if (firebaseSupported && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // ðŸ”¸ ë” ì´ìƒ initialize() í•„ìš” ì—†ìŒ
  // if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
  //   DesktopMultiWindow.initialize();
  // }

  //ì´ˆê¸°í™”ìš© ìž„ì‹œ ì½”ë“œ
  //await Hive.deleteBoxFromDisk('recurring_events');

  // âœ… Hive ì–´ëŒ‘í„° ë“±ë¡
  Hive.registerAdapter(WeeklyTodoAdapter());

  // âœ… íˆ¬ë‘ìš© ë°•ìŠ¤ 2ê°œ ì˜¤í”ˆ
  await Hive.openBox('weekly_todos_main');
  await Hive.openBox('weekly_todos_dialog');

  // âœ… íˆ¬ë‘ ìƒíƒœ ì €ìž¥ìš© ë°•ìŠ¤ ë¯¸ë¦¬ ì˜¤í”ˆ
  //final todoService = TodoService();
  //await todoService.loadDailyState(DateTime.now());

  // âœ… ì„œë¹„ìŠ¤ ì´ˆê¸°í™”
  await HolidayService().init();
  await RecurringService().init();

  // âœ… ë°ìŠ¤í¬íƒ‘ ì°½ ì„¸íŒ…
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('Dayscript');

    // âœ… ì´ˆê¸° ê¸°ë³¸ í¬ê¸°ë§Œ ì„¤ì • (ê³ ì • X)
    setWindowFrame(const Rect.fromLTWH(0, 0, 1920, 1080));

    // âœ… ìµœì†Œ í¬ê¸° (ë„ˆë¬´ ìž‘ì§€ë§Œ ì•Šìœ¼ë©´ ë¨)R
    setWindowMinSize(const Size(900, 600));

    // âœ… ìµœëŒ€ í¬ê¸° ì œí•œ ì œê±° (ë¬´ì œí•œ ë¦¬ì‚¬ì´ì¦ˆ ê°€ëŠ¥)
    setWindowMaxSize(Size.infinite);

    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble("window_left");
    final top = prefs.getDouble("window_top");
    final width = prefs.getDouble("window_width");
    final height = prefs.getDouble("window_height");

    if (left != null && top != null && width != null && height != null) {
      final screen = await getCurrentScreen();

      if (screen != null) {
        final frame = screen.frame;

        // âœ… í™”ë©´ ì˜ì—­ ì•ˆìª½ìœ¼ë¡œ ì¢Œí‘œ ë³´ì • + double ë³€í™˜
        final safeLeft = left.clamp(frame.left, frame.right - 400).toDouble();
        final safeTop = top.clamp(frame.top, frame.bottom - 300).toDouble();

        // âœ… ìµœì†Œ ì°½ í¬ê¸° ë³´ì • + double ë³€í™˜
        final safeWidth = (width < 800 ? 1280 : width).toDouble();
        final safeHeight = (height < 600 ? 900 : height).toDouble();

        setWindowFrame(Rect.fromLTWH(safeLeft, safeTop, safeWidth, safeHeight));
      }
    } else {
      // âœ… ì²˜ìŒ ì‹¤í–‰ ì‹œ ì¤‘ì•™ ì •ë ¬ ìœ ì§€
      final screen = await getCurrentScreen();
      if (screen != null) {
        final frame = screen.frame;
        final w = frame.width * 0.7;
        final h = frame.height * 0.7;
        final l = frame.left + (frame.width - w) / 2;
        final t = frame.top + (frame.height - h) / 2;
        setWindowFrame(Rect.fromLTWH(l, t, w, h));
      }
    }
  }


  // âœ… Windows ì¢…ë£Œ ì‹œ ì°½ í¬ê¸°/ìœ„ì¹˜ ì €ìž¥ í›… ì—°ê²°
  if (Platform.isWindows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      attachWindowCloseHandler();
    });
  }


  // âœ… ì´ˆê¸° ThemeMode ë¡œë“œ í›„ ì•± ì‹¤í–‰
  final themeService = ThemeService();
  final initialMode = await themeService.loadThemeMode();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(enabled: firebaseSupported),
      child:
          MyPlannerApp(
              themeService: themeService,
              initialMode: initialMode,
              supportsAuth: firebaseSupported),
    ),
  );
}

// âœ… ì°½ ë‹«íž˜ ì´ë²¤íŠ¸ ê°ì§€ + ì§ì ‘ ì €ìž¥ ì‹¤í–‰
void attachWindowCloseHandler() async {
  const WM_CLOSE = 0x0010;

  // ì°½ ì¢…ë£Œ ê°ì§€ (window_size íŒ¨í‚¤ì§€ ë°©ì‹)
  getWindowInfo().then((info) {
    // ì¢…ë£Œ ìˆœê°„ ì €ìž¥
    saveWindowSizeDirect();
  });
}

Future<void> saveWindowSizeDirect() async {
  final info = await getWindowInfo();
  final frame = info.frame;

  if (frame != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("window_left", frame.left);
    await prefs.setDouble("window_top", frame.top);
    await prefs.setDouble("window_width", frame.width);
    await prefs.setDouble("window_height", frame.height);
  }
}


class MyPlannerApp extends StatefulWidget {
  final ThemeService themeService;
  final ThemeMode initialMode;
  final bool supportsAuth;
  const MyPlannerApp({
    super.key,
    required this.themeService,
    required this.initialMode,
    required this.supportsAuth,
  });

  @override
  State<MyPlannerApp> createState() => _MyPlannerAppState();
}

class _MyPlannerAppState extends State<MyPlannerApp>
    with WidgetsBindingObserver {
  late ThemeMode _themeMode = widget.initialMode;

  final _todoService = TodoService(); // ê·¸ëƒ¥ ìœ ì§€

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerMultiWindowHandler();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _registerMultiWindowHandler() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
        if (call.method == 'themeChanged') {
          final modeStr = call.arguments as String? ?? 'system';
          final mode = switch (modeStr) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          setState(() => _themeMode = mode);
          await widget.themeService.saveThemeMode(mode);
        }
        return null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      await _saveWindowSize();
    }
  }

  Future<void> _saveWindowSize() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final info = await getWindowInfo();
      final frame = info.frame;
      if (frame != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble("window_left", frame.left);
        await prefs.setDouble("window_top", frame.top);
        await prefs.setDouble("window_width", frame.width);
        await prefs.setDouble("window_height", frame.height);
      }
    }
  }

  Future<void> _handleThemeChange(String mode) async {
    switch (mode) {
      case 'light':
        setState(() => _themeMode = ThemeMode.light);
        await widget.themeService.saveThemeMode(ThemeMode.light);
        break;
      case 'dark':
        setState(() => _themeMode = ThemeMode.dark);
        await widget.themeService.saveThemeMode(ThemeMode.dark);
        break;
      default:
        setState(() => _themeMode = ThemeMode.system);
        await widget.themeService.saveThemeMode(ThemeMode.system);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isIOS || Platform.isAndroid;
    final supportsAuth = widget.supportsAuth;
    return MaterialApp(
      title: 'Dayscript',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      routes: supportsAuth ? {'/login': (_) => const LoginPage()} : const {},
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (!supportsAuth) {
            // Desktop(Windows 등)에서 Firebase 미지원 시 로그인 건너뜀
            return PlannerHomePage(onThemeChange: _handleThemeChange);
          }
          if (!auth.isAuthenticated) {
            return const LoginPage();
          }
          return isMobile
              ? MobileHomePage(
                  themeMode: _themeMode,
                  onThemeChange: _handleThemeChange,
                )
              : PlannerHomePage(onThemeChange: _handleThemeChange);
        },
      ),
    );
  }
}

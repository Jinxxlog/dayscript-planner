// lib/main.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_size/window_size.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/holiday_service.dart';
import 'services/recurring_service.dart';
import 'services/theme_service.dart';
import 'theme/themes.dart';
import 'models/weekly_todo.dart';
import 'pages/planner_home.dart';
import 'services/todo_service.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// 멀티윈도우
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'multi_window.dart';

Future<void> main(List<String> args) async {

  final prefs = await SharedPreferences.getInstance();
  prefs.remove("window_width");
  prefs.remove("window_height");
  prefs.remove("window_left");
  prefs.remove("window_top");

  WidgetsFlutterBinding.ensureInitialized();

  // 🚪 1) 서브 윈도우 진입 분기 (settings 등)
  if (args.isNotEmpty && args.first == 'multi_window') {
    Map<String, dynamic> params = {};
    if (args.length > 1) {
      try {
        params = jsonDecode(args[1]) as Map<String, dynamic>;
      } catch (_) {}
    }

    runApp(MultiWindowApp(args: params));
    return; // ❗ 메인 초기화 코드로 내려가지 않게 여기서 끝내기
  }

  // 🚪 2) 여기부터는 "메인 윈도우" 전용 초기화
  await Hive.initFlutter();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔸 더 이상 initialize() 필요 없음
  // if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
  //   DesktopMultiWindow.initialize();
  // }

  //초기화용 임시 코드
  //await Hive.deleteBoxFromDisk('recurring_events');

  // ✅ Hive 어댑터 등록
  Hive.registerAdapter(WeeklyTodoAdapter());

  // ✅ 투두용 박스 2개 오픈
  await Hive.openBox('weekly_todos_main');
  await Hive.openBox('weekly_todos_dialog');

  // ✅ 투두 상태 저장용 박스 미리 오픈
  final todoService = TodoService();
  await todoService.loadDailyState(DateTime.now());

  // ✅ 서비스 초기화
  await HolidayService().init();
  await RecurringService().init();

  // ✅ 데스크탑 창 세팅
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('Dayscript');
    setWindowMinSize(const Size(1920, 1080));
    setWindowMaxSize(Size.infinite);

    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble("window_left");
    final top = prefs.getDouble("window_top");
    final width = prefs.getDouble("window_width");
    final height = prefs.getDouble("window_height");

    if (left != null && top != null && width != null && height != null) {
      setWindowFrame(Rect.fromLTWH(left, top, width, height));
    } else {
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

  // ✅ 초기 ThemeMode 로드 후 앱 실행
  final themeService = ThemeService();
  final initialMode = await themeService.loadThemeMode();
  runApp(MyPlannerApp(themeService: themeService, initialMode: initialMode));
}

class MyPlannerApp extends StatefulWidget {
  final ThemeService themeService;
  final ThemeMode initialMode;
  const MyPlannerApp({
    super.key,
    required this.themeService,
    required this.initialMode,
  });

  @override
  State<MyPlannerApp> createState() => _MyPlannerAppState();
}

class _MyPlannerAppState extends State<MyPlannerApp>
    with WidgetsBindingObserver {
  late ThemeMode _themeMode = widget.initialMode;

  final _todoService = TodoService(); // 그냥 유지

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    return MaterialApp(
      title: 'Dayscript',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: PlannerHomePage(onThemeChange: _handleThemeChange),
    );
  }
}

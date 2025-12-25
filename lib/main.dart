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
import 'services/local_scope.dart';
import 'theme/themes.dart';
import 'theme/theme_presets.dart';
import 'models/weekly_todo.dart';
import 'pages/planner_home.dart';
import 'pages/mobile_home.dart';
import 'pages/pc_link_page.dart';
import 'services/todo_service.dart';
import 'services/auth_provider.dart' as app_auth;
import 'services/device_link_service.dart';
import 'services/device_identity_service.dart';
import 'services/sync_coordinator.dart';
import 'services/pc_device_revocation_watcher.dart';
import 'pages/login_page.dart';
import 'services/ads_debug_settings_provider.dart';
import 'services/entitlement_provider.dart';
import 'services/credit_provider.dart';
import 'services/ui_prefs_provider.dart';
import 'services/ads/ad_controller.dart';
import 'services/account_data_reset_service.dart';
import 'services/iap_purchase_coordinator.dart';
import 'services/billing_service.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

// ë©€í‹°ìœˆë„ìš°
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) 'desktop_multi_window_stub.dart';
import 'multi_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await StartupService.init();

  // Secondary window (multi_window) should skip Firebase/Hive init.
  if (args.isNotEmpty && args.first == "multi_window") {
    Map<String, dynamic> params = {};
    if (args.length > 1) {
      try {
        params = jsonDecode(args[1]) as Map<String, dynamic>;
      } catch (_) {}
    }
    runApp(MultiWindowApp(args: params));
    return;
  }

  final bool firebaseSupported =
      kIsWeb ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
  if (firebaseSupported && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  await Hive.initFlutter();

  // Handle purchaseStream as early as possible (mobile only).
  IapPurchaseCoordinator().start();

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
  await Hive.openBox(LocalScope.weeklyMainBox);
  await Hive.openBox(LocalScope.weeklyDialogBox);
  await Hive.openBox(LocalScope.dailyTodosBox);

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
    MultiProvider(
      providers: [
        ChangeNotifierProvider<app_auth.AuthProvider>(
          create: (_) => app_auth.AuthProvider(enabled: firebaseSupported),
        ),
        ChangeNotifierProvider(create: (_) => AdsDebugSettingsProvider()),
        ChangeNotifierProxyProvider<app_auth.AuthProvider, EntitlementProvider>(
          create: (_) => EntitlementProvider(),
          update: (_, auth, ent) {
            // ignore: discarded_futures
            ent!.setUser(auth.user);
            return ent;
          },
        ),
        ChangeNotifierProxyProvider<app_auth.AuthProvider, CreditProvider>(
          create: (_) => CreditProvider(),
          update: (_, auth, credit) {
            // ignore: discarded_futures
            credit!.setUser(auth.user);
            return credit;
          },
        ),
        ChangeNotifierProxyProvider<app_auth.AuthProvider, UiPrefsProvider>(
          create: (_) => UiPrefsProvider(),
          update: (_, auth, prefs) {
            // ignore: discarded_futures
            prefs!.setUser(auth.user);
            return prefs;
          },
        ),
        ChangeNotifierProxyProvider2<
          EntitlementProvider,
          AdsDebugSettingsProvider,
          AdController
        >(
          create: (context) => AdController(
            entitlement: context.read<EntitlementProvider>(),
            debugSettings: context.read<AdsDebugSettingsProvider>(),
          ),
          update: (_, entitlement, debugSettings, controller) {
            controller!.updateDeps(
              entitlement: entitlement,
              debugSettings: debugSettings,
            );
            return controller;
          },
        ),
      ],
      child: MyPlannerApp(
        themeService: themeService,
        initialMode: initialMode,
        supportsAuth: firebaseSupported,
      ),
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
  String? _lastLoggedUid;
  bool _lastLoggedAnon = false;
  final _pcRevocationWatcher = PcDeviceRevocationWatcher();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerMultiWindowHandler();
    if (widget.supportsAuth &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // ignore: discarded_futures
      _pcRevocationWatcher.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pcRevocationWatcher.dispose();
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
        if (call.method == 'uiPrefsChanged') {
          try {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
            final fontFamily = args['fontFamily']?.toString();
            final themePresetId = args['themePresetId']?.toString();
            final textScaleRaw = args['textScale'];
            final textScale =
                textScaleRaw is num ? textScaleRaw.toDouble() : null;

            final prefs = context.read<UiPrefsProvider>();
            if (fontFamily != null) {
              await prefs.setFontFamily(fontFamily);
            }
            if (themePresetId != null) {
              await prefs.setThemePresetId(themePresetId);
            }
            if (textScale != null) {
              await prefs.setTextScale(textScale);
            }
            if (fontFamily == null && themePresetId == null && textScale == null) {
              await prefs.reloadFromCache();
            }
            return {'ok': true};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        if (call.method == 'pcLinkWithSecret') {
          try {
            final existing = FirebaseAuth.instance.currentUser;
            if (existing != null && !existing.isAnonymous) {
              return {'ok': false, 'message': 'Already linked.'};
            }
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            final secret = (args['secret'] ?? '').toString().trim();
            final nickname = (args['nickname'] ?? '').toString().trim();
            if (secret.isEmpty) {
              return {'ok': false, 'message': 'Missing secret'};
            }

            final deviceId = await DeviceIdentityService.getDeviceId();
            final platform = Platform.isWindows
                ? 'windows'
                : Platform.isMacOS
                ? 'macos'
                : Platform.isLinux
                ? 'linux'
                : 'desktop';

            final token = await DeviceLinkService().linkWithSecret(
              secret: secret,
              deviceId: deviceId,
              platform: platform,
              appVersion: 'desktop',
              nickname: nickname.isNotEmpty ? nickname : null,
            );

            await FirebaseAuth.instance.signInWithCustomToken(token);
            final signedIn = FirebaseAuth.instance.currentUser;
            // Ensure providers hydrate immediately even if proxy updates lag.
            // ignore: discarded_futures
            context.read<CreditProvider>().setUser(signedIn);
            // ignore: discarded_futures
            context.read<EntitlementProvider>().setUser(signedIn);
            // ignore: discarded_futures
            context.read<UiPrefsProvider>().setUser(signedIn);
            await SyncCoordinator().syncAll();
            return {'ok': true};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        if (call.method == 'pcLinkGetStatus') {
          final u = FirebaseAuth.instance.currentUser;
          int? creditBalance;
          int? proDays;
          int? premiumDays;
          bool? creditHydrated;
          bool? entitlementHydrated;
          try {
            final credit = context.read<CreditProvider>();
            creditBalance = credit.balance;
            creditHydrated = credit.hydrated;
          } catch (_) {}
          try {
            final ent = context.read<EntitlementProvider>();
            final b = ent.balanceAt(DateTime.now());
            proDays = b.proDays;
            premiumDays = b.premiumDays;
            entitlementHydrated = ent.hydrated;
          } catch (_) {}
          return {
            'ok': true,
            'uid': u?.uid,
            'isAnonymous': u?.isAnonymous ?? false,
            'email': u?.email,
            'displayName': u?.displayName,
            'creditBalance': creditBalance,
            'creditHydrated': creditHydrated,
            'proDays': proDays,
            'premiumDays': premiumDays,
            'entitlementHydrated': entitlementHydrated,
          };
        }
        if (call.method == 'pcLinkSignOut') {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null && !user.isAnonymous) {
              final deviceId = await DeviceIdentityService.getDeviceId();
              await DeviceLinkService().revokeDevice(deviceId);
            }
            await FirebaseAuth.instance.signOut();
            return {'ok': true};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        if (call.method == 'resetAllData') {
          try {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
            final includeRemote = args['includeRemote'] != false;
            await AccountDataResetService.resetAll(
              includeRemote: includeRemote,
            );
            return {'ok': true};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        if (call.method == 'billingRedeemCoupon') {
          try {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
            final code = (args['code'] ?? '').toString().trim();
            if (code.isEmpty) {
              return {'ok': false, 'message': 'Missing code'};
            }
            final resp = await BillingService().redeemCoupon(code: code);
            // ignore: discarded_futures
            context.read<CreditProvider>().refresh();
            // ignore: discarded_futures
            context.read<EntitlementProvider>().refresh();
            return {'ok': true, ...resp};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        if (call.method == 'billingDebugResetCouponRedemptionNonce') {
          try {
            final resp = await BillingService().debugResetCouponRedemptionNonce();
            return {'ok': true, ...resp};
          } catch (e) {
            return {'ok': false, 'message': e.toString()};
          }
        }
        return null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      SyncCoordinator().syncAll();
    }
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

  void _logAuthState(User? user) {
    final uid = user?.uid;
    final isAnon = user?.isAnonymous ?? true;
    if (_lastLoggedUid == uid && _lastLoggedAnon == isAnon) return;
    _lastLoggedUid = uid;
    _lastLoggedAnon = isAnon;

    print("AUTH uid = ${FirebaseAuth.instance.currentUser?.uid}");
    print(
      "AUTH isAnonymous = ${FirebaseAuth.instance.currentUser?.isAnonymous}",
    );
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
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final supportsAuth = widget.supportsAuth;

    final entitlement = context.watch<EntitlementProvider>();
    final prefs = context.watch<UiPrefsProvider>();
    final now = DateTime.now();
    final canUsePro = entitlement.hydrated && entitlement.balanceAt(now).isAdFree;
    final fontFamily = canUsePro && prefs.fontFamily.trim().isNotEmpty
        ? prefs.fontFamily.trim()
        : null;
    final preset =
        canUsePro ? ThemePresets.byId(prefs.themePresetId) : ThemePresets.defaultPreset;
    final textScale = canUsePro ? prefs.textScale : 1.0;
    return MaterialApp(
      title: 'Dayscript',
      theme: buildLightTheme(fontFamily: fontFamily, preset: preset),
      darkTheme: buildDarkTheme(fontFamily: fontFamily, preset: preset),
      themeMode: _themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routes: supportsAuth ? {'/login': (_) => const LoginPage()} : const {},
      home: Consumer<app_auth.AuthProvider>(
        builder: (context, auth, _) {
          if (!supportsAuth) {
            // Desktop(Windows 등)에서 Firebase 미지원 시 로그인 건너뜀
            return PlannerHomePage(onThemeChange: _handleThemeChange);
          }
          if (!auth.isAuthenticated) {
            if (isDesktop) {
              return PcLinkPage(
                currentMode: _themeMode,
                onThemeChange: _handleThemeChange,
              );
            }
            return const LoginPage();
          }
          _logAuthState(auth.user);
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

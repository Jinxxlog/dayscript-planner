import 'dart:io' if (dart.library.html) 'platform_stub.dart' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) 'desktop_multi_window_stub.dart';
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/credit_shop_page.dart';
import 'pages/subscription_shop_page.dart';
import 'pages/coupon_page.dart';
import 'pages/font_settings_page.dart';
import 'pages/theme_settings_page.dart';
import 'services/auth_provider.dart' as app_auth;
import 'services/auth_service.dart';
import 'services/ads_debug_settings_provider.dart';
import 'services/entitlement_provider.dart';
import 'services/credit_provider.dart';
import 'services/ui_prefs_provider.dart';
import 'services/ads/ad_controller.dart';
import 'services/device_link_service.dart';
import 'services/account_data_reset_service.dart';
import 'services/external_link_service.dart';
import 'services/startup_service.dart';
import 'services/theme_service.dart';
import 'theme/themes.dart';
import 'theme/theme_presets.dart';
import 'widgets/subscription_badges.dart';

class MultiWindowApp extends StatefulWidget {
  final Map<String, dynamic> args;
  const MultiWindowApp({super.key, required this.args});

  @override
  State<MultiWindowApp> createState() => _MultiWindowAppState();
}

class _MultiWindowAppState extends State<MultiWindowApp> {
  final _themeService = ThemeService();
  ThemeMode _themeMode = ThemeMode.system;
  late final Future<void> _initFuture = _init();
  final bool _firebaseSupported =
      kIsWeb ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;
  bool _firebaseReady = false;

  Future<void> _init() async {
    if (_firebaseSupported) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        _firebaseReady = true;
      } catch (_) {
        _firebaseReady = false;
      }
    } else {
      _firebaseReady = false;
    }
    _themeMode = await _themeService.loadThemeMode();
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _themeService.saveThemeMode(mode);

    // Notify the main window on desktop so both windows stay in sync.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await DesktopMultiWindow.invokeMethod(
          0,
          'themeChanged',
          _modeToString(mode),
        );
      } catch (_) {
        // If the main window is not available, ignore.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.args['page'] ?? 'settings';
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Text('Firebase init failed: ${snapshot.error}'),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => app_auth.AuthProvider(enabled: _firebaseReady),
            ),
            ChangeNotifierProvider(create: (_) => AdsDebugSettingsProvider()),
            ChangeNotifierProxyProvider<
              app_auth.AuthProvider,
              EntitlementProvider
            >(
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
          child: Builder(
            builder: (context) {
              final entitlement = context.watch<EntitlementProvider>();
              final prefs = context.watch<UiPrefsProvider>();
              final now = DateTime.now();
              final canUsePro = entitlement.hydrated &&
                  entitlement.balanceAt(now).isAdFree;
              final fontFamily =
                  canUsePro && prefs.fontFamily.trim().isNotEmpty
                      ? prefs.fontFamily.trim()
                      : null;
              final preset = canUsePro
                  ? ThemePresets.byId(prefs.themePresetId)
                  : ThemePresets.defaultPreset;
              final textScale = canUsePro ? prefs.textScale : 1.0;

              return MaterialApp(
                debugShowCheckedModeBanner: false,
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
                routes: {'/login': (_) => const LoginPage()},
                home: type == 'settings'
                    ? SettingsHomePage(
                        currentMode: _themeMode,
                        onThemeChange: _updateTheme,
                        authEnabled: _firebaseReady,
                      )
                    : const Scaffold(
                        body: Center(child: Text('Unknown window type')),
                      ),
              );
            },
          ),
        );
      },
    );
  }

  // Legacy build (unused)
  Widget _legacyBuild(BuildContext context) {
    final type = widget.args['page'] ?? 'settings';
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Text('Firebase init failed: ${snapshot.error}'),
              ),
            ),
          );
        }

        return MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => app_auth.AuthProvider(enabled: _firebaseReady),
            ),
            ChangeNotifierProvider(create: (_) => AdsDebugSettingsProvider()),
            ChangeNotifierProxyProvider<
              app_auth.AuthProvider,
              EntitlementProvider
            >(
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
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: _themeMode,
            routes: {'/login': (_) => const LoginPage()},
            home: type == 'settings'
                ? SettingsHomePage(
                    currentMode: _themeMode,
                    onThemeChange: _updateTheme,
                    authEnabled: _firebaseReady,
                  )
                : const Scaffold(
                    body: Center(child: Text('Unknown window type')),
                  ),
          ),
        );
      },
    );
  }
}

class SettingsHomePage extends StatefulWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onThemeChange;
  final bool authEnabled;
  const SettingsHomePage({
    super.key,
    required this.currentMode,
    required this.onThemeChange,
    required this.authEnabled,
  });

  @override
  State<SettingsHomePage> createState() => _SettingsHomePageState();

  // Legacy build (unused)
  Widget _legacyBuild(BuildContext context) {
    final auth = context.watch<app_auth.AuthProvider>();
    final user = auth.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileCard(
            user: user,
            isDark: isDark,
            authEnabled: authEnabled,
            isDesktop:
                Platform.isWindows || Platform.isLinux || Platform.isMacOS,
            onLoginTap: () => Navigator.pushNamed(context, '/login'),
            onGuest: () async {
              await AuthService().signOut();
              await AuthService().signInAnonymously();
            },
          ),
          const SizedBox(height: 24),
          const SectionTitle('화면'),
            _SettingsTile(
              title: '테마',
              subtitle: _modeLabel(currentMode),
              icon: Icons.dark_mode,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThemeSettingsPage(
                    currentMode: currentMode,
                    onThemeModeChanged: onThemeChange,
                    persistViaMainWindow: true,
                  ),
                ),
              ),
            ),
          _SettingsTile(
            title: '글씨',
            subtitle: '글씨체 설정',
            icon: Icons.font_download,
            onTap: (authEnabled && user != null)
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FontSettingsPage()),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          const SectionTitle('데이터'),
          _SettingsTile(
            title: '모든 데이터 삭제',
            subtitle: '현재 기기에 저장된 모든 데이터를 삭제합니다.',
            icon: Icons.delete_forever,
            onTap: () => _confirm(
              context,
              title: 'Reset all data',
              message: 'This will remove all local data. Continue?',
              onConfirm: () async {},
              isDestructive: true,
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('추가 기능'),
          _SettingsTile(
            title: '주간 퀘스트',
            subtitle: '주간 목표 설정',
            icon: Icons.flag,
            onTap: () {},
          ),
          _SettingsTile(
            title: '구독',
            subtitle: '개발 중입니다.',
            icon: Icons.workspace_premium,
            onTap: () {},
          ),
          const SizedBox(height: 24),
          const SectionTitle('정보'),
          _SettingsTile(
            title: '앱 정보',
            subtitle: '버전 및 제작자',
            icon: Icons.info_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppInfoPage()),
            ),
          ),
          _SettingsTile(
            title: '릴리즈 노트',
            subtitle: '업데이트 내역',
            icon: Icons.update,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReleaseNotesPage()),
            ),
          ),
          _SettingsTile(
            title: '시작프로그램 등록',
            subtitle: 'PC 시작프로그램 등록 여부를 결정합니다.',
            icon: Icons.keyboard,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StartUpProgram()),
            ),
          ),
          const SizedBox(height: 24),
          if (authEnabled && user != null) ...[
            const SectionTitle('계정'),
            _SettingsTile(
              title: '로그아웃',
              subtitle: user.isAnonymous ? 'Log out from guest' : 'Log out',
              icon: Icons.logout,
              iconColor: Colors.grey,
              onTap: () => _confirm(
                context,
                title: '로그아웃',
                message: '로그아웃 하시겠습니까?',
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().signOut(),
              ),
            ),
            _SettingsTile(
              title: '계정삭제',
              subtitle: '계정을 삭제합니다.',
              icon: Icons.warning_amber,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: () => _confirm(
                context,
                title: '계정 삭제',
                message: '계정을 정말 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.',
                isDestructive: true,
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().deleteAccount(),
              ),
            ),
          ] else if (!authEnabled) ...[
            const SectionTitle('계정'),
            _SettingsTile(
              title: '계정 사용 불가',
              subtitle: 'PC에서는 계정 기능을 사용할 수 없습니다.',
              icon: Icons.lock,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsHomePageState extends State<SettingsHomePage> {
  static const String _pcProgramDownloadUrl =
      'https://www.studio-read.me/projects/dayscript';

  DeviceLinkService? _deviceLinkService;
  bool _issuing = false;
  Map<String, dynamic>? _pcLinkStatus;
  bool _pcStatusLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.authEnabled) {
      _deviceLinkService = DeviceLinkService();
    }
    _refreshPcLinkStatus();
    if (_isDesktop) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _refreshPcLinkStatus();
      });
    }
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get _pcIsLinked {
    final uid = _pcLinkStatus?['uid']?.toString();
    final isAnonymous = _pcLinkStatus?['isAnonymous'] == true;
    return uid != null && uid.isNotEmpty && !isAnonymous;
  }

  String? get _pcLinkedAccountLabel {
    if (!_pcIsLinked) return null;
    final email = _pcLinkStatus?['email']?.toString();
    final uid = _pcLinkStatus?['uid']?.toString();
    if (email != null && email.isNotEmpty) return email;
    return uid;
  }

  Future<void> _refreshPcLinkStatus() async {
    if (!_isDesktop) return;
    setState(() => _pcStatusLoading = true);
    try {
      final resp = await DesktopMultiWindow.invokeMethod(
        0,
        'pcLinkGetStatus',
        {},
      );
      if (resp is Map) {
        _pcLinkStatus = resp.cast<String, dynamic>();
      } else {
        _pcLinkStatus = null;
      }
    } catch (_) {
      _pcLinkStatus = null;
    } finally {
      if (mounted) setState(() => _pcStatusLoading = false);
    }
  }

  Future<void> _promptPcLinkViaMainWindow() async {
    final secretController = TextEditingController();
    final nicknameController = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('모바일 데이터 연결'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('모바일 앱에서 발급한 연결 키를 입력해주세요.'),
              const SizedBox(height: 12),
              TextField(
                controller: secretController,
                decoration: const InputDecoration(
                  labelText: '연결 키 (필수)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(
                  labelText: '호칭 등록 (선택)',
                  border: OutlineInputBorder(),
                ),
                maxLength: 30,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('연결'),
            ),
          ],
        ),
      );
      if (submitted != true) return;

      final secret = secretController.text.trim();
      final nickname = nicknameController.text.trim();
      if (secret.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('연결 키를 입력해주세요.')));
        return;
      }

      final resp = await DesktopMultiWindow.invokeMethod(
        0,
        'pcLinkWithSecret',
        {'secret': secret, if (nickname.isNotEmpty) 'nickname': nickname},
      );
      final ok = resp is Map ? (resp['ok'] == true) : false;
      final message = resp is Map ? (resp['message']?.toString()) : null;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '성공적으로 연결되었습니다.' : (message ?? '연결에 실패했습니다.')),
        ),
      );
      if (ok) {
        await _refreshPcLinkStatus();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('메인 창과 통신하지 못했습니다: $e')));
    } finally {
      secretController.dispose();
      nicknameController.dispose();
    }
  }

  Future<void> _showPcProgramDownloadDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('PC 프로그램 다운로드'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('아래 링크를 복사하거나 열 수 있어요.'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(dialogContext).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SelectableText(_pcProgramDownloadUrl),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('닫기'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: _pcProgramDownloadUrl),
              );
              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('링크를 복사했습니다.')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('복사'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final ok = await ExternalLinkService.open(_pcProgramDownloadUrl);
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('열기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<app_auth.AuthProvider>();
    final user = auth.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle('프로필'),
          _ProfileCard(
            user: user,
            isDark: isDark,
            authEnabled: widget.authEnabled,
            isDesktop: _isDesktop,
            onLoginTap: () => Navigator.pushNamed(context, '/login'),
            onGuest: () async {
              await AuthService().signOut();
              await AuthService().signInAnonymously();
            },
            desktopCreditBalance:
                (_pcLinkStatus?['creditBalance'] as num?)?.toInt(),
            desktopProDays: (_pcLinkStatus?['proDays'] as num?)?.toInt(),
            desktopPremiumDays:
                (_pcLinkStatus?['premiumDays'] as num?)?.toInt(),
          ),
          const SizedBox(height: 24),
          const SectionTitle('계정 연동'),
          if (_isDesktop) ...[
            _SettingsTile(
              title: '연결 계정',
              subtitle: _pcStatusLoading
                  ? '불러오는 중...'
                  : _pcIsLinked
                  ? (_pcLinkedAccountLabel ?? '연결됨')
                  : '연결된 계정이 없습니다.',
              icon: Icons.link,
              onTap: _pcStatusLoading ? null : _refreshPcLinkStatus,
            ),
            _SettingsTile(
              title: '연결 키 입력하기',
              subtitle: _pcIsLinked
                  ? '이미 연동된 상태입니다. 먼저 연결을 해제해 주세요.'
                  : '모바일에서 발급한 연결 키를 입력합니다.',
              icon: Icons.vpn_key_outlined,
              onTap: _pcIsLinked ? null : _promptPcLinkViaMainWindow,
            ),
            _SettingsTile(
              title: '연결 해제하기',
              subtitle: _pcIsLinked ? '이 PC의 계정 연동을 해제합니다.' : '연결된 계정이 없습니다.',
              icon: Icons.link_off,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: _pcIsLinked
                  ? () => _confirm(
                      context,
                      title: '연결 해제',
                      message: '이 PC의 계정 연동을 해제할까요?',
                      isDestructive: true,
                      onConfirm: () async {
                        try {
                          await DesktopMultiWindow.invokeMethod(
                            0,
                            'pcLinkSignOut',
                            {},
                          );
                          await _refreshPcLinkStatus();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('연결을 해제했습니다.')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('연결 해제 실패: $e')),
                          );
                        }
                      },
                    )
                  : null,
            ),
          ] else ...[
            _SettingsTile(
              title: 'PC 연결 키 발급',
              subtitle: 'PC에서 연결 키 입력 후 연동할 수 있어요.',
              icon: Icons.vpn_key_outlined,
              onTap: (widget.authEnabled && user != null && !_issuing)
                  ? _issueKey
                  : null,
            ),
            _SettingsTile(
              title: '연결된 PC',
              subtitle: '연결된 PC를 확인/관리합니다.',
              icon: Icons.devices_other,
              onTap: (widget.authEnabled && user != null)
                  ? _showConnectedPcSheet
                  : null,
            ),
            _SettingsTile(
              title: 'PC 프로그램 다운로드',
              subtitle: 'PC 프로그램 다운로드 링크를 복사/열 수 있어요.',
              icon: Icons.download_outlined,
              onTap: _showPcProgramDownloadDialog,
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('화면'),
          _SettingsTile(
            title: '테마',
            subtitle: '${_modeLabel(widget.currentMode)} · 캘린더 테마를 변경합니다.',
            icon: Icons.dark_mode,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ThemeSettingsPage(
                  currentMode: widget.currentMode,
                  onThemeModeChanged: widget.onThemeChange,
                  persistViaMainWindow: true,
                  canUseProOverride: _pcLinkStatus == null
                      ? null
                      : (((_pcLinkStatus?['proDays'] as num?)?.toInt() ?? 0) >
                              0 ||
                          ((_pcLinkStatus?['premiumDays'] as num?)?.toInt() ??
                                  0) >
                              0),
                ),
              ),
            ),
          ),
          _SettingsTile(
            title: '폰트',
            subtitle: '글씨체를 변경합니다.',
              icon: Icons.font_download,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FontSettingsPage(
                    persistViaMainWindow: true,
                    signedInOverride: _pcLinkStatus == null
                        ? null
                        : (_pcLinkStatus?['isAnonymous'] != true &&
                            (_pcLinkStatus?['uid']?.toString().isNotEmpty ??
                                false)),
                    canUseProOverride: _pcLinkStatus == null
                        ? null
                        : (((_pcLinkStatus?['proDays'] as num?)?.toInt() ?? 0) >
                                0 ||
                            ((_pcLinkStatus?['premiumDays'] as num?)?.toInt() ??
                                    0) >
                                0),
                  ),
                ),
              ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('데이터'),
          if (!_isDesktop && (Platform.isAndroid || Platform.isIOS))
            _SettingsTile(
              title: '구독',
              subtitle: '준비중',
              icon: Icons.workspace_premium,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionShopPage()),
              ),
            ),
          if (kDebugMode)
            _SettingsTile(
              title: '쿠폰',
              subtitle: '디버그',
              icon: Icons.confirmation_number_outlined,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CouponPage()),
                );
                if (!mounted) return;
                await _refreshPcLinkStatus();
              },
            ),
          _SettingsTile(
            title: '데이터 초기화',
            subtitle: '모든 데이터 삭제',
            icon: Icons.delete_forever,
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: () => _confirm(
              context,
              title: '데이터 초기화',
              message: '현재 계정에 저장된 모든 데이터를 삭제합니다. 이 작업은 되돌릴 수 없습니다. 진행하시겠습니까?',
              onConfirm: () async {
                if (!context.mounted) return;
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const AlertDialog(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text('초기화 중...')),
                      ],
                    ),
                  ),
                );
                String? errorMessage;
                try {
                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) {
                    final resp = await DesktopMultiWindow.invokeMethod(
                      0,
                      'resetAllData',
                      {'includeRemote': true},
                    );
                    final ok = resp is Map ? (resp['ok'] == true) : false;
                    if (!ok) {
                      errorMessage = resp is Map
                          ? (resp['message']?.toString() ?? 'Unknown error')
                          : 'Unknown error';
                    }
                  } else {
                    await AccountDataResetService.resetAll(includeRemote: true);
                  }
                } catch (e) {
                  errorMessage = e.toString();
                } finally {
                  if (context.mounted) Navigator.of(context).pop();
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      errorMessage == null
                          ? '데이터가 초기화되었습니다.'
                          : '일부 데이터 삭제에 실패했어요. 네트워크 확인 후 다시 시도해주세요.\n$errorMessage',
                    ),
                  ),
                );
              },
              isDestructive: true,
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('정보'),
          _SettingsTile(
            title: '앱 정보',
            subtitle: 'Studio ReadMe / DayScript v1.0.0 / Contact',
            icon: Icons.info_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppInfoPage()),
            ),
          ),
          _SettingsTile(
            title: '업데이트 노트',
            subtitle: '각 업데이트별 변경사항',
            icon: Icons.update,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReleaseNotesPage()),
            ),
          ),
          _SettingsTile(
            title: '개인정보 처리방침',
            subtitle: '링크 바로가기',
            icon: Icons.privacy_tip_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
            ),
          ),
          if (_isDesktop) ...[
            _SettingsTile(
              title: 'PC 시작프로그램 설정',
              subtitle: '윈도우 시작 시 자동 실행',
              icon: Icons.keyboard,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StartUpProgram()),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('계정'),
          if (_isDesktop) ...[
            _SettingsTile(
              title: '사용 불가',
              subtitle: 'PC에서는 계정 관리 기능을 제공하지 않습니다.',
              icon: Icons.lock,
              onTap: () {},
            ),
          ] else if (widget.authEnabled && user != null) ...[
            _SettingsTile(
              title: '로그아웃',
              subtitle: user.isAnonymous ? '게스트 로그아웃' : '로그아웃',
              icon: Icons.logout,
              onTap: () => _confirm(
                context,
                title: '로그아웃',
                message: '로그아웃 할까요?',
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().signOut(),
              ),
            ),
            _SettingsTile(
              title: '회원 탈퇴',
              subtitle: '계정 삭제',
              icon: Icons.warning_amber,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: () => _confirm(
                context,
                title: '회원 탈퇴',
                message: '계정을 영구 삭제할까요?\n이 작업은 되돌릴 수 없습니다.',
                isDestructive: true,
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().deleteAccount(),
              ),
            ),
          ] else if (!widget.authEnabled) ...[
            _SettingsTile(
              title: '사용 불가',
              subtitle: '이 기기에서는 계정 기능을 사용할 수 없습니다.',
              icon: Icons.lock,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showConnectedPcSheet() async {
    if (_deviceLinkService == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결된 PC 정보를 불러올 수 없습니다.')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.7;
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '연결된 PC',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<DeviceInfo>>(
                  stream: _deviceLinkService!.watchDevices(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('연결된 PC를 불러오지 못했습니다: ${snapshot.error}'),
                      );
                    }
                    final devices = (snapshot.data ?? [])
                        .where((d) => d.status != 'revoked')
                        .toList();
                    if (devices.isEmpty) {
                      return const Center(child: Text('연결된 PC가 없습니다.'));
                    }
                    return ListView(
                      children: devices.map((d) => _deviceTile(d)).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPcLinkSection(User? user, bool authEnabled) {
    if (!authEnabled) {
      final uid = _pcLinkStatus?['uid']?.toString();
      final isAnonymous = _pcLinkStatus?['isAnonymous'] == true;
      final email = _pcLinkStatus?['email']?.toString();
      final linked = uid != null && uid.isNotEmpty && !isAnonymous;

      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.computer),
              title: Text(linked ? 'Linked' : 'Not linked'),
              subtitle: Text(
                linked
                    ? 'Account: ${email?.isNotEmpty == true ? email : uid}'
                    : 'Currently using local data on this PC.',
              ),
              trailing: _pcStatusLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Refresh',
                      onPressed: _refreshPcLinkStatus,
                      icon: const Icon(Icons.refresh),
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('연결 키 입력하기'),
              subtitle: Text(
                linked
                    ? '이미 연동된 상태입니다. 다른 계정을 연결하려면 먼저 해제해 주세요.'
                    : '모바일에서 발급한 연결 키를 입력합니다.',
              ),
              enabled: !linked,
              onTap: linked ? null : _promptPcLinkViaMainWindow,
            ),
            if (linked) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('이 PC 연결 해제'),
                subtitle: const Text('연결을 해제하고 로컬 모드로 전환합니다.'),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('연결 해제'),
                      content: const Text('이 PC의 계정 연동을 해제할까요?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('해제'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    final res = await DesktopMultiWindow.invokeMethod(
                      0,
                      'pcLinkSignOut',
                      {},
                    );
                    final ok = res is Map ? (res['ok'] == true) : false;
                    final message = res is Map
                        ? (res['message']?.toString())
                        : null;
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? '연결을 해제했습니다. 로컬 저장소 적용을 위해 앱을 재시작해 주세요.'
                              : (message ?? '연결 해제에 실패했습니다.'),
                        ),
                      ),
                    );
                    await _refreshPcLinkStatus();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('메인 창과 통신하지 못했습니다: $e')),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      );
    }
    if (_deviceLinkService == null) {
      return _SettingsTile(
        title: 'PC 연동',
        subtitle: '이 창에서는 사용할 수 없는 기능입니다.',
        icon: Icons.computer,
        onTap: () {},
      );
    }
    if (user == null) {
      return _SettingsTile(
        title: 'PC 연동',
        subtitle: '로그인 후 PC를 연동할 수 있어요.',
        icon: Icons.login,
        onTap: () => Navigator.pushNamed(context, '/login'),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('PC 연결 키 발급'),
              subtitle: const Text('모바일 앱과 PC 프로그램을 연동합니다.'),
              trailing: _issuing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _issuing ? null : _issueKey,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: const [
                  Icon(Icons.devices_other, size: 20),
                  SizedBox(width: 8),
                  Text('연결된 PC', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            StreamBuilder<List<DeviceInfo>>(
              stream: _deviceLinkService!.watchDevices(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 12,
                    ),
                    child: Text(
                      '연결된 PC를 불러오는 중 오류가 발생했습니다: ${snapshot.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  );
                }
                final devices = (snapshot.data ?? [])
                    .where((d) => d.status != 'revoked')
                    .toList();
                if (devices.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('연결된 PC가 없습니다.', textAlign: TextAlign.center),
                  );
                }
                return Column(
                  children: devices.map((d) => _deviceTile(d)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(DeviceInfo device) {
    final isRevoked = device.status == 'revoked';
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.computer, color: isRevoked ? Colors.grey : null),
          title: Text(device.nickname),
          subtitle: Text(
            '${device.platform} | ${device.deviceId}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '호칭 변경',
                icon: const Icon(Icons.edit, size: 20),
                onPressed: isRevoked ? null : () => _renameDevice(device),
              ),
              IconButton(
                tooltip: '연동 해제',
                icon: const Icon(Icons.link_off, size: 20),
                onPressed: () => _revokeDevice(device),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _issueKey() async {
    final svc = _deviceLinkService;
    if (svc == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 창에서는 사용할 수 없는 기능입니다.')));
      return;
    }
    setState(() => _issuing = true);
    try {
      final result = await svc.issueLinkKey();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          final now = DateTime.now();
          final expiresAt = result.expiresAt?.toLocal();
          final expireText = expiresAt == null
              ? '만료 시간 정보를 가져올 수 없습니다.'
              : (() {
                  final diff = expiresAt.difference(now);
                  final stamp = expiresAt.toString().substring(0, 16);
                  if (diff.isNegative) return '만료: $stamp (이미 만료됨)';
                  final mins = diff.inMinutes;
                  final secs = diff.inSeconds % 60;
                  final remain = mins > 0
                      ? '${mins}분 ${secs}초 남음'
                      : '${secs}초 남음';
                  return '만료: $stamp ($remain)';
                })();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PC 연결 키',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('한 번만 표시됩니다. 복사한 뒤 PC에 입력해주세요.'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    result.secret,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  expireText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '만료 후에는 새 연결 키를 다시 발급받아야 합니다.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: result.secret));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('복사되었습니다.')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('복사'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('연결 키 발급 실패: $e')));
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _renameDevice(DeviceInfo device) async {
    final svc = _deviceLinkService;
    if (svc == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 창에서는 사용할 수 없는 기능입니다.')));
      return;
    }
    final controller = TextEditingController(text: device.nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PC 호칭 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'PC 이름을 입력하세요'),
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == device.nickname) return;
    try {
      await svc.updateNickname(device.deviceId, result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름이 변경되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('이름 변경에 실패했습니다: $e')));
    }
  }

  Future<void> _revokeDevice(DeviceInfo device) async {
    final svc = _deviceLinkService;
    if (svc == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 창에서는 사용할 수 없는 기능입니다.')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('연결 해제'),
        content: Text('이 PC의 연동을 해제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('연결 해제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await svc.revokeDevice(device.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결 해제.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('연결 해제 실패: $e')));
    }
  }
}

class _ProfileCard extends StatelessWidget {
  final User? user;
  final bool isDark;
  final bool authEnabled;
  final bool isDesktop;
  final VoidCallback onLoginTap;
  final VoidCallback onGuest;
  final int? desktopCreditBalance;
  final int? desktopProDays;
  final int? desktopPremiumDays;
  const _ProfileCard({
    required this.user,
    required this.isDark,
    required this.authEnabled,
    required this.isDesktop,
    required this.onLoginTap,
    required this.onGuest,
    this.desktopCreditBalance,
    this.desktopProDays,
    this.desktopPremiumDays,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = user != null;
    final avatarBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final providers = isLoggedIn
        ? user!.providerData.map((p) => p.providerId).toList()
        : [];
    final googleLinked = providers.contains('google.com');
    final supportsPurchase =
        !isDesktop && (Platform.isAndroid || Platform.isIOS);
    final isGuest = isLoggedIn && (user?.isAnonymous ?? false);
    final creditBalance = (isDesktop && desktopCreditBalance != null)
        ? desktopCreditBalance!
        : context.watch<CreditProvider>().balance;

    final effectiveProDays =
        (isDesktop && desktopProDays != null) ? desktopProDays : null;
    final effectivePremiumDays =
        (isDesktop && desktopPremiumDays != null) ? desktopPremiumDays : null;

    void showGuestBlockedDialog() {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('결제 불가'),
          content: const Text('게스트 사용자는 결제 기능을 사용할 수 없습니다.\n로그인 후 이용해주세요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/login');
              },
              child: const Text('로그인'),
            ),
          ],
        ),
      );
    }

    final nameText = !authEnabled
        ? '로그인 기능을 사용할 수 없습니다.'
        : isLoggedIn
        ? (user!.displayName ??
              user!.email ??
              (user!.isAnonymous ? '게스트' : '사용자'))
        : '로그인이 필요합니다.';

    final detailText = !authEnabled
        ? '이 기기에서는 계정 기능을 사용할 수 없습니다.'
        : isLoggedIn
        ? (user!.email ?? (user!.isAnonymous ? '게스트 계정' : ''))
        : '로그인하면 동기화 기능을 사용할 수 있어요.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: avatarBg,
                backgroundImage: isLoggedIn && user!.photoURL != null
                    ? NetworkImage(user!.photoURL!)
                    : null,
                child: !isLoggedIn
                    ? Icon(
                        Icons.person,
                        size: 32,
                        color: isDark ? Colors.black : Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          nameText,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (!isDesktop && googleLinked)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Google',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (isDesktop &&
                            (effectiveProDays != null ||
                                effectivePremiumDays != null))
                          _SubscriptionBadgesOverride(
                            proDays: effectiveProDays ?? 0,
                            premiumDays: effectivePremiumDays ?? 0,
                          )
                        else
                          const SubscriptionBadges(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isDesktop) ...[
                      const SizedBox(height: 8),
                      Text(
                        'PC에서는 소셜 로그인을 사용할 수 없습니다.',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
          const SizedBox(height: 10),
          // Legacy credit/subscription actions UI (kept for reference).
          if (false) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '크레딧: $creditBalance',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (supportsPurchase)
                  FilledButton(
                    onPressed: (!authEnabled || !isLoggedIn)
                        ? onLoginTap
                        : isGuest
                        ? showGuestBlockedDialog
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreditShopPage(),
                            ),
                          ),
                    child: const Text('크레딧 충전'),
                  ),
              ],
            ),
            if (supportsPurchase) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: (!authEnabled || !isLoggedIn)
                      ? onLoginTap
                      : isGuest
                      ? showGuestBlockedDialog
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionShopPage(),
                          ),
                        ),
                  child: const Text('구독 구매'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                '결제/구독 구매는 모바일에서만 가능합니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.toll_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '$creditBalance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (supportsPurchase)
                FilledButton.icon(
                  onPressed: (!authEnabled || !isLoggedIn)
                      ? onLoginTap
                      : isGuest
                      ? showGuestBlockedDialog
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreditShopPage(),
                          ),
                        ),
                  icon: const Icon(Icons.add),
                  label: const Text('충전'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            supportsPurchase
                ? '구독 구매는 설정의 구독 탭에서 가능합니다.'
                : '결제/구독 구매는 모바일에서만 가능합니다.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isDesktop && authEnabled && !isLoggedIn) ...[
            FilledButton(onPressed: onLoginTap, child: const Text('로그인')),
            TextButton(onPressed: onGuest, child: const Text('게스트로 시작')),
          ],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SubscriptionBadgesOverride extends StatelessWidget {
  final int proDays;
  final int premiumDays;
  const _SubscriptionBadgesOverride({
    required this.proDays,
    required this.premiumDays,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (premiumDays > 0) {
      chips.add(_badge(
        label: 'Premium',
        days: premiumDays,
        bg: const Color(0xFF9575CD),
        fg: Colors.white,
      ));
    }
    if (proDays > 0) {
      chips.add(_badge(
        label: 'Pro',
        days: proDays,
        bg: const Color(0xFF1E88E5),
        fg: Colors.white,
      ));
    }
    if (chips.isEmpty) {
      chips.add(_badge(
        label: 'Standard',
        days: null,
        bg: Colors.white,
        fg: Colors.black87,
        border: Colors.black12,
      ));
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _badge({
    required String label,
    required Color bg,
    required Color fg,
    int? days,
    Color? border,
  }) {
    final text = (days == null || days <= 0) ? label : '$label ${days}d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? textColor;
  const _SettingsTile({
    required this.title,
    required this.icon,
    this.onTap,
    this.subtitle,
    this.iconColor,
    this.textColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null;
    final cardColor = isDark ? theme.colorScheme.surfaceVariant : Colors.white;
    final iconBg = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.grey.shade200;
    final iconColorResolved =
        iconColor ?? (isDark ? Colors.white.withOpacity(0.9) : Colors.black87);
    final primaryTextBase = textColor ?? theme.colorScheme.onSurface;
    final primaryText = enabled
        ? primaryTextBase
        : primaryTextBase.withOpacity(0.5);
    final subColor = theme.colorScheme.onSurfaceVariant;
    final chevronColor = isDark ? Colors.white70 : Colors.grey.shade600;

    String? subtitleResolved = subtitle;
    if (icon == Icons.workspace_premium) {
      subtitleResolved =
          '\uAD11\uACE0 \uC81C\uAC70\uC640 \uAC19\uC740 \uCD94\uAC00 \uAE30\uB2A5\uC744 \uC9C0\uC6D0\uD569\uB2C8\uB2E4';
    } else if (icon == Icons.confirmation_number_outlined) {
      subtitleResolved = '\uCFE0\uD3F0 \uB4F1\uB85D\uD558\uAE30';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.25),
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        enabled: enabled,
        leading: Container(
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          width: 40,
          height: 40,
          child: Icon(icon, color: iconColorResolved),
        ),
        title: Text(title, style: TextStyle(fontSize: 16, color: primaryText)),
        subtitle: subtitleResolved != null
            ? Text(subtitleResolved!, style: TextStyle(color: subColor))
            : null,
        trailing: Icon(Icons.chevron_right, color: chevronColor),
        onTap: onTap,
      ),
    );
  }
}

String _providerLabel(String id) {
  switch (id) {
    case 'google.com':
      return 'Google';
    case 'apple.com':
      return 'Apple';
    case 'kakao.com':
      return 'Kakao';
    case 'naver.com':
      return 'Naver';
    case 'password':
      return 'Email';
    case 'phone':
      return 'Phone';
    case 'anonymous':
      return 'Guest';
    default:
      return id;
  }
}

String _modeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '라이트';
    case ThemeMode.dark:
      return '다크';
    default:
      return '시스템';
  }
}

Future<void> _showThemeDialog(
  BuildContext context,
  ThemeMode currentMode,
  ValueChanged<ThemeMode> onThemeChange,
) async {
  ThemeMode selected = currentMode;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('테마 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('시스템'),
                value: ThemeMode.system,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('라이트'),
                value: ThemeMode.light,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('다크'),
                value: ThemeMode.dark,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                onThemeChange(selected);
                Navigator.pop(context);
              },
              child: const Text('적용'),
            ),
          ],
        ),
      );
    },
  );
}

String _modeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    default:
      return 'system';
  }
}

Future<void> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() onConfirm,
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: isDestructive ? Colors.red : null,
            ),
            child: const Text('확인'),
          ),
        ],
      );
    },
  );
  if (result == true) {
    try {
      await onConfirm();
    } catch (e) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      String msg = '작업에 실패했어요. 다시 시도해주세요.';
      if (e is FirebaseAuthException) {
        if (e.code == 'requires-recent-login') {
          msg = '보안을 위해 다시 로그인 후 시도해주세요.';
        } else if (e.code == 'user-cancelled') {
          msg = '인증이 취소되었습니다.';
        } else if (e.message != null && e.message!.trim().isNotEmpty) {
          msg = e.message!;
        }
      } else if (e is PlatformException) {
        if (e.message != null && e.message!.trim().isNotEmpty) {
          msg = e.message!;
        }
      }

      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class StartUpProgram extends StatefulWidget {
  const StartUpProgram({super.key});

  @override
  State<StartUpProgram> createState() => _StartUpProgramState();
}

class _StartUpProgramState extends State<StartUpProgram> {
  bool _loading = true;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await StartupService.init();
      final enabled = await StartupService.isStartupEnabled();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _loading = true);
    try {
      await StartupService.setStartupEnabled(value);
      final actual = await StartupService.isStartupEnabled();
      if (!mounted) return;
      setState(() => _enabled = actual);
      if (actual != value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 PC 환경에서는 시작프로그램 설정을 적용할 수 없어요.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('설정 적용 실패: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('시작 프로그램 등록')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Platform.isWindows
            ? Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      value: _enabled,
                      onChanged: _loading ? null : _setEnabled,
                      title: const Text('Windows 시작 시 자동 실행'),
                      subtitle: Text(
                        _error != null ? '오류: $_error' : '앱을 부팅 시 자동으로 실행합니다.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('참고'),
                      subtitle: const Text('설치 방식/권한에 따라 동작이 제한될 수 있습니다.'),
                      trailing: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Refresh',
                              icon: const Icon(Icons.refresh),
                              onPressed: _load,
                            ),
                    ),
                  ],
                ),
              )
            : const Center(child: Text('이 기능은 Windows에서만 지원합니다.')),
      ),
    );
  }
}

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('앱 정보')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.apartment_outlined),
                  title: Text('Studio ReadMe'),
                ),
                Divider(height: 1, color: outline),
                const ListTile(
                  leading: Icon(Icons.apps_outlined),
                  title: Text('DayScript v1.0.0'),
                ),
                Divider(height: 1, color: outline),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Contact'),
                  subtitle: const Text('mir001125@naver.com'),
                  trailing: IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: 'mir001125@naver.com'),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('이메일을 복사했어요.')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReleaseNotesPage extends StatelessWidget {
  const ReleaseNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = <_ReleaseNote>[
      const _ReleaseNote(
        version: 'beta 1.0',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: [
              'PC 버전 릴리즈',
              '오버레이 기능 추가 및 UI 안정화',
              '캘린더: 주·월·연간 반복일정 / 사용자 지정 휴일 관리',
              'To-do: 요일별 투두 및 반복 일정 관리',
              '메모패드: 장기 유지 or 빠른 메모 가능',
            ],
          ),
        ],
      ),
      const _ReleaseNote(
        version: 'beta 1.1',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: [
              'PC 설치마법사 지원',
              '시작 프로그램 등록 기능 추가',
              '투두, 메모패드 축소/확대 기능 추가',
              '설정 페이지 구현',
            ],
          ),
          _ReleaseNoteSection(
            title: 'bug fix',
            items: ['투두 체크 여부가 매일 초기화되는 현상 수정', '반복 일정 등록 관련 버그 수정'],
          ),
        ],
      ),
      const _ReleaseNote(
        version: 'beta 1.2',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: [
              '캘린더 메모창 시스템 개편',
              '캘린더 메모 메커니즘 변경 및 카테고리 라벨링 추가',
              '메모패드 UI 개선',
            ],
          ),
        ],
      ),
      const _ReleaseNote(
        version: 'beta 1.3',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: ['모바일 반응형 UI 설계', 'Firebase 연동 준비 | 필드 추가 및 데이터 타입 리팩터링'],
          ),
        ],
      ),
      const _ReleaseNote(
        version: 'beta 1.3',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: [
              'Firebase Auth 기반 모바일 로그인 기능 구현(Google)',
              'PC 프로그램 | 소셜 기반 로그인이 아닌 key 기반 연동 시스템으로 재설계',
              'db 연동 | 로컬 저장소 스코프',
              '서버 보안 설계 | 서버 전용 키 API 구현 및 배포',
            ],
          ),
        ],
      ),
      const _ReleaseNote(
        version: 'beta 1.4',
        sections: [
          _ReleaseNoteSection(
            title: 'update',
            items: [
              '모바일 | PC 키 기반 연결 기능 구현',
              '결제 및 AD, 구독 관련 초기 세팅',
              'PC 버전 아이콘 변경',
              '초기 화면에 로고 삽입',
              '설정 창 개선',
            ],
          ),
        ],
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('업데이트 노트')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) => _ReleaseNoteCard(note: notes[index]),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: notes.length,
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    const url = 'https://www.studio-read.me/privacy';
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 처리방침')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DayScript는 일정 관리 서비스를 제공하기 위해 최소한의 개인정보만을 수집하며,\n'
                    '수집된 정보는 계정 인증, 데이터 동기화, 광고 제공 및 서비스 개선 목적 외에는 사용되지 않습니다.\n\n'
                    '자세한 내용은 전체 개인정보 처리방침을 참고해주세요.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('전체 개인정보 처리방침 보기'),
                    onPressed: () async {
                      final ok = await ExternalLinkService.open(url);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('링크를 열 수 없어요.')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseNote {
  final String version;
  final List<_ReleaseNoteSection> sections;
  const _ReleaseNote({required this.version, required this.sections});
}

class _ReleaseNoteSection {
  final String title;
  final List<String> items;
  const _ReleaseNoteSection({required this.title, required this.items});
}

class _ReleaseNoteCard extends StatelessWidget {
  final _ReleaseNote note;
  const _ReleaseNoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? theme.colorScheme.surfaceVariant : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.version,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final section in note.sections) ...[
              _SectionChip(text: section.title),
              const SizedBox(height: 8),
              for (final item in section.items) _Bullet(text: item),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  final String text;
  const _SectionChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('•  ', style: TextStyle(color: color)),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('구독')),
      body: const Center(child: Text('In production')),
    );
  }
}

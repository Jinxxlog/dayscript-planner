import 'dart:io' if (dart.library.html) 'platform_stub.dart' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) 'desktop_multi_window_stub.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'services/auth_provider.dart' as app_auth;
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'theme/themes.dart';

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
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
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
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
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

class SettingsHomePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final auth = context.watch<app_auth.AuthProvider>();
    final user = auth.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DayScript Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileCard(
            user: user,
            isDark: isDark,
            authEnabled: authEnabled,
            onLoginTap: () => Navigator.pushNamed(context, '/login'),
            onGuest: () async {
              await AuthService().signOut();
              await AuthService().signInAnonymously();
            },
          ),
          const SizedBox(height: 24),
          const SectionTitle('Display'),
          _SettingsTile(
            title: 'Theme',
            subtitle: _modeLabel(currentMode),
            icon: Icons.dark_mode,
            onTap: () => _showThemeDialog(context, currentMode, onThemeChange),
          ),
          _SettingsTile(
            title: 'Font',
            subtitle: 'Default',
            icon: Icons.font_download,
            onTap: () {},
          ),
          const SizedBox(height: 24),
          const SectionTitle('App data'),
          _SettingsTile(
            title: 'Reset all data',
            subtitle: 'Remove all local data',
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
          const SectionTitle('Extras'),
          _SettingsTile(
            title: 'Weekly quest',
            subtitle: 'Set weekly goals',
            icon: Icons.flag,
            onTap: () {},
          ),
          _SettingsTile(
            title: 'Premium',
            subtitle: 'Coming soon',
            icon: Icons.workspace_premium,
            onTap: () {},
          ),
          const SizedBox(height: 24),
          const SectionTitle('Info'),
          _SettingsTile(
            title: 'App info',
            subtitle: 'Version, author',
            icon: Icons.info_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppInfoPage()),
            ),
          ),
          _SettingsTile(
            title: 'Release notes',
            subtitle: 'Recent changes',
            icon: Icons.update,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReleaseNotesPage()),
            ),
          ),
          _SettingsTile(
            title: 'Launch on Windows startup',
            subtitle: 'Enable/disable',
            icon: Icons.keyboard,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StartUpProgram()),
            ),
          ),
          const SizedBox(height: 24),
          if (authEnabled && user != null) ...[
            const SectionTitle('Account'),
            _SettingsTile(
              title: 'Log out',
              subtitle: user.isAnonymous ? 'Log out from guest' : 'Log out',
              icon: Icons.logout,
              iconColor: Colors.grey,
              onTap: () => _confirm(
                context,
                title: 'Log out',
                message: 'Do you want to log out?',
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().signOut(),
              ),
            ),
            _SettingsTile(
              title: 'Delete account',
              subtitle: 'Cannot be undone',
              icon: Icons.warning_amber,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: () => _confirm(
                context,
                title: 'Delete account',
                message:
                    'Delete this account permanently?\nThis action cannot be undone.',
                isDestructive: true,
                onConfirm: () async =>
                    context.read<app_auth.AuthProvider>().deleteAccount(),
              ),
            ),
          ] else if (!authEnabled) ...[
            const SectionTitle('Account'),
            _SettingsTile(
              title: '로그인은 모바일/웹에서만 지원됩니다',
              subtitle: '현재 PC 설정창에서는 프로필을 사용할 수 없습니다',
              icon: Icons.lock,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final User? user;
  final bool isDark;
  final bool authEnabled;
  final VoidCallback onLoginTap;
  final VoidCallback onGuest;
  const _ProfileCard({
    required this.user,
    required this.isDark,
    required this.authEnabled,
    required this.onLoginTap,
    required this.onGuest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = user != null;
    final avatarBg = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final providers =
        isLoggedIn ? user!.providerData.map((p) => p.providerId).toList() : [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !authEnabled
                        ? '로그인은 PC 설정창에서 비활성화'
                        : isLoggedIn
                            ? (user!.displayName ??
                                user!.email ??
                                (user!.isAnonymous ? 'Guest' : 'User'))
                            : 'Sign in required',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    !authEnabled
                        ? '모바일/웹에서 로그인 후 동기화됩니다'
                        : isLoggedIn
                            ? (user!.email ??
                                (user!.isAnonymous ? 'Anonymous' : ''))
                            : 'Log in to manage account settings',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (providers.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: providers
                          .map(
                            (p) => Chip(
                              label: Text(_providerLabel(p)),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (authEnabled && !isLoggedIn) ...[
            FilledButton(
              onPressed: onLoginTap,
              child: const Text('Log in'),
            ),
            TextButton(
              onPressed: onGuest,
              child: const Text('Continue as guest'),
            ),
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

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;
  const _SettingsTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.textColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? theme.colorScheme.surfaceVariant : Colors.white;
    final iconBg =
        isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    final iconColorResolved =
        iconColor ?? (isDark ? Colors.white.withOpacity(0.9) : Colors.black87);
    final primaryText = textColor ?? theme.colorScheme.onSurface;
    final subColor = theme.colorScheme.onSurfaceVariant;
    final chevronColor = isDark ? Colors.white70 : Colors.grey.shade600;

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
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
        subtitle: subtitle != null
            ? Text(subtitle!, style: TextStyle(color: subColor))
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
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
    default:
      return 'System';
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
          title: const Text('Select theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('System'),
                value: ThemeMode.system,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Light'),
                value: ThemeMode.light,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Dark'),
                value: ThemeMode.dark,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                onThemeChange(selected);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: isDestructive ? Colors.red : null,
            ),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );
  if (result == true) {
    await onConfirm();
  }
}

class StartUpProgram extends StatelessWidget {
  const StartUpProgram({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Windows startup')),
      body: const Center(
        child: Text('Startup settings placeholder.'),
      ),
    );
  }
}

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App info')),
      body: const Center(
        child: Text('App info page placeholder.'),
      ),
    );
  }
}

class ReleaseNotesPage extends StatelessWidget {
  const ReleaseNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Release notes')),
      body: const Center(
        child: Text('Release notes page placeholder.'),
      ),
    );
  }
}

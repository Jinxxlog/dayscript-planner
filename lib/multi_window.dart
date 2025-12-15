import 'package:flutter/material.dart';
import 'services/startup_service.dart';   // ← 이거 반드시 추가
import 'services/theme_service.dart';
import 'theme/themes.dart';
import 'dart:io' show Platform;
import 'package:desktop_multi_window/desktop_multi_window.dart';

class MultiWindowApp extends StatefulWidget {
  final Map<String, dynamic> args;

  const MultiWindowApp({super.key, required this.args});

  @override
  State<MultiWindowApp> createState() => _MultiWindowAppState();
}

class _MultiWindowAppState extends State<MultiWindowApp> {
  final _themeService = ThemeService();
  ThemeMode _themeMode = ThemeMode.system;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await _themeService.loadThemeMode();
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _ready = true;
      });
    }
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _themeService.saveThemeMode(mode);
    // 메인 창에 테마 변경 알림 (윈도우 ID 0 가정)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await DesktopMultiWindow.invokeMethod(
            0, 'themeChanged', _modeToString(mode));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.args['page'] ?? 'settings';

    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: type == 'settings'
          ? SettingsHomePage(
              currentMode: _themeMode,
              onThemeChange: _updateTheme,
            )
          : Scaffold(
              body: Center(child: Text("Unknown window: $type")),
            ),
    );
  }
}

// ------------------------------------------------------------
//   ⚙️ 설정창 메인 페이지
// ------------------------------------------------------------
class SettingsHomePage extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onThemeChange;

  const SettingsHomePage({
    super.key,
    required this.currentMode,
    required this.onThemeChange,
  });

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = false; // TODO: Firebase Auth 연동 예정

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "DayScript 설정",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // --------------------
          // 프로필 카드
          // --------------------
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => isLoggedIn
                        ? const AccountSettingsPage()
                        : const LoginPage()),
              );
            },

            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    backgroundImage:
                        isLoggedIn ? NetworkImage("https://picsum.photos/200") : null,
                    child: !isLoggedIn
                        ? Icon(Icons.person,
                            size: 32,
                            color: isDark ? Colors.black : Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 14),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn ? "김진형" : "로그인하세요",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        isLoggedIn ? "jinhyeong@example.com" : "계정 설정을 위해 로그인",
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // --------------------
          // 디스플레이
          // --------------------
          const SectionTitle("디스플레이"),
          _SettingsTile(
            title: "테마 변경",
            subtitle: _modeLabel(currentMode),
            icon: Icons.dark_mode,
            onTap: () => _showThemeDialog(context, currentMode, onThemeChange),
          ),
          _SettingsTile(
            title: "글씨체 변경",
            subtitle: "기본",
            icon: Icons.font_download,
            onTap: () {},
          ),

          const SizedBox(height: 30),

          // --------------------
          // 앱 데이터
          // --------------------
          const SectionTitle("앱 데이터"),
          _SettingsTile(
            title: "데이터 전체 초기화",
            subtitle: "모든 데이터 삭제",
            icon: Icons.delete_forever,
            onTap: () {},
          ),

          const SizedBox(height: 30),

          // --------------------
          // 투두 게이미피케이션
          // --------------------
          const SectionTitle("추가 기능"),
          _SettingsTile(
            title: "주간 퀘스트 설정",
            subtitle: "1주일 목표 설정",
            icon: Icons.flag,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WeeklyQuestPage()),
              );
            },
          ),
          _SettingsTile(
            title: "프리미엄 구독",
            subtitle: "크레딧 / 프로필 테두리 / 백업",
            icon: Icons.workspace_premium,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PremiumPage()),
              );
            },
          ),

          const SizedBox(height: 30),

          // --------------------
          // 고급
          // --------------------
          const SectionTitle("고급"),
          _SettingsTile(
            title: "시작프로그램 등록",
            subtitle: "시작프로그램에 캘린더 등록하기",
            icon: Icons.keyboard,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StartUpProgram()),
              );
            },
          ),
          _SettingsTile(
            title: "릴리즈 노트",
            subtitle: "업데이트 기록 보기",
            icon: Icons.info_outline,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppInfoPage()),
              );
            },
          ),
          _SettingsTile(
            title: "앱 정보",
            subtitle: "버전 / 라이선스",
            icon: Icons.update,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReleaseNotesPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

String _modeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return "라이트";
    case ThemeMode.dark:
      return "다크";
    default:
      return "시스템";
  }
}

Future<void> _showThemeDialog(
    BuildContext context,
    ThemeMode currentMode,
    ValueChanged<ThemeMode> onThemeChange) async {
  ThemeMode selected = currentMode;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("테마 선택"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text("시스템 기본"),
                value: ThemeMode.system,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text("라이트"),
                value: ThemeMode.light,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text("다크"),
                value: ThemeMode.dark,
                groupValue: selected,
                onChanged: (v) => setState(() => selected = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소"),
            ),
            FilledButton(
              onPressed: () {
                onThemeChange(selected);
                Navigator.pop(context);
              },
              child: const Text("적용"),
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

// ------------------------------------------------------------
// 섹션 타이틀
// ------------------------------------------------------------
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

// ------------------------------------------------------------
// 공통 타일
// ------------------------------------------------------------
class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
        isDark ? theme.colorScheme.surfaceVariant : Colors.white;
    final iconBg =
        isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    final iconColor = isDark
        ? Colors.white.withOpacity(0.9)
        : Colors.black87;
    final textColor = theme.colorScheme.onSurface;
    final subColor = theme.colorScheme.onSurfaceVariant;
    final chevronColor =
        isDark ? Colors.white70 : Colors.grey.shade600;

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
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title,
            style: TextStyle(fontSize: 16, color: textColor)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: TextStyle(color: subColor))
            : null,
        trailing: Icon(Icons.chevron_right, color: chevronColor),
        onTap: onTap,
      ),
    );
  }
}

/////////////////////////////////////////////////////////////////
//   더미 상세 페이지 4종
/////////////////////////////////////////////////////////////////

class WeeklyQuestPage extends StatelessWidget {
  const WeeklyQuestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("주간 퀘스트 설정")),
      body: const Center(
        child: Text("주간 퀘스트 기능은 곧 업데이트됩니다!"),
      ),
    );
  }
}

class PremiumPage extends StatelessWidget {
  const PremiumPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("프리미엄 구독")),
      body: const Center(
        child: Text("프리미엄 기능은 준비 중입니다!"),
      ),
    );
  }
}


class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("앱 정보")),
      body: const Center(
        child: Text("DayScript beta 1.0.2\nStudio ReadMe 제작"),
      ),
    );
  }
}

class StartUpProgram extends StatefulWidget {
  const StartUpProgram({super.key});

  @override
  State<StartUpProgram> createState() => _StartUpProgramState();
}

class _StartUpProgramState extends State<StartUpProgram> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    StartupService.isStartupEnabled().then((v) {
      setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("시작프로그램 등록")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Windows 시작 시 자동 실행", style: TextStyle(fontSize: 16)),
              Switch(
                value: _enabled,
                onChanged: (v) async {
                  await StartupService.setStartupEnabled(v);
                  setState(() => _enabled = v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class ReleaseNotesPage extends StatelessWidget {
  const ReleaseNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> dummyNotes = [
      {
        "version": "Beta 1.00",
        "date": "2025-01-22",
        "details":
            "- 기본 캘린더 구조 완성\n"
            "- 투두 리스트 & 메모패드 동작 안정화\n"
            "- 다크모드 / 라이트모드 지원\n"
            "- 멀티윈도우 설정창 프로토타입"
      },
      {
        "version": "Alpha",
        "date": "2025-01-10",
        "details":
            "- 프로젝트 초기 설계 및 UI 베이스 구축\n"
            "- 테스트용 내부 개발 버전"
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("릴리즈 노트"),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: dummyNotes.length,
        itemBuilder: (context, index) {
          final note = dummyNotes[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note["version"]!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  note["date"]!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  note["details"]!,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

////////////////////////////////////////////////////////////////////
// 기존 계정 / 로그인 페이지 그대로 유지
////////////////////////////////////////////////////////////////////

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("계정 설정")),

      body: ListView(
        children: [
          _SettingsTile(
            title: "닉네임 변경",
            icon: Icons.edit,
            onTap: () {},
          ),
          _SettingsTile(
            title: "프로필 사진 변경",
            icon: Icons.image,
            onTap: () {},
          ),
          _SettingsTile(
            title: "로그아웃",
            icon: Icons.logout,
            onTap: () {},
          ),
          _SettingsTile(
            title: "회원탈퇴",
            icon: Icons.warning_amber,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("로그인")),
      body: const Center(
        child: Text("로그인 UI 개발 예정"),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class MultiWindowApp extends StatelessWidget {
  final Map<String, dynamic> args;

  const MultiWindowApp({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final type = args['page'] ?? 'settings';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey.shade200,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey.shade100,
          elevation: 0,
          foregroundColor: Colors.black87,
        ),
      ),
      home: type == 'settings'
          ? const SettingsHomePage()
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
  const SettingsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = false; // TODO: Firebase Auth 연동 예정

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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage:
                        isLoggedIn ? NetworkImage("https://picsum.photos/200") : null,
                    child: !isLoggedIn
                        ? const Icon(Icons.person, size: 32, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 14),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn ? "김진형" : "로그인하세요",
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isLoggedIn ? "jinhyeong@example.com" : "계정 설정을 위해 로그인",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
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
            subtitle: "라이트 / 다크",
            icon: Icons.dark_mode,
            onTap: () {},
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
          const SectionTitle("투두 게이미피케이션"),
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
            title: "단축키 설정",
            subtitle: "키보드 단축키 커스터마이즈",
            icon: Icons.keyboard,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShortcutSettingPage()),
              );
            },
          ),
          _SettingsTile(
            title: "앱 정보",
            subtitle: "버전 / 라이선스",
            icon: Icons.info_outline,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppInfoPage()),
              );
            },
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade700,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        leading: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.black87),
        ),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
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

class ShortcutSettingPage extends StatelessWidget {
  const ShortcutSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("단축키 설정")),
      body: const Center(
        child: Text("단축키 설정 기능 준비 중입니다!"),
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
        child: Text("DayScript v1.0.0\nStudio ReadMe 제작"),
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

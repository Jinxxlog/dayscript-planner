import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("설정"),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ─────────────────────────────────────────────
          // 🔹 프로필 / 계정
          // ─────────────────────────────────────────────
          Card(
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: const Text(
                "로그인되지 않음",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text("구글 / 애플 / 네이버 / 카카오로 로그인"),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () {
                // TODO: 계정 관리 페이지 (추가 예정)
              },
            ),
          ),

          const SizedBox(height: 20),

          // ─────────────────────────────────────────────
          // 🔹 일반 설정
          // ─────────────────────────────────────────────
          const Text(
            "일반",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.color_lens),
                  title: const Text("테마"),
                  subtitle: const Text("라이트 / 다크 / 시스템"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    // TODO: 테마 선택 화면
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.font_download),
                  title: const Text("글씨체"),
                  subtitle: const Text("기본 · 나눔 · 기타 추가 예정"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    // TODO: 글씨체 변경
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─────────────────────────────────────────────
          // 🔹 데이터 / 동기화
          // ─────────────────────────────────────────────
          const Text(
            "데이터 & 동기화",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_sync),
                  title: const Text("데이터 동기화"),
                  subtitle: const Text("Google Cloud 연결 준비됨"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    // TODO: 동기화 화면
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup),
                  title: const Text("백업 / 복원"),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // ─────────────────────────────────────────────
          // 🔹 앱 정보
          // ─────────────────────────────────────────────
          Center(
            child: Text(
              "DayScript v1.0.0",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),

          const SizedBox(height: 10),
          Center(
            child: Text(
              "© 2025 Studio ReadMe",
              style: TextStyle(color: Colors.grey.shade500),
            ),
          )
        ],
      ),
    );
  }
}

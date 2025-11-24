import 'package:flutter/material.dart';

class ProfileDrawer extends StatelessWidget {
  final Function(String) onThemeChange;

  const ProfileDrawer({
    super.key,
    required this.onThemeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ▣ 프로필 영역
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "로그인 필요",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Google / Apple / Naver / Kakao",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(),

            // ▣ 로그인 버튼
            ListTile(
              leading: Icon(Icons.login),
              title: Text("Google 로그인"),
              onTap: () {
                Navigator.pop(context);
                // TODO: Google 로그인 기능 연결
              },
            ),

            ListTile(
              leading: Icon(Icons.logout),
              title: Text("로그아웃"),
              onTap: () {
                Navigator.pop(context);
                // TODO: 로그아웃 기능
              },
            ),

            Divider(),

            // ▣ 테마 변경
            ListTile(
              leading: Icon(Icons.brightness_6),
              title: Text("테마 변경"),
              onTap: () async {
                final mode = await showDialog<String>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    title: Text("테마 설정"),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, "light"),
                        child: Text("라이트"),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, "dark"),
                        child: Text("다크"),
                      ),
                    ],
                  ),
                );

                if (mode != null) onThemeChange(mode);
              },
            ),

            // ▣ 폰트 설정
            ListTile(
              leading: Icon(Icons.font_download),
              title: Text("폰트 설정 (추가 예정)"),
              onTap: () {},
            ),

            Spacer(),

            // ▣ 계정 삭제 / 앱 정보
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text("앱 정보"),
              onTap: () {},
            ),
            ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text("계정 삭제"),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  // ⭐ 데스크탑 GoogleSignIn 설정
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        "226614486302-7av3i5qg8km1p0hjgph6hh8q9df6sl2o.apps.googleusercontent.com", // 데스크탑 OAuth ID
    scopes: [
      "email",
      "profile",
    ],
  );

  Future<void> _signInWithGoogle() async {
    try {
      setState(() => _loading = true);

      // Google 로그인 UI 띄우기
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return; // 로그인 취소
      }

      final googleAuth = await googleUser.authentication;

      // Firebase Auth로 연결
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) Navigator.pop(context); // 로그인 성공 → 창 닫기
    } catch (e) {
      debugPrint("로그인 실패: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("로그인 실패: $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("로그인")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "DayScript 계정 로그인",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _signInWithGoogle,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _loading
                    ? const CircularProgressIndicator()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset("assets/google.png",
                              width: 24, height: 24),
                          const SizedBox(width: 10),
                          const Text("Google로 로그인"),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 40),
            const Text(
              "로그인하면 동기화, 백업, 공명 퀘스트 등을 사용할 수 있어요!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            )
          ],
        ),
      ),
    );
  }
}

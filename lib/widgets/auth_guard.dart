import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_provider.dart';

/// 보호된 화면을 감싸는 가드: 로딩/에러/미로그인 상태 표시.
class AuthGuard extends StatelessWidget {
  final Widget child;
  final Widget? loading;
  final Widget? unauthorized;

  const AuthGuard({
    super.key,
    required this.child,
    this.loading,
    this.unauthorized,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return loading ??
          const Center(child: CircularProgressIndicator.adaptive());
    }

    if (!auth.isAuthenticated) {
      return unauthorized ??
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("로그인이 필요합니다."),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/login'),
                  child: const Text("로그인 하러 가기"),
                ),
              ],
            ),
          );
    }

    return child;
  }
}

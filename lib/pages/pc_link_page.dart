import 'dart:io' if (dart.library.html) 'platform_stub.dart' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../pages/planner_home.dart';
import '../services/credit_provider.dart';
import '../services/device_identity_service.dart';
import '../services/device_link_service.dart';
import '../services/entitlement_provider.dart';
import '../services/guest_data_manager.dart';
import '../services/sync_coordinator.dart';
import '../services/ui_prefs_provider.dart';
import '../widgets/app_logo.dart';

class PcLinkPage extends StatefulWidget {
  final ThemeMode currentMode;
  final Future<void> Function(String mode) onThemeChange;
  const PcLinkPage({
    super.key,
    required this.currentMode,
    required this.onThemeChange,
  });

  @override
  State<PcLinkPage> createState() => _PcLinkPageState();
}

class _PcLinkPageState extends State<PcLinkPage> {
  final _secretController = TextEditingController();
  final _deviceLinkService = DeviceLinkService();
  bool _linking = false;

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _handleGuest() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게스트로 사용'),
        content: const Text('게스트 데이터는 연동 시 삭제될 수 있습니다. 계속 진행할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('계속하기'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    try {
      await FirebaseAuth.instance.signInAnonymously();
      _goMain();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게스트 로그인 실패: $e')),
      );
    }
  }

  Future<void> _handleLink() async {
    final secret = _secretController.text.trim();
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('연동 키를 입력해주세요.')));
      return;
    }

    final hasGuest = await GuestDataManager.hasGuestData();
    if (hasGuest) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('게스트 데이터 초기화'),
          content: const Text(
              '게스트로 사용한 데이터가 있습니다.\n연동하면 게스트 데이터가 삭제됩니다. 진행할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제하고 연동'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await GuestDataManager.clearGuestData();
    }

    setState(() => _linking = true);
    try {
      final deviceId = await DeviceIdentityService.getDeviceId();
      final platform = Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
              ? 'macos'
              : Platform.isLinux
                  ? 'linux'
                  : 'desktop';

      final customToken = await _deviceLinkService.linkWithSecret(
        secret: secret,
        deviceId: deviceId,
        platform: platform,
        appVersion: 'desktop',
      );
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      if (!mounted) return;
      final signedIn = FirebaseAuth.instance.currentUser;
      // ignore: discarded_futures
      context.read<CreditProvider>().setUser(signedIn);
      // ignore: discarded_futures
      context.read<EntitlementProvider>().setUser(signedIn);
      // ignore: discarded_futures
      context.read<UiPrefsProvider>().setUser(signedIn);

      // 최초 동기화는 서버 -> 로컬 우선 적용
      await SyncCoordinator().syncAll();
      if (!mounted) return;
      _goMain();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('연동에 실패했습니다: $e')));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  void _goMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlannerHomePage(
          onThemeChange: widget.onThemeChange,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(maxSize: 200),
                const SizedBox(height: 16),
                const Text(
                  'PC 연동',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '모바일에서 발급한 연동 키를 입력하면 PC를 연동할 수 있습니다. '
                  '게스트 데이터가 있다면 연동 시 삭제될 수 있어요.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _secretController,
                  decoration: const InputDecoration(
                    labelText: '연동 키',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleLink(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _linking ? null : _handleLink,
                        child: _linking
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('연동하기'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _linking ? null : _handleGuest,
                      child: const Text('게스트로 사용'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.shrink(),
                    const Flexible(
                      child: Text('게스트 데이터는 연동 시 삭제될 수 있습니다.'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

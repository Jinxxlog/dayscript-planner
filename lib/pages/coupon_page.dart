import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) '../desktop_multi_window_stub.dart';
import 'package:provider/provider.dart';

import '../services/billing_service.dart';
import '../services/credit_provider.dart';
import '../services/entitlement_provider.dart';

class CouponPage extends StatefulWidget {
  const CouponPage({super.key});

  @override
  State<CouponPage> createState() => _CouponPageState();
}

class _CouponPageState extends State<CouponPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _resetBusy = false;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> resp;
      if (_isDesktop) {
        final raw = await DesktopMultiWindow.invokeMethod(
          0,
          'billingRedeemCoupon',
          {'code': code},
        );
        resp = (raw as Map?)?.cast<String, dynamic>() ?? const {};
        if (resp['ok'] != true) {
          throw Exception(resp['message']?.toString() ?? 'Unknown error');
        }
      } else {
        resp = await BillingService().redeemCoupon(code: code);
      }
      if (!mounted) return;

      final alreadyRedeemed = resp['alreadyRedeemed'] == true;
      if (alreadyRedeemed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 사용한 쿠폰입니다.')),
        );
        return;
      }

      if (!_isDesktop) {
        // ignore: discarded_futures
        context.read<CreditProvider>().refresh();
        // ignore: discarded_futures
        context.read<EntitlementProvider>().refresh();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('쿠폰이 적용되었습니다.')),
      );
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('쿠폰 적용 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _debugReset() async {
    if (!kDebugMode) return;
    if (_resetBusy) return;
    setState(() => _resetBusy = true);
    try {
      final Map<String, dynamic> resp;
      if (_isDesktop) {
        final raw = await DesktopMultiWindow.invokeMethod(
          0,
          'billingDebugResetCouponRedemptionNonce',
          {},
        );
        resp = (raw as Map?)?.cast<String, dynamic>() ?? const {};
        if (resp['ok'] != true) {
          throw Exception(resp['message']?.toString() ?? 'Unknown error');
        }
      } else {
        resp = await BillingService().debugResetCouponRedemptionNonce();
      }
      if (!mounted) return;
      final nonce = resp['debugCouponResetNonce'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('쿠폰 사용량 초기화 완료 (nonce: $nonce)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초기화 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool guestBlocked;
    if (_isDesktop) {
      guestBlocked = false;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      guestBlocked = user == null || user.isAnonymous;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('쿠폰')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (guestBlocked) ...[
              const SizedBox(height: 12),
              const Text('게스트 사용자는 쿠폰을 사용할 수 없습니다.\n로그인 후 이용해 주세요.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  try {
                    await Navigator.pushNamed(context, '/login');
                  } catch (_) {}
                },
                child: const Text('로그인'),
              ),
              const Spacer(),
            ] else ...[
              TextField(
                controller: _controller,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '쿠폰 코드',
                  hintText: '예: thanks_testers',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _apply(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _apply,
                  child: Text(_busy ? '적용 중...' : '적용'),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '테스트용 쿠폰 예시 (쿠폰 문서가 있어야 적용됨)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text('credit1000 = 크레딧 1000 추가'),
              const Text('proplanplus = Pro 7일 추가'),
              const Text('proplanminus = Pro 7일 감소'),
              const Text('premiunplanplus = Premium 7일 추가'),
              const Text('premiunplanminus = Premium 7일 감소'),
              if (kDebugMode) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _resetBusy ? null : _debugReset,
                    child: Text(_resetBusy ? '초기화 중...' : '사용량 초기화 (디버그)'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '테스트 중 같은 쿠폰을 다시 쓰고 싶을 때 사용합니다.\n'
                  '서버에서 허용된 이메일(DEBUG_COUPON_ALLOW_EMAILS)만 초기화가 가능합니다.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

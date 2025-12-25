import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/billing_service.dart';
import '../services/credit_provider.dart';
import '../services/entitlement_provider.dart';
import 'billing_catalog.dart';
import '../widgets/subscription_badges.dart';

class SubscriptionShopPage extends StatefulWidget {
  const SubscriptionShopPage({super.key});

  @override
  State<SubscriptionShopPage> createState() => _SubscriptionShopPageState();
}

class _SubscriptionShopPageState extends State<SubscriptionShopPage> {
  bool _busy = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static const String _proFeatures =
      '\uAD11\uACE0 \uC81C\uAC70 + \uAE00\uC528\uCCB4 \uBCC0\uACBD + \uD22C\uB450 \uC0C9\uC0C1 \uCEE4\uC2A4\uD140 + \uD14C\uB9C8 \uC120\uD0DD';
  static const String _premiumFeatures =
      'Pro\uC758 \uBAA8\uB4E0 \uAE30\uB2A5 + \uC54C\uB9BC \uAE30\uB2A5 + \uD1B5\uACC4 \uAE30\uB2A5 + \uC77C\uC815 \uACF5\uC720 \uAE30\uB2A5';

  Future<bool> _confirmPurchase({
    required String title,
    required String message,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('구매'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _buyPack(SubscriptionPack pack, int currentCredits) async {
    if (!_isMobile) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('모바일에서만 구독 구매가 가능합니다.')));
      return;
    }
    if (_busy) return;
    if (currentCredits < pack.costCredits) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('크레딧이 부족해요.')));
      return;
    }

    final tierLabel = pack.tier == 'premium' ? 'Premium' : 'Pro';
    final ok = await _confirmPurchase(
      title: '$tierLabel ${pack.days}일 구매',
      message:
          '${pack.costCredits} 크레딧을 사용해서 $tierLabel ${pack.days}일을 구매할까요?\n'
          '남은 기간은 누적되고 Premium이 먼저 차감됩니다.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await BillingService().buySubscriptionWithCredits(
        tier: pack.tier,
        days: pack.days,
      );
      if (!mounted) return;
      // ignore: discarded_futures
      context.read<CreditProvider>().refresh();
      // ignore: discarded_futures
      context.read<EntitlementProvider>().refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('구독이 반영되었어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('구독 구매 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(
    BuildContext context,
    String title,
    List<SubscriptionPack> packs,
  ) {
    final credits = context.watch<CreditProvider>().balance;
    final isPremium = title.toLowerCase() == 'premium';
    final badgeBg = isPremium
        ? const Color(0xFF9575CD)
        : const Color(0xFF1E88E5);
    final features = isPremium ? _premiumFeatures : _proFeatures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          features,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        for (final p in packs)
          Card(
            elevation: 0,
            child: ListTile(
              title: Text('${p.days}일'),
              subtitle: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.toll_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text('${p.costCredits}'),
                ],
              ),
              trailing: FilledButton(
                onPressed: (isPremium || _busy) ? null : () => _buyPack(p, credits),
                child: const Text('구매'),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final guestBlocked = user == null || user.isAnonymous;
    final credits = context.watch<CreditProvider>().balance;

    return Scaffold(
      appBar: AppBar(title: const Text('구독 구매')),
      body: !_isMobile
          ? const Center(child: Text('모바일에서만 구독 구매가 가능합니다.'))
          : guestBlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '게스트 사용자는 결제 기능을 사용할 수 없습니다.\n로그인 후 이용해주세요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: const Text('로그인'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.toll_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$credits',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const SubscriptionBadges(compact: false),
                const SizedBox(height: 18),
                _section(context, 'Pro', BillingCatalog.proPacks),
                const SizedBox(height: 18),
                _section(context, 'Premium', BillingCatalog.premiumPacks),
                const SizedBox(height: 14),
                Text(
                  '구독은 자동결제가 아닌 기간제입니다. 남은 기간은 누적되고 Premium이 먼저 차감됩니다.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

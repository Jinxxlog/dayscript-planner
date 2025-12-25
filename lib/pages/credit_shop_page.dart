import 'dart:async';
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../services/billing_service.dart';
import 'billing_catalog.dart';

class CreditShopPage extends StatefulWidget {
  const CreditShopPage({super.key});

  @override
  State<CreditShopPage> createState() => _CreditShopPageState();
}

class _CreditShopPageState extends State<CreditShopPage> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool _loading = true;
  String? _error;
  List<ProductDetails> _products = const [];

  final Set<String> _verifyingPurchaseKeys = <String>{};
  final Set<String> _verifyingProductIds = <String>{};

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      },
    );
    // ignore: discarded_futures
    _init();
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    if (!_isMobile) {
      setState(() {
        _available = false;
        _loading = false;
        _error = '모바일에서만 결제가 가능합니다.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() {
        _available = false;
        _loading = false;
        _error = '게스트 사용자는 결제 기능을 사용할 수 없습니다.\n로그인 후 이용해주세요.';
      });
      return;
    }

    try {
      final available = await _iap.isAvailable();
      if (!mounted) return;
      if (!available) {
        setState(() {
          _available = false;
          _loading = false;
          _error = '결제 서비스를 사용할 수 없어요.';
        });
        return;
      }

      final response = await _iap.queryProductDetails(
        BillingCatalog.creditProductIds,
      );
      if (!mounted) return;
      if (response.error != null) {
        setState(() {
          _available = true;
          _loading = false;
          _error = response.error!.message;
        });
        return;
      }

      final products = response.productDetails.toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      setState(() {
        _available = true;
        _loading = false;
        _error = null;
        _products = products;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        if (!mounted) continue;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('결제 처리 중입니다. 잠시만 기다려주세요.')),
        );
        continue;
      }

      if (p.status == PurchaseStatus.error) {
        if (!mounted) continue;
        final msg = p.error?.message ?? '결제에 실패했어요.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        continue;
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _verifyAndGrantCredits(p);
      }
    }
  }

  Future<void> _verifyAndGrantCredits(PurchaseDetails purchase) async {
    final key = '${purchase.productID}__${purchase.purchaseID ?? ''}';
    if (_verifyingPurchaseKeys.contains(key)) return;
    _verifyingPurchaseKeys.add(key);
    _verifyingProductIds.add(purchase.productID);

    try {
      var verificationData = purchase.verificationData.serverVerificationData;

      if (Platform.isIOS) {
        final addition = _iap
            .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        final refreshed = await addition.refreshPurchaseVerificationData();
        if (refreshed != null && refreshed.serverVerificationData.isNotEmpty) {
          verificationData = refreshed.serverVerificationData;
        }
      }

      final resp = await BillingService().verifyIapCreditPurchase(
        productId: purchase.productID,
        serverVerificationData: verificationData,
        purchaseId: purchase.purchaseID,
      );

      if (!mounted) return;
      final granted = (resp['grantedCredits'] as num?)?.toInt();
      final balance = (resp['creditBalance'] as num?)?.toInt();
      final msg = granted == null
          ? '크레딧이 반영되었어요.'
          : balance == null
          ? '+$granted 크레딧이 반영되었어요.'
          : '+$granted 크레딧이 반영되었어요. (잔액: $balance)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('결제 검증/반영 실패: $e')));
      return;
    } finally {
      _verifyingPurchaseKeys.remove(key);
      _verifyingProductIds.remove(purchase.productID);
    }

    if (Platform.isAndroid) {
      try {
        final androidAddition = _iap
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        await androidAddition.consumePurchase(purchase);
      } catch (_) {}
    }

    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (_) {}
    }
  }

  Future<void> _buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
  }

  Future<void> _restore() async {
    if (!_isMobile) return;
    try {
      if (Platform.isIOS) {
        final addition = _iap
            .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        await addition.sync();
      }
    } catch (_) {}

    try {
      await _iap.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('복원/미처리 결제 처리를 요청했어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('복원 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final guestBlocked = user == null || user.isAnonymous;

    return Scaffold(
      appBar: AppBar(
        title: const Text('크레딧 충전'),
        actions: [
          IconButton(
            tooltip: '복원',
            onPressed: guestBlocked ? null : _restore,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!_available || _error != null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? '결제 서비스를 사용할 수 없어요.',
                      textAlign: TextAlign.center,
                    ),
                    if (guestBlocked) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        child: const Text('로그인'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '크레딧 충전',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final p in _products)
                  Card(
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(
                        Icons.credit_score_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Builder(
                        builder: (context) {
                          final credits = BillingCatalog.creditsForProductId(
                            p.id,
                          );
                          if (credits == null) return Text(p.title);
                          return Row(
                            children: [
                              Text(
                                '$credits',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.toll_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          );
                        },
                      ),
                      subtitle: Text(
                        p.description.isEmpty ? p.id : p.description,
                      ),
                      trailing: FilledButton(
                        onPressed: _verifyingProductIds.contains(p.id)
                            ? null
                            : () => _buy(p),
                        child: Text(p.price),
                      ),
                    ),
                  ),
                if (_products.isEmpty) const Text('스토어에 등록된 크레딧 상품을 찾지 못했어요.'),
                const SizedBox(height: 8),
                Text(
                  '결제는 모바일(Android/iOS)에서만 가능합니다.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

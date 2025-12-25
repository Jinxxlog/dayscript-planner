import 'dart:async';
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'billing_service.dart';

/// Ensures pending purchases get processed even if the user leaves the shop UI.
class IapPurchaseCoordinator {
  IapPurchaseCoordinator._internal();
  static final IapPurchaseCoordinator _instance =
      IapPurchaseCoordinator._internal();
  factory IapPurchaseCoordinator() => _instance;

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Set<String> _processingKeys = <String>{};
  bool _started = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  void start() {
    if (_started) return;
    if (!_isMobile) return;
    _started = true;
    _sub = _iap.purchaseStream.listen((purchases) {
      // ignore: discarded_futures
      _onPurchaseUpdates(purchases);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  bool _isCreditProduct(String productId) => productId.startsWith('credit_');

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!_isCreditProduct(p.productID)) continue;
      if (p.status != PurchaseStatus.purchased &&
          p.status != PurchaseStatus.restored) {
        continue;
      }
      await _handleCreditPurchase(p);
    }
  }

  Future<void> _handleCreditPurchase(PurchaseDetails purchase) async {
    final key = '${purchase.productID}__${purchase.purchaseID ?? ''}';
    if (_processingKeys.contains(key)) return;
    _processingKeys.add(key);

    try {
      var verificationData = purchase.verificationData.serverVerificationData;
      if (Platform.isIOS) {
        try {
          final addition = _iap
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
          final refreshed = await addition.refreshPurchaseVerificationData();
          if (refreshed != null &&
              refreshed.serverVerificationData.isNotEmpty) {
            verificationData = refreshed.serverVerificationData;
          }
        } catch (_) {}
      }

      await BillingService().verifyIapCreditPurchase(
        productId: purchase.productID,
        serverVerificationData: verificationData,
        purchaseId: purchase.purchaseID,
      );

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
    } catch (_) {
      // Keep the purchase uncompleted so it can be retried on next app session.
    } finally {
      _processingKeys.remove(key);
    }
  }
}

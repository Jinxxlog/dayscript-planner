import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

class BillingService {
  BillingService._internal();
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const String _defaultFunctionsRegion = 'us-central1';

  User _requireNonGuestUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Login required.',
      );
    }
    if (user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'guest-not-allowed',
        message: 'Guest users cannot purchase.',
      );
    }
    return user;
  }

  static String get platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<Map<String, dynamic>> verifyIapCreditPurchase({
    required String productId,
    required String serverVerificationData,
    String? purchaseId,
  }) async {
    _requireNonGuestUser();
    final payload = <String, dynamic>{
      'platform': platformKey,
      'productId': productId,
      'serverVerificationData': serverVerificationData,
      if (purchaseId != null) 'purchaseId': purchaseId,
    };
    if (_isDesktop) {
      return _callCallableHttp('verifyIapCreditPurchase', payload);
    }
    final callable = _functions.httpsCallable('verifyIapCreditPurchase');
    final resp = await callable<Map<String, dynamic>>(payload);
    return resp.data;
  }

  Future<Map<String, dynamic>> buySubscriptionWithCredits({
    required String tier, // "pro" | "premium"
    required int days,
  }) async {
    _requireNonGuestUser();
    final payload = <String, dynamic>{'tier': tier, 'days': days};
    if (_isDesktop) {
      return _callCallableHttp('buySubscriptionWithCredits', payload);
    }
    final callable = _functions.httpsCallable('buySubscriptionWithCredits');
    final resp = await callable<Map<String, dynamic>>(payload);
    return resp.data;
  }

  Future<Map<String, dynamic>> applyCoupon({required String code}) async {
    _requireNonGuestUser();
    final payload = <String, dynamic>{'code': code.trim()};
    if (_isDesktop) {
      return _callCallableHttp('applyCoupon', payload);
    }
    final callable = _functions.httpsCallable('applyCoupon');
    final resp = await callable<Map<String, dynamic>>(payload);
    return resp.data;
  }

  Future<Map<String, dynamic>> redeemCoupon({required String code}) async {
    _requireNonGuestUser();
    final payload = <String, dynamic>{'code': code.trim()};
    if (_isDesktop) {
      return _callCallableHttp('redeemCoupon', payload);
    }
    final callable = _functions.httpsCallable('redeemCoupon');
    final resp = await callable<Map<String, dynamic>>(payload);
    return resp.data;
  }

  Future<Map<String, dynamic>> debugResetCouponRedemptionNonce() async {
    _requireNonGuestUser();
    const payload = <String, dynamic>{};
    if (_isDesktop) {
      return _callCallableHttp('debugResetCouponRedemptionNonce', payload);
    }
    final callable = _functions.httpsCallable('debugResetCouponRedemptionNonce');
    final resp = await callable<Map<String, dynamic>>(payload);
    return resp.data;
  }

  Uri _callableUrl(String functionName) {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return Uri.parse(
      'https://${_defaultFunctionsRegion}-$projectId.cloudfunctions.net/$functionName',
    );
  }

  Future<Map<String, dynamic>> _callCallableHttp(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final user = _requireNonGuestUser();
    final url = _callableUrl(functionName);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = await user.getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final resp = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'data': data}),
    );

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Invalid response (${resp.statusCode}): ${resp.body}');
    }

    if (resp.statusCode != 200 || decoded.containsKey('error')) {
      final err = (decoded['error'] as Map?)?.cast<String, dynamic>();
      final status = err?['status']?.toString() ?? 'INTERNAL';
      final message = err?['message']?.toString() ?? 'Unknown error';
      throw Exception('$status: $message (HTTP ${resp.statusCode})');
    }

    final resultRaw = decoded['result'];
    final result = (resultRaw as Map?)?.cast<String, dynamic>();
    if (result == null) {
      throw Exception('invalid-response: missing result');
    }
    return result;
  }
}

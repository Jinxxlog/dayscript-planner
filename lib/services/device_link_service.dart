import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

class DeviceInfo {
  final String deviceId;
  final String nickname;
  final String platform;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  DeviceInfo({
    required this.deviceId,
    required this.nickname,
    required this.platform,
    required this.status,
    this.createdAt,
    this.lastSeenAt,
    this.revokedAt,
  });

  factory DeviceInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DeviceInfo(
      deviceId: data['deviceId'] as String? ?? doc.id,
      nickname: data['nickname'] as String? ?? 'Unnamed PC',
      platform: data['platform'] as String? ?? 'unknown',
      status: data['status'] as String? ?? 'unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastSeenAt: (data['lastSeenAt'] as Timestamp?)?.toDate(),
      revokedAt: (data['revokedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class IssueKeyResult {
  final String secret;
  final DateTime? expiresAt;
  IssueKeyResult({required this.secret, this.expiresAt});
}

class DeviceLinkService {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  static const String _defaultFunctionsRegion = 'us-central1';

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'not-logged-in', message: 'Login required.');
    }
    return user;
  }

  Future<IssueKeyResult> issueLinkKey({int ttlMinutes = 20}) async {
    _requireUser();
    final data = (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? await _callCallableHttp('issuePcLinkKey', {'ttlMinutes': ttlMinutes})
        : (await _functions.httpsCallable('issuePcLinkKey')<Map<String, dynamic>>({
            'ttlMinutes': ttlMinutes,
          }))
            .data;
    final secret = data['secret'] as String? ?? '';
    final expiresRaw = data['expiresAt'];
    DateTime? expiresAt;
    if (expiresRaw is Timestamp) {
      expiresAt = expiresRaw.toDate();
    } else if (expiresRaw is Map) {
      final seconds = (expiresRaw['seconds'] as num?)?.toInt();
      final nanos = (expiresRaw['nanoseconds'] as num?)?.toInt() ?? 0;
      if (seconds != null) {
        expiresAt =
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + nanos ~/ 1000000);
      }
    }
    return IssueKeyResult(secret: secret, expiresAt: expiresAt);
  }

  Stream<List<DeviceInfo>> watchDevices() {
    final user = _requireUser();
    return _fs
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(DeviceInfo.fromDoc).toList());
  }

  Future<void> updateNickname(String deviceId, String nickname) async {
    final user = _requireUser();
    await _fs
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(deviceId)
        .update({'nickname': nickname.trim()});
  }

  Future<void> revokeDevice(String deviceId) async {
    _requireUser();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await _callCallableHttp('revokeDevice', {'deviceId': deviceId});
      return;
    }
    final callable = _functions.httpsCallable('revokeDevice');
    await callable({'deviceId': deviceId});
  }

  /// Links PC with secret and returns custom token.
  Future<String> linkWithSecret({
    required String secret,
    required String deviceId,
    required String platform,
    String? appVersion,
    String? nickname,
  }) async {
    final payload = <String, dynamic>{
      'secret': secret,
      'deviceId': deviceId,
      'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      if (nickname != null && nickname.trim().isNotEmpty) 'nickname': nickname,
    };

    // `cloud_functions` has no Windows/Linux implementation in many setups.
    // On desktop, call the callable endpoint over HTTP.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final result = await _callCallableHttp('linkPcWithKey', payload);
      final token = result['customToken'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Missing customToken in response');
      }
      return token;
    }

    final callable = _functions.httpsCallable('linkPcWithKey');
    final resp = await callable<Map<String, dynamic>>(payload);
    final token = resp.data['customToken'] as String?;
    if (token == null || token.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'invalid-response',
        message: 'Missing customToken in response',
      );
    }
    return token;
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
    final url = _callableUrl(functionName);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // For callable functions that require auth, attach Firebase ID token.
    // (linkPcWithKey can work without auth, so this is best-effort.)
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token?.isNotEmpty == true) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
    }

    final resp = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'data': data}), // callable protocol: wrap in `data`
    );

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Invalid response (${resp.statusCode}): ${resp.body}');
    }

    // Callable error parsing
    if (resp.statusCode != 200 || decoded.containsKey('error')) {
      final err = (decoded['error'] as Map?)?.cast<String, dynamic>();
      final status = err?['status']?.toString() ?? 'INTERNAL';
      final message = err?['message']?.toString() ?? 'Unknown error';
      final details = err?['details'];
      final detailsStr = details == null ? '' : ' | details=${jsonEncode(details)}';
      throw Exception('$status: $message (HTTP ${resp.statusCode})$detailsStr');
    }

    // Callable response payload is usually under `result`
    final resultRaw = decoded['result'];
    final result = (resultRaw as Map?)?.cast<String, dynamic>();
    if (result == null) {
      throw Exception('invalid-response: missing result');
    }
    return result;
  }
}

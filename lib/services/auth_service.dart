import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'user_profile_service.dart';

/// 단일 Auth 진입점: currentUser 스트림, 기본 Google 로그인/로그아웃, 익명 로그인 지원.
class AuthService {
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInAnonymously() async {
    // 다른 계정으로 로그인 중이면 우선 로그아웃 후 익명 로그인
    if (_auth.currentUser != null && !_auth.currentUser!.isAnonymous) {
      await _auth.signOut();
    }
    return _auth.signInAnonymously();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;

      await _reauthenticateForSensitiveOperation(user);
      final refreshed = _auth.currentUser;
      if (refreshed == null) return;
      await refreshed.delete();
    }
  }

  Future<void> _reauthenticateForSensitiveOperation(User user) async {
    final providerIds = user.providerData.map((p) => p.providerId).toSet();
    if (providerIds.contains('google.com')) {
      await _reauthenticateWithGoogle(user);
      return;
    }
    if (providerIds.contains('apple.com')) {
      await _reauthenticateWithApple(user);
      return;
    }

    throw FirebaseAuthException(
      code: 'requires-recent-login',
      message: 'This operation requires recent authentication.',
    );
  }

  Future<void> _reauthenticateWithGoogle(User user) async {
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
    );

    var googleUser = await googleSignIn.signInSilently();
    googleUser ??= await googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'user-cancelled',
        message: 'Reauthentication was cancelled.',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> _reauthenticateWithApple(User user) async {
    final available = await SignInWithApple.isAvailable();
    if (!available) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Apple Sign In is not available.',
      );
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256OfString(rawNonce);

    final appleCred = await SignInWithApple.getAppleIDCredential(
      scopes: const [],
      nonce: nonce,
    );

    final oauthCred = OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce,
    );

    await user.reauthenticateWithCredential(oauthCred);
  }

  /// Google 로그인 → Firebase Auth 연동 (모바일/데스크톱 공용 clientId 사용)
  Future<UserCredential> signInWithGoogle({String? clientId}) async {
    final googleSignIn = GoogleSignIn(
      clientId: clientId,
      scopes: const ['email', 'profile'],
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('로그인이 취소되었습니다.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    return _signInOrLink(credential);
  }

  /// Apple 로그인 → Firebase Auth 연동 (iOS 필수)
  Future<UserCredential> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256OfString(rawNonce);

    final appleCred = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCred = OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce,
    );

    return _signInOrLink(oauthCred);
  }

  // --------------------------------------------------------------------------
  // 내부 헬퍼
  // --------------------------------------------------------------------------
  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final current = _auth.currentUser;
    UserCredential cred;
    try {
      if (current != null && current.isAnonymous) {
        cred = await current.linkWithCredential(credential);
      } else {
        cred = await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      // 이메일 중복/다른 provider로 이미 가입되어 있는 경우 → 해당 크레덴셜로 로그인 시도
      if (e.code == 'credential-already-in-use' ||
          e.code == 'account-exists-with-different-credential') {
        cred = await _auth.signInWithCredential(credential);
      } else {
        rethrow;
      }
    }

    // 프로필 upsert
    if (cred.user != null) {
      await UserProfileService().upsertUser(cred.user!);
    }

    return cred;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)])
        .join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

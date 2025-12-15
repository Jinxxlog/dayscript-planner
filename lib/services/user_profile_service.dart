import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 유저 프로필을 Firestore에 저장/업데이트.
class UserProfileService {
  UserProfileService._internal();
  static final UserProfileService _instance = UserProfileService._internal();
  factory UserProfileService() => _instance;

  final _db = FirebaseFirestore.instance;

  Future<void> upsertUser(User user) async {
    final doc = _db.collection('users').doc(user.uid);
    final providers = user.providerData.map((p) => p.providerId).toList();
    final payload = {
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'providers': providers,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await doc.set(payload, SetOptions(merge: true));
  }
}

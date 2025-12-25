import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/entitlement.dart';

class EntitlementService {
  EntitlementService._internal();
  static final EntitlementService _instance = EntitlementService._internal();
  factory EntitlementService() => _instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Future<Entitlement?> fetch(String uid) async {
    final snap = await _userDoc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final raw = data['entitlement'];
    if (raw is! Map) return null;
    return Entitlement.fromFirestoreMap(raw.cast<String, dynamic>());
  }

  Stream<Entitlement?> watch(String uid) {
    return _userDoc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      final raw = data['entitlement'];
      if (raw is! Map) return null;
      return Entitlement.fromFirestoreMap(raw.cast<String, dynamic>());
    });
  }

  Future<void> upsert(String uid, Entitlement entitlement) async {
    await _userDoc(uid).set(
      {
        'entitlement': entitlement.toFirestoreMap(),
        'entitlementUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

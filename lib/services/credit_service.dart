import 'package:cloud_firestore/cloud_firestore.dart';

class CreditService {
  CreditService._internal();
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Future<int> fetchBalance(String uid) async {
    final snap = await _userDoc(uid).get();
    final data = snap.data();
    if (data == null) return 0;
    return (data['creditBalance'] as num?)?.toInt() ?? 0;
  }

  Stream<int> watchBalance(String uid) {
    return _userDoc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return 0;
      return (data['creditBalance'] as num?)?.toInt() ?? 0;
    });
  }
}

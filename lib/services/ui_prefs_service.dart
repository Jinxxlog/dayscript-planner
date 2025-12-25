import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ui_prefs.dart';

class UiPrefsService {
  UiPrefsService._internal();
  static final UiPrefsService _instance = UiPrefsService._internal();
  factory UiPrefsService() => _instance;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection('prefs').doc('ui');

  Future<UiPrefs?> fetch(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return UiPrefs.fromJson(data);
  }

  Stream<UiPrefs?> watch(String uid) {
    return _doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return UiPrefs.fromJson(data);
    });
  }

  Future<void> upsert(String uid, UiPrefs prefs) async {
    await _doc(uid).set(
      prefs.toJson(),
      SetOptions(merge: true),
    );
  }
}


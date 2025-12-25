import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_sync_service.dart';
import 'local_data_reset_service.dart';
import 'local_scope.dart';
import 'sync_metadata_service.dart';

class AccountDataResetService {
  AccountDataResetService._();

  static const String _resetInProgressKey = 'reset_in_progress';

  static Future<void> resetAll({bool includeRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_resetInProgressKey, true);

    Object? remoteError;
    DateTime? resetAt;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (includeRemote && user != null && !user.isAnonymous) {
        try {
          final fs = FirestoreSyncService();
          await fs.init(user.uid);
          await fs.markResetNow();
          resetAt = await fs.fetchResetAt();
          await fs.deleteAllUserData();
          await SyncMetadataService.clearLastSyncAt();
        } catch (e) {
          remoteError = e;
        }
      }

      await LocalDataResetService.resetCurrentAccountData();

      // Persist a local reset marker so we don't repeatedly "apply" the same reset.
      try {
        final prefsAfter = await SharedPreferences.getInstance();
        final key = LocalScope.prefKeyWithBase('reset_at');
        await prefsAfter.setString(
          key,
          (resetAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
        );
      } catch (_) {}
    } finally {
      await prefs.setBool(_resetInProgressKey, false);
    }

    if (remoteError != null) {
      // ignore: only_throw_errors
      throw remoteError;
    }
  }
}

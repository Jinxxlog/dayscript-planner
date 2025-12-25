import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

enum SubscriptionTier { standard, pro, premium }

class Entitlement {
  final int proSeconds;
  final int premiumSeconds;
  final DateTime lastAccruedAt;

  const Entitlement({
    required this.proSeconds,
    required this.premiumSeconds,
    required this.lastAccruedAt,
  });

  factory Entitlement.standard({DateTime? lastAccruedAt}) => Entitlement(
        proSeconds: 0,
        premiumSeconds: 0,
        lastAccruedAt: (lastAccruedAt ?? DateTime.now()).toUtc(),
      );

  bool isAdFree(DateTime now) => balanceAt(now).isAdFree;

  EntitlementBalance balanceAt(DateTime now) {
    final nowUtc = now.toUtc();
    final lastUtc = lastAccruedAt.toUtc();
    final elapsed = nowUtc.difference(lastUtc).inSeconds;
    if (elapsed <= 0) {
      return EntitlementBalance(
        proSeconds: max(0, proSeconds),
        premiumSeconds: max(0, premiumSeconds),
        asOf: nowUtc,
      );
    }

    final premiumRemaining = max(0, premiumSeconds - elapsed);
    final leftover = max(0, elapsed - premiumSeconds);
    final proRemaining = max(0, proSeconds - leftover);

    return EntitlementBalance(
      proSeconds: proRemaining,
      premiumSeconds: premiumRemaining,
      asOf: nowUtc,
    );
  }

  Entitlement applyDelta({
    required DateTime now,
    int addProSeconds = 0,
    int addPremiumSeconds = 0,
  }) {
    final b = balanceAt(now);
    return Entitlement(
      proSeconds: max(0, b.proSeconds + addProSeconds),
      premiumSeconds: max(0, b.premiumSeconds + addPremiumSeconds),
      lastAccruedAt: now.toUtc(),
    );
  }

  SubscriptionTier primaryTier(DateTime now) {
    final b = balanceAt(now);
    if (b.premiumSeconds > 0) return SubscriptionTier.premium;
    if (b.proSeconds > 0) return SubscriptionTier.pro;
    return SubscriptionTier.standard;
  }

  static int secondsToDisplayDays(int seconds) {
    if (seconds <= 0) return 0;
    const day = 86400;
    return ((seconds + day - 1) / day).floor();
  }

  Map<String, dynamic> toJson() => {
        'proSeconds': proSeconds,
        'premiumSeconds': premiumSeconds,
        'lastAccruedAt': lastAccruedAt.toUtc().toIso8601String(),
      };

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    DateTime parseDT(dynamic v) {
      if (v is DateTime) return v.toUtc();
      if (v is String) return DateTime.tryParse(v)?.toUtc() ?? DateTime.now().toUtc();
      return DateTime.now().toUtc();
    }

    return Entitlement(
      proSeconds: (json['proSeconds'] as num?)?.toInt() ?? 0,
      premiumSeconds: (json['premiumSeconds'] as num?)?.toInt() ?? 0,
      lastAccruedAt: parseDT(json['lastAccruedAt']),
    );
  }

  factory Entitlement.fromFirestoreMap(Map<String, dynamic> data) {
    DateTime parseDT(dynamic v) {
      if (v is Timestamp) return v.toDate().toUtc();
      if (v is DateTime) return v.toUtc();
      if (v is String) return DateTime.tryParse(v)?.toUtc() ?? DateTime.now().toUtc();
      return DateTime.now().toUtc();
    }

    return Entitlement(
      proSeconds: (data['proSeconds'] as num?)?.toInt() ?? 0,
      premiumSeconds: (data['premiumSeconds'] as num?)?.toInt() ?? 0,
      lastAccruedAt: parseDT(data['lastAccruedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'proSeconds': proSeconds,
        'premiumSeconds': premiumSeconds,
        'lastAccruedAt': Timestamp.fromDate(lastAccruedAt.toUtc()),
      };
}

class EntitlementBalance {
  final int proSeconds;
  final int premiumSeconds;
  final DateTime asOf;

  const EntitlementBalance({
    required this.proSeconds,
    required this.premiumSeconds,
    required this.asOf,
  });

  bool get isAdFree => proSeconds > 0 || premiumSeconds > 0;
  int get proDays => Entitlement.secondsToDisplayDays(proSeconds);
  int get premiumDays => Entitlement.secondsToDisplayDays(premiumSeconds);
}


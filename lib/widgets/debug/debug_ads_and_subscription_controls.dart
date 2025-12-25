import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/entitlement.dart';
import '../../services/ads_debug_settings_provider.dart';
import '../../services/entitlement_provider.dart';

class DebugAdsAndSubscriptionControls extends StatelessWidget {
  const DebugAdsAndSubscriptionControls({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final ads = context.watch<AdsDebugSettingsProvider>();
    final ent = context.watch<EntitlementProvider>();
    final now = DateTime.now();
    final b = ent.balanceAt(now);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Debug',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('adsEnabled'),
              subtitle: const Text('Turn off ads rendering without subscription'),
              value: ads.adsEnabled,
              onChanged: (v) => ads.setAdsEnabled(v),
            ),
            const SizedBox(height: 6),
            Text('pro=${b.proDays}d premium=${b.premiumDays}d'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: ent.uid == null
                      ? null
                      : () => ent.grantDaysDebug(
                            tier: SubscriptionTier.pro,
                            days: 7,
                          ),
                  child: const Text('+7d Pro'),
                ),
                FilledButton.tonal(
                  onPressed: ent.uid == null
                      ? null
                      : () => ent.grantDaysDebug(
                            tier: SubscriptionTier.premium,
                            days: 7,
                          ),
                  child: const Text('+7d Premium'),
                ),
                FilledButton.tonal(
                  onPressed: ent.uid == null ? null : () => ent.clearDebug(),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


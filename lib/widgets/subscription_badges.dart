import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/entitlement_provider.dart';

class SubscriptionBadges extends StatelessWidget {
  final bool compact;
  const SubscriptionBadges({super.key, this.compact = true});

  @override
  Widget build(BuildContext context) {
    return Consumer<EntitlementProvider>(
      builder: (context, ent, _) {
        final now = DateTime.now();
        final b = ent.balanceAt(now);

        final chips = <Widget>[];
        if (b.premiumSeconds > 0) {
          chips.add(_badge(
            context,
            label: 'Premium',
            days: b.premiumDays,
            bg: const Color(0xFF9575CD),
            fg: Colors.white,
          ));
        }
        if (b.proSeconds > 0) {
          chips.add(_badge(
            context,
            label: 'Pro',
            days: b.proDays,
            bg: const Color(0xFF1E88E5),
            fg: Colors.white,
          ));
        }
        if (chips.isEmpty) {
          chips.add(_badge(
            context,
            label: 'Standard',
            days: null,
            bg: Colors.white,
            fg: Colors.black87,
            border: Colors.black12,
          ));
        }

        return Wrap(
          spacing: compact ? 6 : 8,
          runSpacing: 6,
          children: chips,
        );
      },
    );
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    required Color bg,
    required Color fg,
    int? days,
    Color? border,
  }) {
    final text = (days == null || days <= 0) ? label : '$label ${days}d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}


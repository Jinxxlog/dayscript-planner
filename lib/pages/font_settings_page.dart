import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) '../desktop_multi_window_stub.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/entitlement_provider.dart';
import '../services/ui_prefs_provider.dart';
import '../theme/font_catalog.dart';
import 'subscription_shop_page.dart';

class FontSettingsPage extends StatelessWidget {
  final bool persistViaMainWindow;
  final bool? canUseProOverride;
  final bool? signedInOverride;

  const FontSettingsPage({
    super.key,
    this.persistViaMainWindow = false,
    this.canUseProOverride,
    this.signedInOverride,
  });

  bool _canUsePro(BuildContext context) {
    final ent = context.watch<EntitlementProvider>();
    if (!ent.hydrated) return false;
    return ent.balanceAt(DateTime.now()).isAdFree;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPrefsProvider>();
    final selected = FontCatalog.normalize(prefs.fontFamily);
    final signedIn = signedInOverride ?? (prefs.uid != null);
    final guestBlocked = !signedIn;
    final canUsePro = canUseProOverride ?? _canUsePro(context);
    final effectiveTextScale = prefs.textScale.clamp(0.85, 1.25).toDouble();
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Scaffold(
      appBar: AppBar(title: const Text('\uAE00\uC528\uCCB4')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (guestBlocked) ...[
            const Text('로그인 후 이용해 주세요.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  await Navigator.pushNamed(context, '/login');
                } catch (_) {}
              },
              child: const Text('로그인'),
            ),
            const SizedBox(height: 24),
          ] else if (!canUsePro) ...[
            const Text('Pro 구독자 전용 기능입니다.'),
            const SizedBox(height: 12),
            if (Platform.isAndroid || Platform.isIOS)
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionShopPage()),
                ),
                child: const Text('구독 구매'),
              )
            else
              const Text('구독 구매는 모바일에서만 가능합니다.'),
            const SizedBox(height: 24),
          ] else ...[
            Text(
              '글씨 크기',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 0.9, label: Text('작게')),
                    ButtonSegment(value: 1.0, label: Text('보통')),
                    ButtonSegment(value: 1.1, label: Text('크게')),
                  ],
                  selected: <double>{
                    (effectiveTextScale - 1.1).abs() < 0.01
                        ? 1.1
                        : (effectiveTextScale - 0.9).abs() < 0.01
                            ? 0.9
                            : 1.0
                  },
                  onSelectionChanged: (s) async {
                    final v = s.first;
                    if (persistViaMainWindow && isDesktop) {
                      await context.read<UiPrefsProvider>().setTextScaleLocal(v);
                      try {
                        await DesktopMultiWindow.invokeMethod(
                          0,
                          'uiPrefsChanged',
                          {'source': 'textScale', 'textScale': v},
                        );
                      } catch (_) {}
                    } else {
                      await context.read<UiPrefsProvider>().setTextScale(v);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '글씨체',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final entry in FontCatalog.options.entries)
              Card(
                elevation: 0,
                child: RadioListTile<String>(
                  value: entry.key,
                  groupValue: selected,
                  onChanged: (v) async {
                    if (v == null) return;
                    if (persistViaMainWindow && isDesktop) {
                      await context.read<UiPrefsProvider>().setFontFamilyLocal(v);
                      try {
                        await DesktopMultiWindow.invokeMethod(
                          0,
                          'uiPrefsChanged',
                          {'source': 'fontFamily', 'fontFamily': v},
                        );
                      } catch (_) {}
                    } else {
                      await context.read<UiPrefsProvider>().setFontFamily(v);
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('글씨체가 적용되었습니다.')),
                    );
                  },
                  title: Text(entry.value),
                  subtitle: Text(
                    'Dayscript 미리보기',
                    style: entry.key.isEmpty
                        ? null
                        : Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontFamily: entry.key),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

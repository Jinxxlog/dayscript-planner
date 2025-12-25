import 'dart:io' if (dart.library.html) '../platform_stub.dart' show Platform;

import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart'
    if (dart.library.html) '../desktop_multi_window_stub.dart';
import 'package:provider/provider.dart';

import '../services/entitlement_provider.dart';
import '../services/ui_prefs_provider.dart';
import '../theme/theme_presets.dart';
import 'subscription_shop_page.dart';

class ThemeSettingsPage extends StatefulWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool persistViaMainWindow;
  final bool? canUseProOverride;

  const ThemeSettingsPage({
    super.key,
    required this.currentMode,
    required this.onThemeModeChanged,
    this.persistViaMainWindow = false,
    this.canUseProOverride,
  });

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late ThemeMode _mode = widget.currentMode;

  @override
  void didUpdateWidget(covariant ThemeSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMode != widget.currentMode) {
      _mode = widget.currentMode;
    }
  }

  bool _canUsePro(BuildContext context) {
    final ent = context.watch<EntitlementProvider>();
    if (!ent.hydrated) return false;
    return ent.balanceAt(DateTime.now()).isAdFree;
  }

  void _setMode(ThemeMode mode) {
    setState(() => _mode = mode);
    widget.onThemeModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPrefsProvider>();
    final selectedPreset = ThemePresets.byId(prefs.themePresetId);
    final canUsePro = widget.canUseProOverride ?? _canUsePro(context);

    return Scaffold(
      appBar: AppBar(title: const Text('\uD14C\uB9C8')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '\uBAA8\uB4DC',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('\uC2DC\uC2A4\uD15C'),
                  value: ThemeMode.system,
                  groupValue: _mode,
                  onChanged: (v) {
                    if (v == null) return;
                    _setMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('\uB77C\uC774\uD2B8'),
                  value: ThemeMode.light,
                  groupValue: _mode,
                  onChanged: (v) {
                    if (v == null) return;
                    _setMode(v);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('\uB2E4\uD06C'),
                  value: ThemeMode.dark,
                  groupValue: _mode,
                  onChanged: (v) {
                    if (v == null) return;
                    _setMode(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '\uD14C\uB9C8 \uC2A4\uD0C0\uC77C',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!canUsePro)
                Text(
                  '\uAD6C\uB3C5 \uD14C\uB9C8\uB294 Pro\uBD80\uD130 \uAC00\uB2A5',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in ThemePresets.all)
                _ThemePresetCard(
                  preset: preset,
                  selected: preset.id == selectedPreset.id,
                  locked: preset.proOnly && !canUsePro,
                  onTap: () async {
                    if (preset.proOnly && !canUsePro) {
                      final isMobile = Platform.isAndroid || Platform.isIOS;
                      if (isMobile) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              '\uAD6C\uB3C5 \uD14C\uB9C8\uB294 Pro \uAD6C\uB3C5 \uD544\uC694',
                            ),
                            action: SnackBarAction(
                              label: '\uAD6C\uB3C5',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SubscriptionShopPage(),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '\uAD6C\uB3C5 \uD14C\uB9C8\uB294 Pro \uAD6C\uB3C5 \uD544\uC694(\uAD6C\uB3C5 \uAD6C\uB9E4\uB294 \uBAA8\uBC14\uC77C\uC5D0\uC11C\uB9CC \uAC00\uB2A5)',
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    final isDesktop =
                        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
                    if (widget.persistViaMainWindow && isDesktop) {
                      await context
                          .read<UiPrefsProvider>()
                          .setThemePresetIdLocal(preset.id);
                      try {
                        await DesktopMultiWindow.invokeMethod(
                          0,
                          'uiPrefsChanged',
                          {
                            'source': 'themePreset',
                            'themePresetId': preset.id,
                          },
                        );
                      } catch (_) {}
                    } else {
                      await context
                          .read<UiPrefsProvider>()
                          .setThemePresetId(preset.id);
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('\uD14C\uB9C8\uAC00 \uC801\uC6A9\uB418\uC5C8\uC2B5\uB2C8\uB2E4.'),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemePresetCard extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _ThemePresetCard({
    required this.preset,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - 16 * 2 - 12) / 2;
    final preview = preset.preview.isEmpty
        ? [Theme.of(context).colorScheme.primary]
        : preset.preview;

    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;

    return SizedBox(
      width: cardWidth,
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    colors: preview.length >= 2
                        ? preview.take(3).toList()
                        : [preview.first, preview.first],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    if (locked)
                      const Positioned(
                        right: 10,
                        top: 10,
                        child: Icon(Icons.lock, color: Colors.white),
                      ),
                    if (selected)
                      const Positioned(
                        right: 10,
                        bottom: 10,
                        child: Icon(Icons.check_circle, color: Colors.white),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.proOnly ? 'Pro' : '\uBB34\uB8CC',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

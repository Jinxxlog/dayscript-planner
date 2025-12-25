import 'package:flutter/material.dart';

import 'custom_colors.dart';
import 'font_catalog.dart';
import 'theme_presets.dart';

const _radius = 14.0;
const _legacyDefaultFont = 'NotoSansKR';

ThemeData _applyFont(ThemeData base, String? fontFamily) {
  final f = FontCatalog.normalize(fontFamily);
  if (f.isEmpty || f == _legacyDefaultFont) return base;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: f),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: f),
  );
}

ThemeData _buildTheme({
  required ColorScheme scheme,
  required CustomColors custom,
  required Brightness brightness,
  required ThemePreset preset,
  String? fontFamily,
}) {
  final isDefault = preset.id == ThemePresets.defaultId;
  Color mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;
  final scaffoldBg = isDefault
      ? scheme.surface
      : mix(scheme.surface, scheme.primaryContainer,
          brightness == Brightness.light ? 0.35 : 0.18);
  final cardBg = isDefault
      ? scheme.surface
      : mix(scheme.surface, scheme.primaryContainer,
          brightness == Brightness.light ? 0.18 : 0.10);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    canvasColor: scaffoldBg,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardBg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
    ),
    brightness: brightness,
    extensions: [custom],
  );
  return _applyFont(base, fontFamily);
}

ColorScheme _schemeFromPreset(ThemePreset preset, Brightness brightness) {
  final primarySeed = brightness == Brightness.light ? preset.lightSeed : preset.darkSeed;
  final secondarySeed = brightness == Brightness.light
      ? preset.lightSecondarySeed
      : preset.darkSecondarySeed;
  final tertiarySeed = brightness == Brightness.light
      ? preset.lightTertiarySeed
      : preset.darkTertiarySeed;

  final primary = ColorScheme.fromSeed(seedColor: primarySeed, brightness: brightness);
  final secondary = ColorScheme.fromSeed(seedColor: secondarySeed, brightness: brightness);
  final tertiary = ColorScheme.fromSeed(seedColor: tertiarySeed, brightness: brightness);

  return primary.copyWith(
    secondary: secondary.primary,
    onSecondary: secondary.onPrimary,
    secondaryContainer: secondary.primaryContainer,
    onSecondaryContainer: secondary.onPrimaryContainer,
    tertiary: tertiary.primary,
    onTertiary: tertiary.onPrimary,
    tertiaryContainer: tertiary.primaryContainer,
    onTertiaryContainer: tertiary.onPrimaryContainer,
  );
}

ThemeData buildLightTheme({
  String? fontFamily,
  ThemePreset preset = ThemePresets.defaultPreset,
}) {
  final scheme = _schemeFromPreset(preset, Brightness.light);
  final custom = preset.lightCustom;
  return _buildTheme(
    scheme: scheme,
    custom: custom,
    brightness: Brightness.light,
    preset: preset,
    fontFamily: fontFamily,
  );
}

ThemeData buildDarkTheme({
  String? fontFamily,
  ThemePreset preset = ThemePresets.defaultPreset,
}) {
  final scheme = _schemeFromPreset(preset, Brightness.dark);
  final custom = preset.darkCustom;
  return _buildTheme(
    scheme: scheme,
    custom: custom,
    brightness: Brightness.dark,
    preset: preset,
    fontFamily: fontFamily,
  );
}

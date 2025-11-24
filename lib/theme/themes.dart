// lib/theme/themes.dart
import 'package:flutter/material.dart';
import 'custom_colors.dart';

// 1) 브랜드 시드(살짝 톤 다운된 블루)
const _brandSeed = Color(0xFF4F7DF0);

// 2) 기본 팔레트
final ColorScheme lightScheme = ColorScheme.fromSeed(
  seedColor: _brandSeed,
  brightness: Brightness.light,
);
final ColorScheme darkScheme = ColorScheme.fromSeed(
  seedColor: _brandSeed,
  brightness: Brightness.dark,
);

// 3) 캘린더 전용 확장색
final CustomColors lightCustom = CustomColors(
  success: const Color(0xFF2E7D32),
  warning: const Color(0xFFF57C00),
  info: const Color(0xFF1565C0),
  calendarSelectedFill: const Color(0xFF6495ED).withOpacity(0.26),
  calendarTodayFill: const Color(0xFFE9EEF9),
);
final CustomColors darkCustom = CustomColors(
  success: const Color(0xFF81C784),
  warning: const Color(0xFFFFB74D),
  info: const Color(0xFF90CAF9),
  calendarSelectedFill: const Color(0xFF90CAF9).withOpacity(0.22),
  calendarTodayFill: const Color(0xFF2B2F36),
);

// 4) 공통 라운드/타이포
const _radius = 14.0;
const _font = 'NotoSansKR'; // 프로젝트에 폰트가 없으면 이 줄은 주석 처리해도 됨

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: lightScheme,
    // 글꼴을 쓸 경우에만:
    // fontFamily: _font,

    // AppBar는 둔탁하지 않게 surface 톤 + 0 elevation
    appBarTheme: AppBarTheme(
      backgroundColor: lightScheme.surface,
      foregroundColor: lightScheme.onSurface,
      elevation: 0,
      centerTitle: true,
    ),

    // 버튼 패밀리: Filled / Outlined / Text 를 M3 톤으로
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        side: BorderSide(color: lightScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: lightScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: lightScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: lightScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightScheme.primary, width: 1.4),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
    ),

    extensions: [lightCustom],
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: darkScheme,
    // fontFamily: _font,

    appBarTheme: AppBarTheme(
      backgroundColor: darkScheme.surface,
      foregroundColor: darkScheme.onSurface,
      elevation: 0,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        side: BorderSide(color: darkScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: darkScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: darkScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      margin: EdgeInsets.zero,
    ),
  dialogTheme: DialogThemeData(
    backgroundColor: darkScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkScheme.primary, width: 1.4),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
    ),

    extensions: [darkCustom],
  );
}

import 'package:flutter/material.dart';

import 'custom_colors.dart';

class ThemePreset {
  final String id;
  final String name;
  final bool proOnly;
  final Color lightSeed;
  final Color lightSecondarySeed;
  final Color lightTertiarySeed;
  final Color darkSeed;
  final Color darkSecondarySeed;
  final Color darkTertiarySeed;
  final List<Color> preview;
  final CustomColors lightCustom;
  final CustomColors darkCustom;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.proOnly,
    required this.lightSeed,
    required this.lightSecondarySeed,
    required this.lightTertiarySeed,
    required this.darkSeed,
    required this.darkSecondarySeed,
    required this.darkTertiarySeed,
    required this.preview,
    required this.lightCustom,
    required this.darkCustom,
  });
}

class ThemePresets {
  static const String defaultId = 'default';

  static const ThemePreset defaultPreset = ThemePreset(
    id: defaultId,
    name: '\uAE30\uBCF8',
    proOnly: false,
    lightSeed: Color(0xFF4F7DF0),
    lightSecondarySeed: Color(0xFF4F7DF0),
    lightTertiarySeed: Color(0xFF9BB5FF),
    darkSeed: Color(0xFF4F7DF0),
    darkSecondarySeed: Color(0xFF4F7DF0),
    darkTertiarySeed: Color(0xFF90CAF9),
    preview: [Color(0xFF4F7DF0), Color(0xFF9BB5FF), Color(0xFFE9EEF9)],
    lightCustom: CustomColors(
      success: Color(0xFF2E7D32),
      warning: Color(0xFFF57C00),
      info: Color(0xFF1565C0),
      calendarSelectedFill: Color(0x426495ED),
      calendarTodayFill: Color(0x33E9EEF9),
    ),
    darkCustom: CustomColors(
      success: Color(0xFF81C784),
      warning: Color(0xFFFFB74D),
      info: Color(0xFF90CAF9),
      calendarSelectedFill: Color(0x3890CAF9),
      calendarTodayFill: Color(0x332B2F36),
    ),
  );

  static const List<ThemePreset> all = <ThemePreset>[
    defaultPreset,
    ThemePreset(
      id: 'sakura',
      name: '\uBC9A\uAF43',
      proOnly: true,
      lightSeed: Color(0xFFFF6FAE),
      lightSecondarySeed: Color(0xFFFFF6EE),
      lightTertiarySeed: Color(0xFFB83B6A),
      darkSeed: Color(0xFFB83B6A),
      darkSecondarySeed: Color(0xFFFF80AB),
      darkTertiarySeed: Color(0xFFFFF6EE),
      preview: [Color(0xFFFF6FAE), Color(0xFFFFC1D9), Color(0xFFFFF6EE)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFB83B6A),
        info: Color(0xFFD81B60),
        calendarSelectedFill: Color(0x42FF6FAE),
        calendarTodayFill: Color(0x26FF6FAE),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFF80AB),
        info: Color(0xFFFF80AB),
        calendarSelectedFill: Color(0x38FF80AB),
        calendarTodayFill: Color(0x26101217),
      ),
    ),
    ThemePreset(
      id: 'sunset',
      name: '\uB178\uC744',
      proOnly: true,
      lightSeed: Color(0xFFFF7A18),
      lightSecondarySeed: Color(0xFF2B6CB0),
      lightTertiarySeed: Color(0xFFBEE3F8),
      darkSeed: Color(0xFF1E3A8A),
      darkSecondarySeed: Color(0xFFFF7A18),
      darkTertiarySeed: Color(0xFF60A5FA),
      preview: [Color(0xFFFF7A18), Color(0xFF2B6CB0), Color(0xFFBEE3F8)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFFF7A18),
        info: Color(0xFF2B6CB0),
        calendarSelectedFill: Color(0x422B6CB0),
        calendarTodayFill: Color(0x26FF7A18),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFFB74D),
        info: Color(0xFF90CAF9),
        calendarSelectedFill: Color(0x3890CAF9),
        calendarTodayFill: Color(0x261E3A8A),
      ),
    ),
    ThemePreset(
      id: 'nightSky',
      name: '\uBC24\uD558\uB298',
      proOnly: true,
      lightSeed: Color(0xFF6D28D9),
      lightSecondarySeed: Color(0xFF1E3A8A),
      lightTertiarySeed: Color(0xFF93C5FD),
      darkSeed: Color(0xFF0F172A),
      darkSecondarySeed: Color(0xFF6D28D9),
      darkTertiarySeed: Color(0xFFFBBF24),
      preview: [Color(0xFF6D28D9), Color(0xFF1E3A8A), Color(0xFF0B1020)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFF59E0B),
        info: Color(0xFF6D28D9),
        calendarSelectedFill: Color(0x421E3A8A),
        calendarTodayFill: Color(0x266D28D9),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFBBF24),
        info: Color(0xFF93C5FD),
        calendarSelectedFill: Color(0x38FBBF24),
        calendarTodayFill: Color(0x26101B3D),
      ),
    ),
    ThemePreset(
      id: 'lavender',
      name: '\uC5F0\uBCF4\uB77C',
      proOnly: true,
      lightSeed: Color(0xFF8B5CF6),
      lightSecondarySeed: Color(0xFFD8B4FE),
      lightTertiarySeed: Color(0xFFF5F3FF),
      darkSeed: Color(0xFF4C1D95),
      darkSecondarySeed: Color(0xFFC4B5FD),
      darkTertiarySeed: Color(0xFFF5F3FF),
      preview: [Color(0xFF8B5CF6), Color(0xFFD8B4FE), Color(0xFFFFFFFF)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFF59E0B),
        info: Color(0xFF8B5CF6),
        calendarSelectedFill: Color(0x42D8B4FE),
        calendarTodayFill: Color(0x268B5CF6),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFBBF24),
        info: Color(0xFFC4B5FD),
        calendarSelectedFill: Color(0x38C4B5FD),
        calendarTodayFill: Color(0x264C1D95),
      ),
    ),
    ThemePreset(
      id: 'soda',
      name: '\uC18C\uB2E4',
      proOnly: true,
      lightSeed: Color(0xFF38BDF8),
      lightSecondarySeed: Color(0xFF9CA3FF),
      lightTertiarySeed: Color(0xFFE0F7FF),
      darkSeed: Color(0xFF0B4A6F),
      darkSecondarySeed: Color(0xFF38BDF8),
      darkTertiarySeed: Color(0xFF9CA3FF),
      preview: [Color(0xFF38BDF8), Color(0xFF9CA3FF), Color(0xFFFFFFFF)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFF59E0B),
        info: Color(0xFF38BDF8),
        calendarSelectedFill: Color(0x429CA3FF),
        calendarTodayFill: Color(0x2638BDF8),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFBBF24),
        info: Color(0xFF7DD3FC),
        calendarSelectedFill: Color(0x387DD3FC),
        calendarTodayFill: Color(0x260B4A6F),
      ),
    ),
    ThemePreset(
      id: 'mintChoco',
      name: '\uBBFC\uD2B8\uCD08\uCF54',
      proOnly: true,
      lightSeed: Color(0xFF2DD4BF),
      lightSecondarySeed: Color(0xFF8B5E3C),
      lightTertiarySeed: Color(0xFFF5E6D3),
      darkSeed: Color(0xFF3B2F2A),
      darkSecondarySeed: Color(0xFF5EEAD4),
      darkTertiarySeed: Color(0xFFD6A77A),
      preview: [Color(0xFF2DD4BF), Color(0xFFB08968), Color(0xFFFFF3E6)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFF8B5E3C),
        info: Color(0xFF2DD4BF),
        calendarSelectedFill: Color(0x338B5E3C),
        calendarTodayFill: Color(0x262DD4BF),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFD6A77A),
        info: Color(0xFF5EEAD4),
        calendarSelectedFill: Color(0x33D6A77A),
        calendarTodayFill: Color(0x265EEAD4),
      ),
    ),
    ThemePreset(
      id: 'starryNight',
      name: '\uBCC4\uC774 \uBE5B\uB098\uB294 \uBC24',
      proOnly: true,
      lightSeed: Color(0xFF1D4ED8),
      lightSecondarySeed: Color(0xFF60A5FA),
      lightTertiarySeed: Color(0xFFFBBF24),
      darkSeed: Color(0xFF0B1020),
      darkSecondarySeed: Color(0xFF93C5FD),
      darkTertiarySeed: Color(0xFFFBBF24),
      preview: [Color(0xFF1D4ED8), Color(0xFF60A5FA), Color(0xFFFBBF24)],
      lightCustom: CustomColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFFBBF24),
        info: Color(0xFF1D4ED8),
        calendarSelectedFill: Color(0x33FBBF24),
        calendarTodayFill: Color(0x261D4ED8),
      ),
      darkCustom: CustomColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFBBF24),
        info: Color(0xFF93C5FD),
        calendarSelectedFill: Color(0x38FBBF24),
        calendarTodayFill: Color(0x261D4ED8),
      ),
    ),
  ];

  static ThemePreset byId(String? id) {
    final target = (id ?? '').trim();
    for (final p in all) {
      if (p.id == target) return p;
    }
    return defaultPreset;
  }
}

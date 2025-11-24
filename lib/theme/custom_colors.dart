import 'package:flutter/material.dart';

@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Color calendarSelectedFill;
  final Color calendarTodayFill;

  const CustomColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.calendarSelectedFill,
    required this.calendarTodayFill,
  });

  @override
  CustomColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? calendarSelectedFill,
    Color? calendarTodayFill,
  }) {
    return CustomColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      calendarSelectedFill: calendarSelectedFill ?? this.calendarSelectedFill,
      calendarTodayFill: calendarTodayFill ?? this.calendarTodayFill,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      calendarSelectedFill: Color.lerp(calendarSelectedFill, other.calendarSelectedFill, t)!,
      calendarTodayFill: Color.lerp(calendarTodayFill, other.calendarTodayFill, t)!,
    );
  }

  Map<String, int> toMap() => {
    'success': success.value,
    'warning': warning.value,
    'info': info.value,
    'calendarSelectedFill': calendarSelectedFill.value,
    'calendarTodayFill': calendarTodayFill.value,
  };

  static CustomColors fromMap(Map<String, dynamic> map) => CustomColors(
    success: Color(map['success'] as int),
    warning: Color(map['warning'] as int),
    info: Color(map['info'] as int),
    calendarSelectedFill: Color(map['calendarSelectedFill'] as int),
    calendarTodayFill: Color(map['calendarTodayFill'] as int),
  );
}

import 'package:flutter/material.dart';

/// 🔹 카테고리 데이터 (이름 + HEX 컬러)
class ColorCategory {
  final String name;
  final String color; // HEX 코드, 예: "#2196F3"

  const ColorCategory({required this.name, required this.color});

  Map<String, dynamic> toJson() => {'name': name, 'color': color};

  factory ColorCategory.fromJson(Map<String, dynamic> json) =>
      ColorCategory(name: json['name'], color: json['color']);

  /// ✅ HEX → Color 변환 함수
  static Color fromHex(String hex) {
    try {
      return Color(int.parse(hex.replaceAll('#', '0xff')));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  /// ✅ Color → HEX 변환 함수
  static String toHex(Color color) =>
      '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  /// ✅ 기본 색상 팔레트 (UI용)
  static const List<Color> colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.redAccent,
  ];
}

/// 🔹 기본 카테고리 목록
final List<ColorCategory> defaultCategories = [
  ColorCategory(name: '업무', color: '#2196F3'),
  ColorCategory(name: '개인', color: '#4CAF50'),
  ColorCategory(name: '운동', color: '#FF9800'),
  ColorCategory(name: '기타', color: '#9C27B0'),
];

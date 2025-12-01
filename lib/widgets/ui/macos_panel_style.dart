import 'package:flutter/material.dart';

BoxDecoration macWidgetDecoration(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  return BoxDecoration(
    color: (isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04)),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.black.withOpacity(0.06),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
        blurRadius: 12,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

Widget buildMacHeader({
  required String title,
  required bool collapsed,
  required VoidCallback onToggle,
}) {
  return GestureDetector(
    onTap: onToggle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 22,
            color: Colors.blueAccent,
          ),
        ],
      ),
    ),
  );
}

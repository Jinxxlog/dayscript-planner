import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double widthFactor;
  final double minSize;
  final double maxSize;
  final double scale;
  final bool showText;
  final String assetPath;

  const AppLogo({
    super.key,
    this.widthFactor = 0.48,
    this.minSize = 150,
    this.maxSize = 220,
    this.scale = 1.0,
    this.showText = false,
    this.assetPath = 'assets/dayscript_logo.png',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : screenWidth;

        final computed = (availableWidth * widthFactor) * scale;
        final clamped = computed.clamp(minSize, maxSize);
        final size = clamped.toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.18),
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _FallbackLogo(size: size);
                  },
                ),
              ),
            ),
            if (showText) ...[
              const SizedBox(height: 10),
              Text(
                'DayScript',
                style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ) ??
                    const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  final double size;
  const _FallbackLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.42;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          size: iconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

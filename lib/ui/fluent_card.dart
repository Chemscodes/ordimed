import 'package:flutter/material.dart';
import 'fluent_theme.dart';

class FluentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const FluentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = Theme.of(context).cardTheme.color ??
        (isDark ? const Color(0xFF141E32) : Colors.white);
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FluentTheme.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor,
            baseColor.withOpacity(isDark ? 0.92 : 0.98),
          ],
        ),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.7),
        ),
        boxShadow: [FluentTheme.softShadow(context)],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(FluentTheme.cardRadius),
      onTap: onTap,
      child: card,
    );
  }
}

import 'package:flutter/material.dart';

class FluentTheme {
  static const double cardRadius = 16;
  static const double buttonRadius = 14;
  static const double appBarRadius = 18;
  static const Duration fastAnim = Duration(milliseconds: 180);
  static const Duration midAnim = Duration(milliseconds: 240);

  static BoxShadow softShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxShadow(
      color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.12),
      blurRadius: 18,
      offset: const Offset(0, 8),
    );
  }

  static LinearGradient appBarGradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearGradient(
      colors: [scheme.primary, scheme.secondary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  static LinearGradient micaBackground(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LinearGradient(
      colors: [
        scheme.primary.withOpacity(0.05),
        scheme.secondary.withOpacity(0.05),
        scheme.background,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}

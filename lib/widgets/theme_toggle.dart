import 'package:flutter/material.dart';
import '../theme_controller.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Mode clair' : 'Mode sombre',
      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: Colors.white),
      onPressed: ThemeController.toggle,
    );
  }
}

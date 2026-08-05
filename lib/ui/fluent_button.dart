import 'package:flutter/material.dart';
import 'fluent_theme.dart';

enum FluentButtonType { primary, secondary, ghost }

class FluentButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final FluentButtonType type;
  final bool showLabel;
  final bool compact;
  final bool isLoading;

  const FluentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.type = FluentButtonType.primary,
    this.showLabel = true,
    this.compact = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    BorderSide? border;
    Gradient? gradient;

    switch (type) {
      case FluentButtonType.primary:
        bg = scheme.primary;
        fg = Colors.white;
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.secondary, 0.35) ?? scheme.primary,
          ],
        );
        break;
      case FluentButtonType.secondary:
        bg = scheme.secondary.withOpacity(0.12);
        fg = scheme.onSurface;
        border = BorderSide(color: scheme.secondary.withOpacity(0.3));
        break;
      case FluentButtonType.ghost:
        bg = Colors.transparent;
        fg = scheme.onSurface;
        border = BorderSide(color: scheme.outline.withOpacity(0.4));
        break;
    }

    final horizontalPadding = compact ? 12.0 : 16.0;
    final verticalPadding = compact ? 10.0 : 12.0;

    final isEnabled = onPressed != null && !isLoading;

    return AnimatedOpacity(
      duration: FluentTheme.fastAnim,
      opacity: isEnabled ? 1 : 0.6,
      child: AnimatedContainer(
        duration: FluentTheme.fastAnim,
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(FluentTheme.buttonRadius),
          border: border != null ? Border.all(color: border.color, width: border.width) : null,
          boxShadow: type == FluentButtonType.primary
              ? [FluentTheme.softShadow(context)]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(FluentTheme.buttonRadius),
            onTap: isEnabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading) ...[
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (icon != null) ...[
                    Icon(icon, color: fg, size: 18),
                    if (showLabel) const SizedBox(width: 8),
                  ],
                  if (showLabel)
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

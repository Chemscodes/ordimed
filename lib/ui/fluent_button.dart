import 'package:flutter/material.dart';
import 'app_theme.dart';

enum FluentButtonType { primary, secondary, ghost }

/// Bouton de l'application.
///
/// Trois états animés : repos, survol (léger éclaircissement et montée),
/// appui (enfoncement). Le libellé est toujours contraint et tronqué —
/// c'est ce qui empêche un texte long de faire déborder une barre d'actions.
class FluentButton extends StatefulWidget {
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
  State<FluentButton> createState() => _FluentButtonState();
}

class _FluentButtonState extends State<FluentButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.isLoading;

    Color fg;
    Color? bg;
    Gradient? gradient;
    BoxBorder? border;
    List<BoxShadow> shadows = const [];

    switch (widget.type) {
      case FluentButtonType.primary:
        fg = dark ? scheme.onPrimary : Colors.white;
        gradient = AppTheme.brandGradient(context);
        shadows = [
          BoxShadow(
            color: scheme.primary.withValues(alpha: _hover ? 0.45 : 0.28),
            blurRadius: _hover ? 22 : 14,
            offset: Offset(0, _hover ? 8 : 5),
          ),
        ];
        break;
      case FluentButtonType.secondary:
        fg = scheme.primary;
        bg = scheme.primary.withValues(alpha: _hover ? 0.18 : 0.11);
        border = Border.all(color: scheme.primary.withValues(alpha: 0.35));
        break;
      case FluentButtonType.ghost:
        fg = scheme.onSurface.withValues(alpha: 0.9);
        bg = _hover
            ? scheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent;
        border = Border.all(color: scheme.outline.withValues(alpha: 0.7));
        break;
    }

    final hPad = widget.compact ? 12.0 : 18.0;
    final vPad = widget.compact ? 10.0 : 13.0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            height: 15,
            width: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          if (widget.showLabel) const SizedBox(width: 9),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 18),
          if (widget.showLabel) const SizedBox(width: 9),
        ],
        if (widget.showLabel)
          // Flexible + ellipsis : le libellé cède plutôt que de déborder.
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: widget.compact ? 13 : 14,
                letterSpacing: 0.1,
              ),
            ),
          ),
      ],
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedOpacity(
          duration: AppTheme.fast,
          opacity: enabled ? 1 : 0.45,
          child: AnimatedScale(
            duration: AppTheme.fast,
            curve: AppTheme.ease,
            scale: _pressed ? 0.96 : 1,
            child: AnimatedContainer(
              duration: AppTheme.fast,
              curve: AppTheme.ease,
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              decoration: BoxDecoration(
                color: gradient == null ? bg : null,
                gradient: gradient,
                borderRadius: BorderRadius.circular(AppTheme.rButton),
                border: border,
                boxShadow: enabled && !_pressed ? shadows : const [],
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Carte de l'application.
///
/// Réagit au survol (souris) et à l'appui : élévation et bordure s'animent.
/// Une carte cliquable doit se comporter comme telle, c'est ce qui distingue
/// une interface vivante d'une image.
class FluentCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  /// Accentue la carte : bordure teintée et halo coloré.
  final bool highlighted;

  const FluentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.highlighted = false,
  });

  @override
  State<FluentCard> createState() => _FluentCardState();
}

class _FluentCardState extends State<FluentCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final interactive = widget.onTap != null;
    final lifted = interactive && _hover;

    final borderColor = widget.highlighted
        ? scheme.primary.withValues(alpha: 0.55)
        : lifted
        ? scheme.primary.withValues(alpha: 0.35)
        : scheme.outline.withValues(alpha: dark ? 0.85 : 0.6);

    final card = AnimatedContainer(
      duration: AppTheme.fast,
      curve: AppTheme.ease,
      margin: widget.margin,
      transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: borderColor, width: widget.highlighted ? 1.4 : 1),
        boxShadow: _pressed
            ? AppTheme.shadow(context, strength: 0.4)
            : AppTheme.shadow(context, strength: lifted ? 1.25 : 0.75),
      ),
      // clipBehavior : un enfant trop large (tableau, longue ligne) est coupé
      // proprement au rayon de la carte au lieu de déborder en jaune et noir.
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (!interactive) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: AppTheme.fast,
          curve: AppTheme.ease,
          scale: _pressed ? 0.985 : 1,
          child: card,
        ),
      ),
    );
  }
}

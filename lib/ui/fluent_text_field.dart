import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Champ de saisie de l'application.
///
/// L'icône se colore quand le champ prend le focus : un repère visuel discret
/// qui indique où l'on écrit, utile sur les formulaires longs du dossier
/// patient.
class FluentTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? hint;

  const FluentTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.hint,
  });

  @override
  State<FluentTextField> createState() => _FluentTextFieldState();
}

class _FluentTextFieldState extends State<FluentTextField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus != _focused) {
        setState(() => _focused = _node.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      cursorColor: scheme.primary,
      cursorRadius: const Radius.circular(2),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.icon == null
            ? null
            : AnimatedContainer(
                duration: AppTheme.fast,
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  widget.icon,
                  size: 19,
                  color: _focused
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

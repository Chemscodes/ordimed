import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart' as fmt;
import '../core/validate.dart' as v;
import 'app_theme.dart';

/// Champ de saisie unique de l'application.
///
/// Un seul widget, des constructeurs nommés par nature de donnée. Chaque
/// constructeur apporte d'un bloc : le bon clavier, les bons filtres de
/// frappe, le bon validateur et la bonne unité. Impossible d'avoir un champ
/// « téléphone » sans clavier numérique, ou un champ « montant » sans
/// validation — c'est le point : supprimer la classe entière d'incohérences
/// où chaque écran recompose ces réglages à la main.
class AppField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;

  /// Unité affichée à droite du champ : `DA`, `cm`, `kg`, `ans`.
  final String? suffix;

  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final List<TextInputFormatter> formatters;
  final bool obscure;
  final int maxLines;
  final bool autofocus;
  final String? helper;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onChanged;

  const AppField._({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.formatters = const [],
    this.obscure = false,
    this.maxLines = 1,
    this.autofocus = false,
    this.helper,
    this.capitalization = TextCapitalization.none,
    this.onChanged,
  });

  /// Texte libre. [obligatoire] applique la validation « champ requis ».
  factory AppField.text({
    Key? key,
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool obligatoire = false,
    String? helper,
    int maxLines = 1,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      hint: hint,
      icon: icon,
      helper: helper,
      maxLines: maxLines,
      autofocus: autofocus,
      onChanged: onChanged,
      capitalization: TextCapitalization.sentences,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      validator: obligatoire ? (s) => v.required(s, champ: label) : null,
    );
  }

  /// Nom ou prénom : capitale automatique, longueur bornée.
  factory AppField.nom({
    Key? key,
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool obligatoire = true,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      icon: icon,
      autofocus: autofocus,
      onChanged: onChanged,
      capitalization: TextCapitalization.words,
      validator: obligatoire
          ? (s) => v.nom(s, champ: label)
          : (s) => (s ?? '').trim().isEmpty ? null : v.nom(s, champ: label),
    );
  }

  /// Âge en années : clavier numérique, entier borné.
  factory AppField.age({
    Key? key,
    required TextEditingController controller,
    String label = 'Âge',
    bool obligatoire = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      icon: Icons.cake_outlined,
      suffix: 'ans',
      keyboardType: TextInputType.number,
      formatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      onChanged: onChanged,
      validator: (s) => v.age(s, obligatoire: obligatoire),
    );
  }

  /// Téléphone algérien : chiffres uniquement, 10 au maximum.
  factory AppField.phone({
    Key? key,
    required TextEditingController controller,
    String label = 'Téléphone',
    bool obligatoire = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      hint: '0551 68 62 12',
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
      formatters: [
        // On laisse passer le + et les espaces : un numéro collé depuis
        // WhatsApp arrive souvent en +213… et sera normalisé à la validation.
        FilteringTextInputFormatter.allow(RegExp(r'[\d +]')),
        LengthLimitingTextInputFormatter(17),
      ],
      onChanged: onChanged,
      validator: (s) => v.phone(s, obligatoire: obligatoire),
    );
  }

  /// Adresse e-mail.
  factory AppField.email({
    Key? key,
    required TextEditingController controller,
    String label = 'E-mail',
    bool obligatoire = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      hint: 'nom@domaine.com',
      icon: Icons.mail_outline,
      keyboardType: TextInputType.emailAddress,
      formatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      onChanged: onChanged,
      validator: (s) => v.email(s, obligatoire: obligatoire),
    );
  }

  /// Montant en dinars : clavier décimal, virgule ou point acceptés.
  factory AppField.montant({
    Key? key,
    required TextEditingController controller,
    String label = 'Montant',
    String? helper,
    bool obligatoire = false,
    double min = 0,
    double max = 10000000,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      helper: helper,
      icon: Icons.payments_outlined,
      suffix: 'DA',
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      formatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
        LengthLimitingTextInputFormatter(12),
      ],
      onChanged: onChanged,
      validator: (s) => v.montant(
        s,
        obligatoire: obligatoire,
        min: min,
        max: max,
        champ: label,
      ),
    );
  }

  /// Nombre entier générique (séances, quantités).
  factory AppField.entier({
    Key? key,
    required TextEditingController controller,
    required String label,
    String? suffix,
    String? helper,
    IconData? icon,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      suffix: suffix,
      helper: helper,
      icon: icon,
      keyboardType: TextInputType.number,
      formatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: onChanged,
      validator: validator,
    );
  }

  /// Mesure physiologique : poids, taille, tour de taille.
  factory AppField.mesure({
    Key? key,
    required TextEditingController controller,
    required String label,
    required String unite,
    required String? Function(String?) validator,
    IconData? icon,
    ValueChanged<String>? onChanged,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      suffix: unite,
      icon: icon,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      formatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: onChanged,
      validator: validator,
    );
  }

  /// Mot de passe, avec bascule de visibilité.
  factory AppField.password({
    Key? key,
    required TextEditingController controller,
    String label = 'Mot de passe',
    bool obligatoire = true,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      icon: Icons.lock_outline,
      obscure: true,
      validator: obligatoire ? v.password : null,
    );
  }

  /// Code PIN d'un profil.
  factory AppField.pin({
    Key? key,
    required TextEditingController controller,
    String label = 'Code PIN',
    bool autofocus = false,
  }) {
    return AppField._(
      controller: controller,
      label: label,
      icon: Icons.pin_outlined,
      obscure: true,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      formatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      validator: v.pin,
    );
  }

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  final FocusNode _node = FocusNode();
  bool _focused = false;
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
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

    return TextFormField(
      controller: widget.controller,
      focusNode: _node,
      autofocus: widget.autofocus,
      obscureText: widget.obscure && _hidden,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.formatters,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      textCapitalization: widget.capitalization,
      cursorColor: scheme.primary,
      onChanged: widget.onChanged,
      validator: widget.validator,
      // La validation se déclenche à la première interaction, pas au premier
      // affichage : un formulaire vide ne doit pas s'ouvrir tout en rouge.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        prefixIcon: widget.icon == null
            ? null
            : Padding(
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
        suffixIcon: _buildSuffix(scheme),
      ),
    );
  }

  Widget? _buildSuffix(ColorScheme scheme) {
    if (widget.obscure) {
      return IconButton(
        tooltip: _hidden ? 'Afficher' : 'Masquer',
        icon: Icon(
          _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 19,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      );
    }
    final s = widget.suffix;
    if (s == null) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 14, left: 8),
      child: Text(
        s,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.55),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Valeur calculée, affichée mais non saisissable.
///
/// L'IMC, le reste à payer et les séances restantes se déduisent d'autres
/// champs. Les présenter dans un cadre visuellement distinct dit à
/// l'utilisateur « ne cherche pas à modifier ça » sans avoir à l'écrire.
class ComputedValue extends StatelessWidget {
  final String label;

  /// Valeur formatée, ou `null` si elle n'est pas encore calculable.
  final String? value;

  /// Précision affichée sous la valeur : catégorie d'IMC, échéance…
  final String? note;

  final IconData? icon;

  /// Message affiché quand [value] est `null` — dit *ce qui manque*.
  final String placeholder;

  /// Teinte d'accent. Par défaut la primaire du thème.
  final Color? accent;

  const ComputedValue({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.icon,
    this.placeholder = 'En attente de saisie',
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = accent ?? scheme.primary;
    final calcule = value != null;

    // Teinte fusionnée avec la surface : une semi-transparence laisserait
    // remonter le fond sombre de l'AppShell et délaverait la carte.
    final fond = Color.alphaBlend(
      couleur.withValues(alpha: calcule ? 0.09 : 0.04),
      scheme.surface,
    );

    return AnimatedContainer(
      duration: AppTheme.mid,
      curve: AppTheme.ease,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        border: Border.all(
          color: couleur.withValues(alpha: calcule ? 0.35 : 0.15),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 19,
              color: couleur.withValues(alpha: calcule ? 1 : 0.4),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ?? placeholder,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: calcule ? 17 : 13,
                    fontWeight: calcule ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: calcule ? -0.3 : 0,
                    fontStyle: calcule ? FontStyle.normal : FontStyle.italic,
                    color: calcule
                        ? scheme.onSurface
                        : scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                if (note != null && calcule) ...[
                  const SizedBox(height: 2),
                  Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(couleur, scheme.onSurface, 0.25),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Repère discret : cette valeur est calculée, pas saisie.
          Tooltip(
            message: 'Valeur calculée automatiquement',
            child: Icon(
              Icons.functions,
              size: 15,
              color: scheme.onSurface.withValues(alpha: 0.28),
            ),
          ),
        ],
      ),
    );
  }
}

/// Boutons de montants suggérés, affichés sous un champ de versement.
///
/// Encaisser « le reste à payer » est le geste le plus courant du cabinet ;
/// le proposer d'un tap supprime une saisie et donc une faute de frappe.
class MontantsSuggeres extends StatelessWidget {
  /// Libellé → montant. Les entrées à montant nul ou négatif sont ignorées.
  final Map<String, double> suggestions;
  final ValueChanged<double> onChoisi;

  const MontantsSuggeres({
    super.key,
    required this.suggestions,
    required this.onChoisi,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = suggestions.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((e) {
        return ActionChip(
          onPressed: () => onChoisi(e.value),
          avatar: Icon(Icons.bolt, size: 15, color: scheme.primary),
          label: Text(
            '${e.key} · ${fmt.money(e.value, withSuffix: false)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
          ),
          backgroundColor: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08),
            scheme.surface,
          ),
        );
      }).toList(),
    );
  }
}

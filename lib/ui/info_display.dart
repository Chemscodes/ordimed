import 'package:flutter/material.dart';

import '../core/format.dart' as fmt;
import '../core/parcours.dart';
import 'app_theme.dart';

/// Affichage des informations.
///
/// L'app empilait partout des lignes `'Medecin: X\nAssistant: Y\nDepuis: Z'`
/// dans un sous-titre. Rien ne distinguait l'étiquette de la valeur, tout
/// avait le même poids, et l'œil devait relire chaque ligne pour trouver
/// l'information cherchée.
///
/// Ces composants séparent les deux : étiquette petite, en capitales et
/// discrète ; valeur nette et lisible. C'est ce contraste, pas la décoration,
/// qui fait qu'une interface a l'air professionnelle.

/// Couple étiquette / valeur.
class InfoPair extends StatelessWidget {
  final String label;

  /// `null` ou vide affiche [fallback] en grisé italique.
  final String? value;

  final IconData? icon;
  final String fallback;

  /// Met la valeur en évidence (chiffre clé, montant).
  final bool emphasis;

  /// Teinte de la valeur. Sert aux états sémantiques (dû, soldé, alerte).
  final Color? valueColor;

  const InfoPair({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.fallback = 'Non renseigné',
    this.emphasis = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vide = value == null || value!.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          vide ? fallback : value!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: emphasis ? 17 : 14.5,
            fontWeight: vide
                ? FontWeight.w400
                : (emphasis ? FontWeight.w800 : FontWeight.w600),
            letterSpacing: emphasis ? -0.3 : 0,
            fontStyle: vide ? FontStyle.italic : FontStyle.normal,
            height: 1.25,
            color: vide
                ? scheme.onSurface.withValues(alpha: 0.4)
                : (valueColor ?? scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

/// Grille de couples étiquette / valeur.
///
/// Colonnes de largeur égale plutôt qu'un `Wrap` de cartes à largeur fixe :
/// celui-ci produisait des rangées irrégulières et des hauteurs inégales dès
/// qu'une valeur passait sur deux lignes.
class InfoGrid extends StatelessWidget {
  final List<InfoPair> items;

  /// Largeur minimale d'une colonne. En dessous, on réduit le nombre de
  /// colonnes plutôt que de comprimer le texte.
  final double minColumnWidth;

  final double spacing;

  const InfoGrid({
    super.key,
    required this.items,
    this.minColumnWidth = 160,
    this.spacing = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final colonnes = (c.maxWidth / (minColumnWidth + spacing))
            .floor()
            .clamp(1, items.length);
        final largeur =
            (c.maxWidth - spacing * (colonnes - 1)) / colonnes;

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: items
              .map((e) => SizedBox(width: largeur, child: e))
              .toList(),
        );
      },
    );
  }
}

/// Pastille d'initiales, teintée par le nom.
///
/// Deux patients voisins dans une liste n'ont presque jamais la même
/// couleur : le repère visuel aide à retrouver une ligne d'un coup d'œil.
class InitialsAvatar extends StatelessWidget {
  final String nom;
  final String prenom;
  final double size;

  const InitialsAvatar({
    super.key,
    required this.nom,
    this.prenom = '',
    this.size = 44,
  });

  /// Teinte dérivée du nom : stable d'un affichage à l'autre.
  Color _teinte(ColorScheme scheme) {
    final graine = '$nom$prenom'.hashCode.abs();
    const palette = [
      Color(0xFF0EA5A4),
      Color(0xFF6366F1),
      Color(0xFFF97316),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
      Color(0xFF0891B2),
    ];
    return palette[graine % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = _teinte(scheme);

    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [couleur, Color.lerp(couleur, Colors.black, 0.22)!],
        ),
        boxShadow: [
          BoxShadow(
            color: couleur.withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        fmt.initials(nom, prenom),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Ligne de liste représentant une personne.
///
/// Remplace le `ListTile` dont le sous-titre concaténait des lignes
/// `'Label: valeur'`. Ici l'identité domine, les métadonnées sont
/// secondaires et alignées, l'état est une pastille, et les actions sont
/// à droite — une hiérarchie au lieu d'un bloc de texte.
class PersonRow extends StatefulWidget {
  final String nom;
  final String prenom;

  /// Métadonnées secondaires, affichées en ligne et séparées par des points.
  final List<String> meta;

  final EtapeParcours? etape;

  /// Information de droite : heure d'arrivée, montant dû…
  final Widget? trailing;

  final List<Widget> actions;
  final VoidCallback? onTap;

  const PersonRow({
    super.key,
    required this.nom,
    this.prenom = '',
    this.meta = const [],
    this.etape,
    this.trailing,
    this.actions = const [],
    this.onTap,
  });

  @override
  State<PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<PersonRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = widget.meta.where((m) => m.trim().isNotEmpty).toList();
    final nomComplet = '${widget.nom} ${widget.prenom}'.trim();

    final contenu = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InitialsAvatar(nom: widget.nom, prenom: widget.prenom),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      nomComplet.isEmpty ? 'Patient' : nomComplet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (widget.etape != null) ...[
                    const SizedBox(width: 10),
                    EtapeChip(etape: widget.etape!, compact: true),
                  ],
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                // Une seule ligne à puces médianes plutôt que quatre lignes
                // « Label: valeur » : trois fois moins de hauteur, et l'œil
                // balaie horizontalement au lieu de relire verticalement.
                Text(
                  meta.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 12),
          widget.trailing!,
        ],
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: widget.actions),
        ],
      ],
    );

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.fast,
          curve: AppTheme.ease,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            border: Border.all(
              color: _hover && widget.onTap != null
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outline.withValues(alpha: 0.7),
            ),
            boxShadow: AppTheme.shadow(
              context,
              strength: _hover && widget.onTap != null ? 1.0 : 0.5,
            ),
          ),
          child: contenu,
        ),
      ),
    );
  }
}

/// Ligne de métadonnées secondaires, séparées par des puces médianes.
///
/// Remplace les sous-titres qui empilaient `'Medecin: X\nAssistant: Y'` :
/// une ligne au lieu de quatre, l'œil balaie horizontalement au lieu de
/// relire verticalement, et la carte cesse d'être trois fois trop haute.
///
/// [etape] ajoute une pastille d'état en tête de ligne.
class MetaLine extends StatelessWidget {
  final List<String> items;
  final EtapeParcours? etape;

  const MetaLine({super.key, required this.items, this.etape});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibles = items.where((e) => e.trim().isNotEmpty).toList();

    final texte = Text(
      visibles.join('  ·  '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: scheme.onSurface.withValues(alpha: 0.62),
      ),
    );

    if (etape == null) return texte;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 5),
        EtapeChip(etape: etape!, compact: true),
        if (visibles.isNotEmpty) ...[const SizedBox(height: 6), texte],
      ],
    );
  }
}

/// Bloc horodaté aligné à droite d'une ligne : « Depuis 10:01 ».
class SinceBadge extends StatelessWidget {
  final String label;
  final String? value;

  const SinceBadge({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (value == null || value!.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value!,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// En-tête de section : titre, compteur, action à droite.
class SectionHeader extends StatelessWidget {
  final String titre;
  final int? compteur;
  final Widget? action;
  final IconData? icone;

  const SectionHeader({
    super.key,
    required this.titre,
    this.compteur,
    this.action,
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          if (icone != null) ...[
            Icon(icone, size: 17, color: scheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            titre,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          if (compteur != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.14),
                  scheme.surface,
                ),
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Text(
                '$compteur',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

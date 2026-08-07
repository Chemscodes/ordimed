import 'package:flutter/material.dart';

/// Le parcours d'une visite, du rendez-vous à la sortie du patient.
///
/// Le cabinet tenait deux vocabulaires séparés : les rendez-vous n'avaient
/// aucun statut, la salle d'attente en avait un à elle (`waiting`,
/// `in_consultation`, `done`). Résultat, un rendez-vous restait « à venir »
/// pour toujours, même honoré, et personne ne pouvait dire d'un patient où
/// il en était sans regarder deux collections.
///
/// C'est un seul cycle de vie, celui que tiennent Doctolib, Cliniko et Jane :
///
/// ```
///   planifié → confirmé → arrivé → en cours → honoré
///                  ↓         ↓        ↓
///               annulé    absent   (annulé)
/// ```
///
/// `absent` est une étape à part entière, pas un oubli : un patient qui ne
/// vient pas est une information de gestion, pas une absence de donnée.
enum EtapeParcours {
  planifie('planifie', 'Planifié', Icons.event_outlined, 0),
  confirme('confirme', 'Confirmé', Icons.event_available_outlined, 1),
  arrive('arrive', 'En salle', Icons.chair_outlined, 2),
  enCours('en_cours', 'En consultation', Icons.medical_services_outlined, 3),
  honore('honore', 'Honoré', Icons.check_circle_outline, 4),
  absent('absent', 'Absent', Icons.person_off_outlined, 5),
  annule('annule', 'Annulé', Icons.event_busy_outlined, 6);

  /// Valeur stockée dans Firestore. Sans accent ni espace : elle voyage.
  final String code;
  final String libelle;
  final IconData icone;

  /// Rang d'affichage. Trier sur l'énumération elle-même lierait l'ordre à
  /// celui des déclarations, qu'on voudra peut-être changer.
  final int ordre;

  const EtapeParcours(this.code, this.libelle, this.icone, this.ordre);

  /// La visite est encore en cours : elle attend un geste du cabinet.
  bool get estOuverte =>
      this == planifie || this == confirme || this == arrive || this == enCours;

  /// La visite est close, quelle qu'en soit l'issue.
  bool get estClose => !estOuverte;

  /// Le patient est physiquement dans le cabinet.
  bool get estPresent => this == arrive || this == enCours;

  /// Issue négative : le patient n'a pas été vu.
  bool get estManquee => this == absent || this == annule;

  /// Étapes atteignables depuis celle-ci.
  ///
  /// L'ordre compte : la première est l'action normale, celle qu'on met en
  /// avant. Les suivantes sont les sorties.
  List<EtapeParcours> get suivantes {
    switch (this) {
      case planifie:
        return const [confirme, arrive, annule];
      case confirme:
        return const [arrive, absent, annule];
      case arrive:
        return const [enCours, absent];
      case enCours:
        return const [honore];
      case honore:
      case absent:
      case annule:
        return const [];
    }
  }

  /// L'action normale depuis cette étape, s'il en reste une.
  EtapeParcours? get suivante => suivantes.isEmpty ? null : suivantes.first;

  /// Libellé du bouton qui fait passer à [cible].
  ///
  /// Un bouton nomme un geste, pas un état d'arrivée — la salle d'attente
  /// avait un bouton « En consultation » que personne ne reconnaissait
  /// comme cliquable.
  String verbeVers(EtapeParcours cible) {
    switch (cible) {
      case confirme:
        return 'Confirmer';
      case arrive:
        return 'Le patient est arrivé';
      case enCours:
        return 'Consulter';
      case honore:
        return 'Terminer';
      case absent:
        return 'Noter absent';
      case annule:
        return 'Annuler';
      case planifie:
        return 'Replanifier';
    }
  }

  /// Couleur de l'étape, dérivée du thème pour suivre clair et sombre.
  Color couleur(ColorScheme scheme) {
    switch (this) {
      case planifie:
        return scheme.onSurface.withValues(alpha: 0.55);
      case confirme:
        return scheme.primary;
      case arrive:
        return scheme.tertiary;
      case enCours:
        return scheme.secondary;
      case honore:
        return const Color(0xFF16A34A);
      case absent:
        return const Color(0xFFEA580C);
      case annule:
        return scheme.error;
    }
  }

  static EtapeParcours? fromCode(String? code) {
    if (code == null) return null;
    final c = code.trim().toLowerCase();
    for (final e in EtapeParcours.values) {
      if (e.code == c) return e;
    }
    return null;
  }

  /// Déduit l'étape d'un document de salle d'attente.
  ///
  /// Les anciens documents ne portent pas `etape` : ils ont l'ancien `status`
  /// et des horodatages. On les lit encore, sinon toute la file existante
  /// deviendrait illisible du jour au lendemain.
  static EtapeParcours fromWaiting(Map<String, dynamic> data) {
    final connue = fromCode(data['etape']?.toString());
    if (connue != null) return connue;

    final statut = (data['status'] ?? '').toString().toLowerCase();
    if (statut == 'cancelled' || statut == 'canceled') return annule;
    if (data['closedAt'] != null || statut == 'done' || statut == 'closed') {
      return honore;
    }
    if (statut == 'in_consultation' || data['inConsultationAt'] != null) {
      return enCours;
    }
    return arrive;
  }

  /// Déduit l'étape d'un rendez-vous.
  ///
  /// Les rendez-vous existants n'ont aucun statut : ils sont planifiés, et
  /// c'est tout ce qu'on peut honnêtement en dire.
  static EtapeParcours fromRendezVous(Map<String, dynamic> data) =>
      fromCode(data['etape']?.toString()) ?? planifie;
}

/// Pastille d'étape : icône, libellé, couleur de l'étape.
class EtapeChip extends StatelessWidget {
  final EtapeParcours etape;
  final bool compact;

  const EtapeChip({super.key, required this.etape, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = etape.couleur(scheme);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(couleur.withValues(alpha: 0.14), scheme.surface),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: couleur.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(etape.icone, size: compact ? 12 : 14, color: couleur),
          SizedBox(width: compact ? 4 : 6),
          Text(
            etape.libelle,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: Color.lerp(couleur, scheme.onSurface, 0.25),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fil du parcours : montre où en est la visite et ce qui reste.
///
/// Les étapes de sortie (absent, annulé) n'y figurent pas quand elles ne
/// sont pas atteintes — un fil doit se lire comme un chemin, pas comme un
/// arbre de décision.
class FilParcours extends StatelessWidget {
  final EtapeParcours courante;

  const FilParcours({super.key, required this.courante});

  static const _chemin = [
    EtapeParcours.planifie,
    EtapeParcours.confirme,
    EtapeParcours.arrive,
    EtapeParcours.enCours,
    EtapeParcours.honore,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Une visite manquée n'a plus de chemin à montrer : elle s'est arrêtée.
    if (courante.estManquee) {
      return EtapeChip(etape: courante);
    }

    final index = _chemin.indexOf(courante);

    return Row(
      children: [
        for (var i = 0; i < _chemin.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= index
                    ? _chemin[i].couleur(scheme).withValues(alpha: 0.5)
                    : scheme.outline.withValues(alpha: 0.5),
              ),
            ),
          _Pastille(
            etape: _chemin[i],
            faite: i < index,
            courante: i == index,
          ),
        ],
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  final EtapeParcours etape;
  final bool faite;
  final bool courante;

  const _Pastille({
    required this.etape,
    required this.faite,
    required this.courante,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = etape.couleur(scheme);
    final actif = faite || courante;

    return Tooltip(
      message: etape.libelle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: courante ? 26 : 20,
        height: courante ? 26 : 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: actif
              ? Color.alphaBlend(
                  couleur.withValues(alpha: courante ? 0.9 : 0.55),
                  scheme.surface,
                )
              : scheme.surface,
          border: Border.all(
            color: actif
                ? couleur
                : scheme.outline.withValues(alpha: 0.7),
            width: courante ? 2 : 1,
          ),
        ),
        child: Icon(
          faite ? Icons.check : etape.icone,
          size: courante ? 14 : 11,
          color: actif ? Colors.white : scheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

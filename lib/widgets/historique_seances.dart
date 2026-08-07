import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/coerce.dart';
import '../core/format.dart' as fmt;
import '../services/firestore_service.dart';
import '../ui/app_theme.dart';
import '../ui/info_display.dart';

/// Une séance passée, telle qu'on peut la relire.
class Seance {
  final DateTime? date;
  final double? poids;
  final double? taille;
  final String imc;
  final String notes;

  const Seance({
    this.date,
    this.poids,
    this.taille,
    this.imc = '',
    this.notes = '',
  });

  /// Relit une séance depuis un document.
  ///
  /// Les consultations récentes portent des champs typés. Les anciennes n'ont
  /// que `contenu`, un bloc de texte — on en retire ce qu'on peut plutôt que
  /// de les afficher vides, mais sans y chercher les mesures : deviner un
  /// poids dans du texte libre finirait par produire un chiffre faux, et un
  /// chiffre faux sur un dossier médical est pire qu'un chiffre absent.
  factory Seance.fromForm(Map<String, dynamic> data) {
    final notes = asTextOrNull(data['notes']);
    return Seance(
      date: asDateOrNull(data['createdAt']),
      poids: asDoubleOrNull(data['poids']),
      taille: asDoubleOrNull(data['taille']),
      imc: asText(data['imc']),
      notes: notes ?? asText(data['contenu']),
    );
  }

  bool get aDesMesures => poids != null || taille != null || imc.isNotEmpty;
  bool get estVide => !aDesMesures && notes.trim().isEmpty;
}

/// Historique des séances d'un patient.
///
/// Il n'existait nulle part. Le dossier montrait des documents en vrac —
/// ordonnances, bilans et consultations mélangés, du plus récent au plus
/// ancien — sans qu'on puisse répondre à la question que le médecin pose
/// vraiment en s'asseyant : « qu'est-ce qui s'est passé la dernière fois,
/// et est-ce que ça va mieux ? »
///
/// D'où la variation de poids d'une séance à l'autre : une colonne de
/// chiffres ne se lit pas, un écart se lit.
class HistoriqueSeances extends StatelessWidget {
  final String parentUid;
  final String profileId;
  final String patientId;

  /// Nombre de séances affichées. Au-delà, un compteur.
  final int limite;

  /// En mode compact, les notes sont tronquées : la consultation en cours
  /// a besoin du rappel, pas du dossier complet.
  final bool compact;

  const HistoriqueSeances({
    super.key,
    required this.parentUid,
    required this.profileId,
    required this.patientId,
    this.limite = 6,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService().patientForms(
        parentUid: parentUid,
        profileId: profileId,
        patientId: patientId,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _Message('Historique indisponible');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final seances =
            snap.data!.docs
                .map((d) => d.data() as Map<String, dynamic>)
                .where((d) => asText(d['type']) == 'Consultation')
                .map(Seance.fromForm)
                .where((s) => !s.estVide)
                .toList()
              // Le tri se fait ici plutôt que dans la requête : les documents
              // sans `createdAt` — il en existe — seraient exclus par un
              // orderBy Firestore, et disparaîtraient de l'historique.
              ..sort((a, b) {
                final da = a.date, db = b.date;
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return db.compareTo(da);
              });

        if (seances.isEmpty) {
          return const _Message(
            'Aucune séance enregistrée. Ce sera la première.',
          );
        }

        final visibles = seances.take(limite).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < visibles.length; i++)
              _LigneSeance(
                seance: visibles[i],
                // La séance suivante dans la liste est la précédente dans le
                // temps : c'est à elle qu'on compare.
                precedente: i + 1 < seances.length ? seances[i + 1] : null,
                premiere: i == 0,
                derniere: i == visibles.length - 1,
                compact: compact,
              ),
            if (seances.length > visibles.length)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 4),
                child: Text(
                  '+ ${seances.length - visibles.length} séance'
                  '${seances.length - visibles.length > 1 ? 's' : ''} '
                  'plus ancienne'
                  '${seances.length - visibles.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LigneSeance extends StatelessWidget {
  final Seance seance;
  final Seance? precedente;
  final bool premiere;
  final bool derniere;
  final bool compact;

  const _LigneSeance({
    required this.seance,
    required this.precedente,
    required this.premiere,
    required this.derniere,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = premiere ? scheme.primary : scheme.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le rail : point de la séance, trait vers la suivante.
          Column(
            children: [
              Container(
                width: premiere ? 14 : 10,
                height: premiere ? 14 : 10,
                margin: EdgeInsets.only(top: premiere ? 4 : 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: premiere ? scheme.primary : scheme.surface,
                  border: Border.all(color: couleur, width: 2),
                ),
              ),
              if (!derniere)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: scheme.outline.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: derniere ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          seance.date == null
                              ? 'Date inconnue'
                              : fmt.capitalize(fmt.relativeDay(seance.date)),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: premiere ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (seance.date != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          fmt.date(seance.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (seance.aDesMesures) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (seance.poids != null)
                          _Mesure(
                            libelle: 'Poids',
                            valeur: '${fmt.money(seance.poids, withSuffix: false)} kg',
                            ecart: _ecartPoids(),
                          ),
                        if (seance.taille != null)
                          _Mesure(
                            libelle: 'Taille',
                            valeur:
                                '${seance.taille!.toStringAsFixed(0)} cm',
                          ),
                        if (seance.imc.isNotEmpty)
                          _Mesure(libelle: 'IMC', valeur: seance.imc),
                      ],
                    ),
                  ],
                  if (seance.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      seance.notes.trim(),
                      maxLines: compact ? 2 : 8,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: scheme.onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Variation de poids depuis la séance précédente.
  ///
  /// Nul quand il n'y a rien à comparer — afficher « +0,0 kg » faute de
  /// mesure antérieure ferait croire à une stabilité constatée.
  double? _ecartPoids() {
    final avant = precedente?.poids;
    final maintenant = seance.poids;
    if (avant == null || maintenant == null) return null;
    final ecart = maintenant - avant;
    return ecart.abs() < 0.05 ? null : ecart;
  }
}

class _Mesure extends StatelessWidget {
  final String libelle;
  final String valeur;
  final double? ecart;

  const _Mesure({required this.libelle, required this.valeur, this.ecart});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = ecart;
    final couleurEcart = e == null
        ? null
        : (e > 0 ? const Color(0xFFEA580C) : const Color(0xFF16A34A));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$libelle ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Text(
            valeur,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (e != null) ...[
            const SizedBox(width: 6),
            Icon(
              e > 0 ? Icons.trending_up : Icons.trending_down,
              size: 13,
              color: couleurEcart,
            ),
            const SizedBox(width: 2),
            Text(
              '${e > 0 ? '+' : '−'}${fmt.money(e.abs(), withSuffix: false)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: couleurEcart,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String texte;

  const _Message(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.history_outlined,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'historique prête à poser dans une page.
class CarteHistoriqueSeances extends StatelessWidget {
  final String parentUid;
  final String profileId;
  final String patientId;
  final int limite;
  final bool compact;

  const CarteHistoriqueSeances({
    super.key,
    required this.parentUid,
    required this.profileId,
    required this.patientId,
    this.limite = 6,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            titre: 'Séances précédentes',
            icone: Icons.history,
          ),
          const SizedBox(height: 14),
          HistoriqueSeances(
            parentUid: parentUid,
            profileId: profileId,
            patientId: patientId,
            limite: limite,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

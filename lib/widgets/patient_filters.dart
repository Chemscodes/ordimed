import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/clinical.dart';
import '../core/coerce.dart';
import '../services/soft_delete.dart';
import '../ui/app_theme.dart';

/// Filtres rapides de la liste des patients.
///
/// La recherche par nom ne répondait à aucune des deux questions que le
/// cabinet se pose tous les jours : « qui me doit encore de l'argent » et
/// « à qui reste-t-il des séances ». Ces deux-là sont donc des filtres à
/// part entière, pas des options enfouies.
enum PatientFiltre {
  tous,
  resteAPayer,
  seancesRestantes,
  soldes;

  String get libelle {
    switch (this) {
      case PatientFiltre.tous:
        return 'Tous';
      case PatientFiltre.resteAPayer:
        return 'Reste à payer';
      case PatientFiltre.seancesRestantes:
        return 'Séances restantes';
      case PatientFiltre.soldes:
        return 'Soldés';
    }
  }

  IconData get icone {
    switch (this) {
      case PatientFiltre.tous:
        return Icons.groups_outlined;
      case PatientFiltre.resteAPayer:
        return Icons.account_balance_wallet_outlined;
      case PatientFiltre.seancesRestantes:
        return Icons.event_repeat_outlined;
      case PatientFiltre.soldes:
        return Icons.task_alt;
    }
  }

  /// Le patient passe-t-il ce filtre ?
  bool accepte(Map<String, dynamic> data) {
    switch (this) {
      case PatientFiltre.tous:
        return true;
      case PatientFiltre.resteAPayer:
        final r = Reglement.fromPatient(data).reste;
        return r != null && r > 0;
      case PatientFiltre.seancesRestantes:
        final s = Seances.fromPatient(data).restantes;
        return s != null && s > 0;
      case PatientFiltre.soldes:
        return Reglement.fromPatient(data).solde;
    }
  }
}

/// Critères actifs sur la liste : texte, filtre rapide, médecin.
class PatientQuery {
  final String texte;
  final PatientFiltre filtre;

  /// `null` = tous les médecins.
  final String? doctorId;

  const PatientQuery({
    this.texte = '',
    this.filtre = PatientFiltre.tous,
    this.doctorId,
  });

  PatientQuery copyWith({
    String? texte,
    PatientFiltre? filtre,
    Object? doctorId = _unset,
  }) {
    return PatientQuery(
      texte: texte ?? this.texte,
      filtre: filtre ?? this.filtre,
      doctorId: identical(doctorId, _unset)
          ? this.doctorId
          : doctorId as String?,
    );
  }

  static const Object _unset = Object();

  bool get actif =>
      texte.isNotEmpty || filtre != PatientFiltre.tous || doctorId != null;

  /// Applique tous les critères, suppression douce comprise.
  ///
  /// Le filtrage se fait en mémoire et non dans la requête Firestore : un
  /// `where('deletedAt', isNull: true)` masquerait tous les dossiers créés
  /// avant l'introduction de la suppression douce, qui n'ont pas ce champ.
  bool accepte(Map<String, dynamic> data) {
    if (isDeleted(data)) return false;

    if (doctorId != null && asText(data['doctorId']) != doctorId) return false;
    if (!filtre.accepte(data)) return false;

    if (texte.isEmpty) return true;
    final besoin = texte.toLowerCase();
    final nom = asText(data['nom']).toLowerCase();
    final prenom = asText(data['prenom']).toLowerCase();
    final tel = asText(data['tel']);
    // La recherche couvre aussi le téléphone : à l'accueil, un patient se
    // retrouve souvent par son numéro plutôt que par l'orthographe de son nom.
    return '$nom $prenom'.contains(besoin) ||
        '$prenom $nom'.contains(besoin) ||
        tel.contains(besoin);
  }

  /// Filtre une liste de documents Firestore.
  List<QueryDocumentSnapshot> filtrer(List<QueryDocumentSnapshot> docs) {
    return docs.where((d) {
      final data = d.data();
      if (data is! Map<String, dynamic>) return false;
      return accepte(data);
    }).toList();
  }
}

/// Barre de filtres : pastilles rapides et sélection du médecin.
class PatientFilterBar extends StatelessWidget {
  final PatientQuery query;
  final ValueChanged<PatientQuery> onChanged;

  /// id de profil → nom affiché. Vide masque le sélecteur de médecin.
  final Map<String, String> medecins;

  /// Nombre de résultats après filtrage, affiché quand un critère est actif.
  final int? resultats;

  const PatientFilterBar({
    super.key,
    required this.query,
    required this.onChanged,
    this.medecins = const {},
    this.resultats,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Défilement horizontal : avec un médecin de plus, une barre en Row
        // déborderait sur fenêtre étroite.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              ...PatientFiltre.values.map((f) {
                final actif = query.filtre == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: actif,
                    avatar: Icon(f.icone, size: 16),
                    label: Text(f.libelle),
                    onSelected: (_) => onChanged(query.copyWith(filtre: f)),
                  ),
                );
              }),
              if (medecins.isNotEmpty) ...[
                Container(
                  height: 26,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: scheme.outline.withValues(alpha: 0.5),
                ),
                _SelecteurMedecin(
                  medecins: medecins,
                  selection: query.doctorId,
                  onChanged: (id) => onChanged(query.copyWith(doctorId: id)),
                ),
              ],
            ],
          ),
        ),
        // La réinitialisation apparaît dès qu'un critère est posé. Le
        // compteur, lui, n'est affiché que si l'appelant le connaît — il
        // n'est pas toujours calculable avant le rendu de la liste.
        if (query.actif) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 15,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              if (resultats != null)
                Text(
                  resultats == 0
                      ? 'Aucun patient ne correspond'
                      : '$resultats patient${resultats == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => onChanged(
                  const PatientQuery(),
                ),
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Réinitialiser'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SelecteurMedecin extends StatelessWidget {
  final Map<String, String> medecins;
  final String? selection;
  final ValueChanged<String?> onChanged;

  const _SelecteurMedecin({
    required this.medecins,
    required this.selection,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nom = selection == null ? 'Tous les médecins' : medecins[selection];

    return PopupMenuButton<String?>(
      tooltip: 'Filtrer par médecin',
      onSelected: (v) => onChanged(v),
      itemBuilder: (_) => [
        const PopupMenuItem<String?>(
          value: null,
          child: Text('Tous les médecins'),
        ),
        const PopupMenuDivider(),
        ...medecins.entries.map(
          (e) => PopupMenuItem<String?>(value: e.key, child: Text(e.value)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          color: selection == null
              ? Colors.transparent
              : Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.12),
                  scheme.surface,
                ),
          border: Border.all(
            color: selection == null
                ? scheme.outline
                : scheme.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medical_services_outlined,
              size: 16,
              color: selection == null ? null : scheme.primary,
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                nom ?? 'Médecin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selection == null ? null : scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/coerce.dart';
import '../core/format.dart' as fmt;
import '../core/versements.dart';
import '../ui/app_theme.dart';

enum PaymentStatus { solde, partiel, impaye, sansPrix }

List<Versement> _versementsDe(Map<String, dynamic> patientData) {
  final raw = patientData['versements'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Versement.fromMap(Map<String, dynamic>.from(e)))
      .toList();
}

double _totalVerseDe(Map<String, dynamic> patientData) {
  final totalVersementsRaw = asDoubleOrNull(patientData['totalVersements']);
  return totalVersementsRaw ?? totalDe(_versementsDe(patientData));
}

/// Reste à payer, ou `null` si aucun prix n'est fixé sur le dossier.
///
/// Partagé entre [PatientStatusIndicator] (listes de patients) et la salle
/// d'attente : même calcul, même chiffre affiché partout.
double? resteAPayerDe(Map<String, dynamic> patientData) {
  final prix = asDoubleOrNull(patientData['prix']);
  if (prix == null || prix <= 0) return null;
  final reste = prix - _totalVerseDe(patientData);
  return reste > 0 ? reste : 0;
}

PaymentStatus statutPaiementDe(Map<String, dynamic> patientData) {
  final prix = asDoubleOrNull(patientData['prix']);
  final total = _totalVerseDe(patientData);
  if (prix == null || prix <= 0) return PaymentStatus.sansPrix;
  if (total <= 0) return PaymentStatus.impaye;
  if (total >= prix) return PaymentStatus.solde;
  return PaymentStatus.partiel;
}

({Color color, String label}) specPourStatutPaiement(
  BuildContext context,
  PaymentStatus status,
) {
  switch (status) {
    case PaymentStatus.solde:
      return (color: AppTheme.menthe(context), label: 'Soldé');
    case PaymentStatus.partiel:
      return (color: AppTheme.ambre(context), label: 'Partiel');
    case PaymentStatus.impaye:
      return (color: AppTheme.corail(context), label: 'Impayé');
    case PaymentStatus.sansPrix:
      return (color: AppTheme.ink3(context), label: 'Sans prix');
  }
}

/// Pastille de statut de paiement + date relative de dernière visite,
/// affichée sous le nom dans les listes de patients.
///
/// Réutilise les mêmes primitives que le dossier patient et le graphique de
/// stats (`Versement.fromMap`, `totalDe`) : le même total s'affiche partout.
class PatientStatusIndicator extends StatelessWidget {
  final Map<String, dynamic> patientData;

  const PatientStatusIndicator({super.key, required this.patientData});

  @override
  Widget build(BuildContext context) {
    final spec = specPourStatutPaiement(
      context,
      statutPaiementDe(patientData),
    );
    final versements = _versementsDe(patientData);
    final lastVisit = versements.isNotEmpty
        ? versements.first.date
        : asDateOrNull(patientData['createdAt']);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: spec.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          spec.label,
          style: TextStyle(
            color: spec.color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (lastVisit != null) ...[
          const SizedBox(width: 8),
          Text(
            '· ${fmt.relativeDay(lastVisit)}',
            style: TextStyle(color: AppTheme.ink3(context), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Pastille compacte « reste à payer », pour une ligne de salle d'attente.
///
/// Ne s'affiche que s'il reste effectivement quelque chose à encaisser —
/// un patient soldé ou sans prix fixé ne montre rien, pour ne pas noyer les
/// cas qui comptent.
class ResteAPayerBadge extends StatelessWidget {
  final Map<String, dynamic> patientData;

  const ResteAPayerBadge({super.key, required this.patientData});

  @override
  Widget build(BuildContext context) {
    final reste = resteAPayerDe(patientData);
    if (reste == null || reste <= 0) return const SizedBox.shrink();
    final corail = AppTheme.corail(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: corail.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: corail.withValues(alpha: 0.45)),
      ),
      child: Text(
        'Doit ${fmt.money(reste)}',
        style: TextStyle(
          color: corail,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/clinical.dart';
import '../core/format.dart' as fmt;
import '../ui/app_field.dart';

/// IMC calculé en direct depuis les champs poids et taille.
///
/// Remplace un champ de saisie : le médecin tapait auparavant une division
/// dont les deux opérandes étaient juste au-dessus. Une faute de frappe y
/// devenait une donnée clinique fausse.
///
/// [syncTo] reçoit la valeur calculée sous forme de texte. C'est le pont avec
/// le code d'enregistrement existant, qui lit `imcCtrl.text` : il continue de
/// fonctionner sans modification, mais la valeur qu'il lit n'est plus saisie.
class BmiField extends StatefulWidget {
  final TextEditingController poidsCtrl;
  final TextEditingController tailleCtrl;
  final TextEditingController? syncTo;

  const BmiField({
    super.key,
    required this.poidsCtrl,
    required this.tailleCtrl,
    this.syncTo,
  });

  @override
  State<BmiField> createState() => _BmiFieldState();
}

class _BmiFieldState extends State<BmiField> {
  Bmi? _bmi;

  @override
  void initState() {
    super.initState();
    widget.poidsCtrl.addListener(_recompute);
    widget.tailleCtrl.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    widget.poidsCtrl.removeListener(_recompute);
    widget.tailleCtrl.removeListener(_recompute);
    super.dispose();
  }

  void _recompute() {
    final bmi = Bmi.compute(
      poidsKg: widget.poidsCtrl.text,
      tailleCm: widget.tailleCtrl.text,
    );

    // Le contrôleur miroir est mis à jour même quand le calcul échoue :
    // sinon un poids corrigé à la baisse laisserait l'ancien IMC en base.
    final cible = widget.syncTo;
    if (cible != null) {
      final texte = bmi?.formatted ?? '';
      if (cible.text != texte) cible.text = texte;
    }

    if (mounted && bmi?.value != _bmi?.value) setState(() => _bmi = bmi);
  }

  /// Couleur de l'accent selon la catégorie : vert au normal, ambre au
  /// surpoids, rouge à l'obésité. Le repère est visuel avant d'être textuel.
  Color _accent(ColorScheme scheme) {
    switch (_bmi?.category) {
      case null:
        return scheme.outline;
      case BmiCategory.normal:
        return const Color(0xFF16A34A);
      case BmiCategory.underweight:
      case BmiCategory.overweight:
        return scheme.secondary;
      case BmiCategory.obese1:
      case BmiCategory.obese2:
      case BmiCategory.obese3:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComputedValue(
      label: 'IMC',
      value: _bmi?.formatted,
      note: _bmi?.category.label,
      icon: Icons.straighten,
      accent: _accent(scheme),
      placeholder: 'Renseignez le poids et la taille',
    );
  }
}

/// État financier d'un dossier : reste à payer, trop-perçu ou soldé.
class ReglementSummary extends StatelessWidget {
  final Reglement reglement;

  /// Affiche la barre de progression sous le montant.
  final bool withProgress;

  const ReglementSummary({
    super.key,
    required this.reglement,
    this.withProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = reglement;

    String? valeur;
    String? note;
    Color accent;

    if (r.sansPrix) {
      valeur = null;
      note = null;
      accent = scheme.outline;
    } else if (r.tropPercu != null) {
      valeur = fmt.money(r.tropPercu);
      note = 'Trop-perçu à restituer';
      accent = scheme.secondary;
    } else if (r.solde) {
      valeur = 'Soldé';
      note = '${fmt.money(r.verse)} encaissés';
      accent = const Color(0xFF16A34A);
    } else {
      valeur = fmt.money(r.reste);
      note = '${fmt.money(r.verse)} sur ${fmt.money(r.prix)}';
      accent = scheme.primary;
    }

    final bloc = ComputedValue(
      label: r.tropPercu != null ? 'Trop-perçu' : 'Reste à payer',
      value: valeur,
      note: note,
      icon: Icons.account_balance_wallet_outlined,
      accent: accent,
      placeholder: 'Aucun prix fixé',
    );

    final progression = r.progression;
    if (!withProgress || progression == null) return bloc;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bloc,
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progression,
            minHeight: 6,
            backgroundColor: scheme.outline.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }
}

/// Avancement du forfait de séances.
class SeancesSummary extends StatelessWidget {
  final Seances seances;
  final bool withProgress;

  const SeancesSummary({
    super.key,
    required this.seances,
    this.withProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = seances;

    String? valeur;
    String? note;
    Color accent;

    if (s.sansForfait) {
      valeur = s.effectuees > 0 ? '${s.effectuees} effectuées' : null;
      note = s.effectuees > 0 ? 'Aucun forfait défini' : null;
      accent = scheme.outline;
    } else if (s.depassement != null) {
      valeur = '${s.depassement} en dépassement';
      note = 'Forfait de ${s.total} séances consommé';
      accent = scheme.secondary;
    } else if (s.termine) {
      valeur = 'Forfait terminé';
      note = '${s.total} séances réalisées';
      accent = const Color(0xFF16A34A);
    } else {
      valeur = '${s.restantes} restantes';
      note = '${s.libelle} séances';
      accent = scheme.primary;
    }

    final bloc = ComputedValue(
      label: 'Séances',
      value: valeur,
      note: note,
      icon: Icons.event_repeat_outlined,
      accent: accent,
      placeholder: 'Aucune séance enregistrée',
    );

    final progression = s.progression;
    if (!withProgress || progression == null) return bloc;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bloc,
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progression,
            minHeight: 6,
            backgroundColor: scheme.outline.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }
}

/// Calculs cliniques.
///
/// Tout ce qui se déduit d'autres valeurs se calcule ici plutôt que de se
/// saisir. Un IMC recopié à la main dans un dossier médical, c'est une
/// décision clinique fondée sur une faute de frappe.
library;

import 'coerce.dart';

/// Catégories d'IMC selon la classification de l'OMS.
enum BmiCategory {
  underweight,
  normal,
  overweight,
  obese1,
  obese2,
  obese3;

  String get label {
    switch (this) {
      case BmiCategory.underweight:
        return 'Insuffisance pondérale';
      case BmiCategory.normal:
        return 'Corpulence normale';
      case BmiCategory.overweight:
        return 'Surpoids';
      case BmiCategory.obese1:
        return 'Obésité modérée';
      case BmiCategory.obese2:
        return 'Obésité sévère';
      case BmiCategory.obese3:
        return 'Obésité morbide';
    }
  }
}

/// Indice de masse corporelle.
///
/// [poidsKg] en kilogrammes, [tailleCm] en **centimètres** — c'est l'unité que
/// le cabinet saisit. La conversion en mètres est faite ici, une seule fois,
/// plutôt que dans chaque écran.
///
/// Renvoie `null` si l'une des deux mesures manque ou sort des bornes
/// physiologiques : mieux vaut ne rien afficher qu'afficher un nombre faux.
class Bmi {
  final double value;
  final BmiCategory category;

  const Bmi._(this.value, this.category);

  /// Calcule l'IMC, ou `null` si les mesures sont absentes ou aberrantes.
  ///
  /// Bornes retenues : poids 2–500 kg, taille 30–260 cm. Elles couvrent le
  /// nourrisson comme le cas extrême, et rejettent les erreurs de saisie
  /// courantes — une taille en mètres (1,75) ou un poids en grammes.
  static Bmi? compute({required dynamic poidsKg, required dynamic tailleCm}) {
    final poids = asDoubleOrNull(poidsKg);
    final taille = asDoubleOrNull(tailleCm);
    if (poids == null || taille == null) return null;
    if (poids < 2 || poids > 500) return null;
    if (taille < 30 || taille > 260) return null;

    final metres = taille / 100;
    final imc = poids / (metres * metres);
    if (imc.isNaN || imc.isInfinite) return null;

    return Bmi._(imc, _categorize(imc));
  }

  static BmiCategory _categorize(double imc) {
    if (imc < 18.5) return BmiCategory.underweight;
    if (imc < 25) return BmiCategory.normal;
    if (imc < 30) return BmiCategory.overweight;
    if (imc < 35) return BmiCategory.obese1;
    if (imc < 40) return BmiCategory.obese2;
    return BmiCategory.obese3;
  }

  /// Valeur arrondie au dixième, comme l'usage clinique.
  String get formatted => value.toStringAsFixed(1);

  @override
  String toString() => '$formatted — ${category.label}';
}

/// État financier d'un dossier patient.
///
/// Le reste à payer et le solde ne sont plus des champs saisis : ils se
/// déduisent du prix et des versements enregistrés.
class Reglement {
  /// Total convenu avec le patient. `null` si aucun prix n'a été fixé.
  final double? prix;

  /// Somme des versements déjà encaissés.
  final double verse;

  const Reglement({required this.prix, required this.verse});

  factory Reglement.fromPatient(Map<String, dynamic>? data) {
    return Reglement(
      prix: asDoubleOrNull(data?['prix']),
      verse: asDouble(data?['totalVersements']),
    );
  }

  /// Aucun prix fixé : on ne peut rien conclure sur le solde.
  bool get sansPrix => prix == null;

  /// Reste à payer, jamais négatif. `null` si le prix n'est pas fixé.
  double? get reste {
    final p = prix;
    if (p == null) return null;
    final r = p - verse;
    return r > 0 ? r : 0;
  }

  /// Trop-perçu, s'il y en a un. `null` sinon.
  ///
  /// Un versement supérieur au prix arrive : acompte saisi deux fois, prix
  /// revu à la baisse après coup. L'afficher vaut mieux que le masquer.
  double? get tropPercu {
    final p = prix;
    if (p == null) return null;
    final excedent = verse - p;
    return excedent > 0 ? excedent : null;
  }

  /// Le dossier est réglé quand le prix est fixé et entièrement couvert.
  bool get solde => prix != null && verse >= prix!;

  /// Part réglée, entre 0 et 1. `null` si le prix n'est pas fixé ou vaut zéro.
  double? get progression {
    final p = prix;
    if (p == null || p <= 0) return null;
    final ratio = verse / p;
    return ratio.clamp(0.0, 1.0);
  }
}

/// Suivi du forfait de séances.
class Seances {
  /// Nombre de séances vendues. `null` si aucun forfait n'a été défini.
  final int? total;

  /// Séances déjà réalisées.
  final int effectuees;

  const Seances({required this.total, required this.effectuees});

  factory Seances.fromPatient(Map<String, dynamic>? data) {
    return Seances(
      total: asIntOrNull(data?['nombreSeances']),
      effectuees: asInt(data?['seancesEffectuees']),
    );
  }

  bool get sansForfait => total == null;

  /// Séances restantes, jamais négatif. `null` si aucun forfait.
  int? get restantes {
    final t = total;
    if (t == null) return null;
    final r = t - effectuees;
    return r > 0 ? r : 0;
  }

  /// Le forfait est consommé.
  bool get termine => total != null && effectuees >= total!;

  /// Dépassement du forfait, s'il y en a un. `null` sinon.
  int? get depassement {
    final t = total;
    if (t == null) return null;
    final excedent = effectuees - t;
    return excedent > 0 ? excedent : null;
  }

  /// Part réalisée, entre 0 et 1. `null` si aucun forfait ou forfait à zéro.
  double? get progression {
    final t = total;
    if (t == null || t <= 0) return null;
    return (effectuees / t).clamp(0.0, 1.0);
  }

  /// Libellé court pour l'affichage : « 3 / 10 » ou « 3 » sans forfait.
  String get libelle {
    final t = total;
    return t == null ? '$effectuees' : '$effectuees / $t';
  }
}

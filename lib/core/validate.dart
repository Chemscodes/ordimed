/// Validation des saisies.
///
/// Chaque fonction renvoie `null` quand la valeur est acceptable, ou un
/// message d'erreur en français prêt à afficher. C'est la signature attendue
/// par `TextFormField.validator`, donc ces fonctions se branchent directement.
///
/// Les messages disent **ce qui ne va pas et ce qu'on attend**, jamais
/// « champ invalide ».
library;

import 'coerce.dart';
import 'format.dart';

/// Bornes retenues pour l'âge. 130 laisse de la marge sur le record humain
/// tout en rejetant les erreurs de frappe évidentes.
const int ageMin = 0;
const int ageMax = 130;

/// Champ obligatoire.
String? required(String? value, {String champ = 'Ce champ'}) {
  if (asText(value).isEmpty) return '$champ est obligatoire';
  return null;
}

/// Nom ou prénom : obligatoire, deux caractères minimum.
String? nom(String? value, {String champ = 'Le nom'}) {
  final s = asText(value);
  if (s.isEmpty) return '$champ est obligatoire';
  if (s.length < 2) return '$champ doit faire au moins 2 caractères';
  if (s.length > 60) return '$champ est trop long (60 caractères maximum)';
  return null;
}

/// Âge en années. Facultatif par défaut.
String? age(String? value, {bool obligatoire = false}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? "L'âge est obligatoire" : null;

  final n = int.tryParse(s);
  if (n == null) return "L'âge doit être un nombre entier";
  if (n < ageMin || n > ageMax) return "L'âge doit être entre $ageMin et $ageMax ans";
  return null;
}

/// Téléphone algérien. Facultatif par défaut.
///
/// Accepte le mobile à 10 chiffres (`05`, `06`, `07`) et le fixe à 9 chiffres
/// commençant par `0`. L'indicatif international `+213` est toléré et
/// normalisé par [normalizePhone].
String? phone(String? value, {bool obligatoire = false}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? 'Le téléphone est obligatoire' : null;

  final d = digitsOnly(normalizePhone(s));
  if (d.length < 9) return 'Numéro trop court (9 chiffres minimum)';
  if (d.length > 10) return 'Numéro trop long (10 chiffres maximum)';
  if (!d.startsWith('0')) return 'Un numéro algérien commence par 0';

  if (d.length == 10) {
    final operateur = d.substring(0, 2);
    if (!['05', '06', '07'].contains(operateur)) {
      return 'Mobile invalide : doit commencer par 05, 06 ou 07';
    }
  }
  return null;
}

/// Ramène un numéro à sa forme nationale : `+213551686212` devient
/// `0551686212`. Sert avant validation et avant enregistrement.
String normalizePhone(String value) {
  var d = digitsOnly(value);
  if (d.startsWith('00213')) {
    d = d.substring(5);
  } else if (d.startsWith('213') && d.length > 9) {
    d = d.substring(3);
  }
  if (d.isNotEmpty && !d.startsWith('0')) d = '0$d';
  return d;
}

/// Adresse e-mail. Facultative par défaut.
String? email(String? value, {bool obligatoire = false}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? "L'e-mail est obligatoire" : null;

  // Volontairement permissif : une regex stricte rejette des adresses valides.
  // On attrape les fautes de frappe évidentes, pas les cas exotiques.
  final ok = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]{2,}$').hasMatch(s);
  if (!ok) return "Adresse e-mail invalide (exemple : nom@domaine.com)";
  return null;
}

/// Montant en dinars. Facultatif par défaut.
///
/// [max] borne la saisie — un versement de dix millions est presque toujours
/// une frappe en trop.
String? montant(
  String? value, {
  bool obligatoire = false,
  double min = 0,
  double max = 10000000,
  String champ = 'Le montant',
}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? '$champ est obligatoire' : null;

  final n = asDoubleOrNull(s);
  if (n == null) return '$champ doit être un nombre';
  if (n.isNaN || n.isInfinite) return '$champ est invalide';
  if (n < min) return '$champ ne peut pas être inférieur à ${min.toInt()} DA';
  if (n > max) return '$champ dépasse la limite autorisée';
  return null;
}

/// Nombre de séances d'un forfait.
String? seances(String? value, {bool obligatoire = false}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? 'Le nombre de séances est obligatoire' : null;

  final n = int.tryParse(s);
  if (n == null) return 'Le nombre de séances doit être un entier';
  if (n < 1) return 'Le forfait doit contenir au moins 1 séance';
  if (n > 500) return 'Nombre de séances trop élevé (500 maximum)';
  return null;
}

/// Mesure physiologique bornée — poids, taille, tour de taille.
String? mesure(
  String? value, {
  required String champ,
  required double min,
  required double max,
  required String unite,
  bool obligatoire = false,
}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? '$champ est obligatoire' : null;

  final n = asDoubleOrNull(s);
  if (n == null) return '$champ doit être un nombre';
  if (n < min || n > max) {
    return '$champ doit être entre ${_short(min)} et ${_short(max)} $unite';
  }
  return null;
}

/// Poids en kilogrammes.
String? poids(String? value, {bool obligatoire = false}) => mesure(
  value,
  champ: 'Le poids',
  min: 2,
  max: 500,
  unite: 'kg',
  obligatoire: obligatoire,
);

/// Taille en centimètres. Le message rappelle l'unité, parce que saisir 1,75
/// au lieu de 175 est l'erreur la plus fréquente.
String? taille(String? value, {bool obligatoire = false}) {
  final s = asText(value);
  if (s.isEmpty) return obligatoire ? 'La taille est obligatoire' : null;

  final n = asDoubleOrNull(s);
  if (n == null) return 'La taille doit être un nombre';
  if (n > 0 && n < 3) return 'La taille est attendue en centimètres (ex. 175)';
  if (n < 30 || n > 260) return 'La taille doit être entre 30 et 260 cm';
  return null;
}

/// Code PIN d'un profil : 4 à 6 chiffres.
String? pin(String? value) {
  final s = asText(value);
  if (s.isEmpty) return 'Le code PIN est obligatoire';
  if (!RegExp(r'^\d+$').hasMatch(s)) return 'Le code PIN ne contient que des chiffres';
  if (s.length < 4) return 'Le code PIN doit faire au moins 4 chiffres';
  if (s.length > 6) return 'Le code PIN doit faire au plus 6 chiffres';
  return null;
}

/// Mot de passe de compte cabinet.
String? password(String? value) {
  final s = value ?? '';
  if (s.isEmpty) return 'Le mot de passe est obligatoire';
  if (s.length < 6) return 'Le mot de passe doit faire au moins 6 caractères';
  return null;
}

/// Enchaîne plusieurs validateurs, renvoie la première erreur rencontrée.
String? Function(String?) all(List<String? Function(String?)> validators) {
  return (String? value) {
    for (final v in validators) {
      final erreur = v(value);
      if (erreur != null) return erreur;
    }
    return null;
  };
}

String _short(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

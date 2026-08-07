/// Conversions tolérantes depuis Firestore.
///
/// Pourquoi ce fichier existe : les documents d'Ordimed sont hétérogènes.
/// L'âge a été enregistré en **chaîne** (`'age': age.text.trim()`), les prix
/// tantôt en nombre tantôt en chaîne, les dates en `Timestamp`, en `DateTime`
/// ou en ISO 8601 selon l'endroit du code qui les a écrites.
///
/// Toute lecture passe donc par ces fonctions, qui acceptent les trois formes.
/// Les écritures, elles, utilisent désormais des types propres — mais les
/// anciens documents doivent continuer à s'afficher.
///
/// Ces fonctions remplacent douze helpers privés dupliqués dans sept fichiers.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Nombre décimal, ou `null` si la valeur est absente ou illisible.
///
/// Accepte la virgule comme séparateur décimal : `'12,5'` donne `12.5`.
double? asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  // Retire les espaces de milliers et normalise la virgule décimale.
  final cleaned = raw.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  return double.tryParse(cleaned);
}

/// Nombre décimal, `0` par défaut. Pour les totaux, où l'absence vaut zéro.
double asDouble(dynamic value) => asDoubleOrNull(value) ?? 0;

/// Nombre entier, ou `null` si la valeur est absente ou illisible.
///
/// Un décimal est tronqué : `'42.7'` donne `42`.
int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final d = asDoubleOrNull(value);
  return d?.toInt();
}

/// Nombre entier, `0` par défaut.
int asInt(dynamic value) => asIntOrNull(value) ?? 0;

/// Date, ou `null`. Accepte `Timestamp`, `DateTime` et ISO 8601.
DateTime? asDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) {
    // Millisecondes depuis l'epoch — écrites par certains anciens écrans.
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// Texte nettoyé, chaîne vide si absent. Jamais `null` : simplifie l'affichage.
String asText(dynamic value) {
  if (value == null) return '';
  return value.toString().trim();
}

/// Texte, ou `null` si vide. Pour distinguer « non renseigné » de « vide ».
String? asTextOrNull(dynamic value) {
  final s = asText(value);
  return s.isEmpty ? null : s;
}

/// Clé de journée `AAAA-MM-JJ`, utilisée par `daily_stats` et `purchases`.
String dayKeyOf(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

/// Date correspondant à une clé de journée, ou `null` si le format est invalide.
DateTime? dateFromDayKey(String dayKey) {
  final parts = dayKey.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Minuit du jour de [date].
DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

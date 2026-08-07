/// Mise en forme pour l'affichage.
///
/// Un seul endroit décide à quoi ressemble un montant, un téléphone ou une
/// date dans Ordimed. Sans ça, chaque écran réinvente son format et l'app
/// paraît bricolée.
library;

import 'coerce.dart';

/// Separateur de milliers : espace **insecable** (U+00A0).
///
/// Insecable pour qu'un montant ne se coupe jamais en fin de ligne, et
/// U+00A0 plutot qu'une espace fine parce qu'elle est rendue par toutes
/// les polices. Exportee pour que les tests s'y referent au lieu de
/// recopier un caractere invisible.
const String thousandsSeparator = '\u00A0';

/// Montant en dinars : `12 500 DA`, `1 250,50 DA`.
///
/// Les décimales n'apparaissent que si elles existent — un prix rond ne
/// s'affiche pas `12 500,00 DA`.
String money(dynamic value, {bool withSuffix = true}) {
  final n = asDoubleOrNull(value);
  if (n == null) return withSuffix ? '— DA' : '—';
  return '${_groupedNumber(n)}${withSuffix ? ' DA' : ''}';
}

/// Nombre avec séparateurs de milliers, décimales seulement si nécessaires.
String _groupedNumber(double value) {
  final negatif = value < 0;
  final abs = value.abs();
  final entier = abs.truncate();
  final reste = abs - entier;

  final chiffres = entier.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(thousandsSeparator);
    buffer.write(chiffres[i]);
  }

  var sortie = buffer.toString();
  if (reste > 0.0001) {
    // Deux décimales, sans zéro final inutile : 12,5 plutôt que 12,50.
    var dec = (reste * 100).round().toString().padLeft(2, '0');
    if (dec.endsWith('0')) dec = dec.substring(0, 1);
    sortie = '$sortie,$dec';
  }
  return negatif ? '-$sortie' : sortie;
}

/// Entier avec séparateurs de milliers : `1 250`.
String integer(dynamic value) {
  final n = asIntOrNull(value);
  if (n == null) return '—';
  return _groupedNumber(n.toDouble());
}

/// Téléphone algérien lisible : `0551 68 62 12`.
///
/// Le stockage reste brut (chiffres uniquement) ; seul l'affichage est groupé.
/// Un numéro qui ne correspond à aucun format connu est rendu tel quel plutôt
/// que déformé.
String phone(dynamic value) {
  final brut = digitsOnly(asText(value));
  if (brut.isEmpty) return '—';

  // Mobile national : 10 chiffres, 0 + opérateur (5/6/7) + 8 chiffres.
  if (brut.length == 10 && brut.startsWith('0')) {
    return '${brut.substring(0, 4)} ${brut.substring(4, 6)} '
        '${brut.substring(6, 8)} ${brut.substring(8, 10)}';
  }
  // Fixe national : 9 chiffres, 0 + indicatif de wilaya + 6 chiffres.
  if (brut.length == 9 && brut.startsWith('0')) {
    return '${brut.substring(0, 3)} ${brut.substring(3, 5)} '
        '${brut.substring(5, 7)} ${brut.substring(7, 9)}';
  }
  return asText(value);
}

/// Ne garde que les chiffres. Sert au stockage et à la comparaison.
String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Date courte : `05/08/2026`.
String date(dynamic value) {
  final d = asDateOrNull(value);
  if (d == null) return '—';
  final j = d.day.toString().padLeft(2, '0');
  final m = d.month.toString().padLeft(2, '0');
  return '$j/$m/${d.year}';
}

/// Date et heure : `05/08/2026 à 14:30`.
String dateTime(dynamic value) {
  final d = asDateOrNull(value);
  if (d == null) return '—';
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${date(d)} à $h:$min';
}

/// Ancienneté en langage courant : « aujourd'hui », « il y a 3 jours ».
String relativeDay(dynamic value, {DateTime? now}) {
  final d = asDateOrNull(value);
  if (d == null) return '—';
  final reference = startOfDay(now ?? DateTime.now());
  final jours = reference.difference(startOfDay(d)).inDays;

  if (jours == 0) return "aujourd'hui";
  if (jours == 1) return 'hier';
  if (jours == -1) return 'demain';
  if (jours > 1 && jours < 30) return 'il y a $jours jours';
  if (jours < -1 && jours > -30) return 'dans ${-jours} jours';
  return date(d);
}

/// Remplace les séparateurs techniques par des espaces : `perte_de_poids`
/// devient `perte de poids`. Les motifs et origines sont stockés en clé.
String humanize(dynamic value) {
  final s = asText(value);
  if (s.isEmpty) return '';
  return s.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
}

/// Première lettre en capitale, le reste inchangé.
String capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Initiales pour une pastille d'avatar : « Amina Belkacem » donne « AB ».
String initials(String nom, [String prenom = '']) {
  String first(String s) {
    final t = s.trim();
    return t.isEmpty ? '' : t[0].toUpperCase();
  }

  final a = first(nom);
  final b = first(prenom);
  final res = '$a$b';
  return res.isEmpty ? '?' : res;
}

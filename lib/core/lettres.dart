/// Montants écrits en toutes lettres.
///
/// Un reçu manuscrit algérien porte toujours la somme en lettres sous le
/// chiffre : c'est ce qui empêche d'ajouter un zéro après coup. Un reçu
/// imprimé qui ne la porte pas a l'air d'un brouillon.
library;

const _unites = [
  'zéro',
  'un',
  'deux',
  'trois',
  'quatre',
  'cinq',
  'six',
  'sept',
  'huit',
  'neuf',
  'dix',
  'onze',
  'douze',
  'treize',
  'quatorze',
  'quinze',
  'seize',
  'dix-sept',
  'dix-huit',
  'dix-neuf',
];

const _dizaines = [
  '',
  '',
  'vingt',
  'trente',
  'quarante',
  'cinquante',
  'soixante',
  'soixante',
  'quatre-vingt',
  'quatre-vingt',
];

/// Écrit un entier de 0 à 999 999 999 en lettres.
String _entierEnLettres(int n) {
  if (n < 20) return _unites[n];

  if (n < 100) {
    final d = n ~/ 10;
    final u = n % 10;

    // 70 et 90 se disent « soixante-dix » et « quatre-vingt-dix » : la
    // dizaine reste celle d'en dessous et l'unité monte au-delà de dix.
    if (d == 7 || d == 9) {
      final reste = _unites[10 + u];
      // « soixante et onze » en graphie traditionnelle. La réforme de 1990
      // autorise les traits d'union partout, mais un document comptable
      // gagne à s'écrire comme les documents comptables s'écrivent.
      final liaison = (d == 7 && u == 1) ? ' et ' : '-';
      return '${_dizaines[d]}$liaison$reste';
    }

    if (u == 0) {
      // « quatre-vingts » prend un s quand rien ne le suit.
      return d == 8 ? 'quatre-vingts' : _dizaines[d];
    }
    // 21, 31… prennent « et un ».
    if (u == 1 && d != 8) return '${_dizaines[d]} et un';
    return '${_dizaines[d]}-${_unites[u]}';
  }

  if (n < 1000) {
    final c = n ~/ 100;
    final reste = n % 100;
    // « cent » s'accorde seulement s'il termine le nombre.
    final tete = c == 1 ? 'cent' : '${_unites[c]} cent${reste == 0 ? 's' : ''}';
    return reste == 0 ? tete : '$tete ${_entierEnLettres(reste)}';
  }

  if (n < 1000000) {
    final milliers = n ~/ 1000;
    final reste = n % 1000;
    // « mille » est invariable.
    final tete = milliers == 1
        ? 'mille'
        : '${_entierEnLettres(milliers)} mille';
    return reste == 0 ? tete : '$tete ${_entierEnLettres(reste)}';
  }

  final millions = n ~/ 1000000;
  final reste = n % 1000000;
  final tete = millions == 1
      ? 'un million'
      : '${_entierEnLettres(millions)} millions';
  return reste == 0 ? tete : '$tete ${_entierEnLettres(reste)}';
}

/// Écrit un montant en dinars, centimes compris s'il y en a.
///
/// Renvoie une chaîne vide pour un montant négatif : un reçu ne constate
/// pas une dette, et écrire « moins deux mille dinars » en toutes lettres
/// sur une quittance n'aurait aucun sens juridique.
String montantEnLettres(num montant) {
  if (montant.isNaN || montant.isInfinite || montant < 0) return '';

  // Arrondi au centime avant découpage : 1999.999 doit donner deux mille
  // dinars, pas « mille neuf cent quatre-vingt-dix-neuf et 100 centimes ».
  final total = (montant * 100).round();
  final dinars = total ~/ 100;
  final centimes = total % 100;

  if (dinars > 999999999) return '';

  final tete = '${_entierEnLettres(dinars)} dinar${dinars > 1 ? 's' : ''}';
  if (centimes == 0) return tete;
  return '$tete et ${_entierEnLettres(centimes)} '
      'centime${centimes > 1 ? 's' : ''}';
}

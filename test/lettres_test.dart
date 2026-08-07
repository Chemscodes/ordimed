import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/lettres.dart';

void main() {
  group('Petits nombres', () {
    test('zero prend le singulier', () {
      // « zéro dinar » : en français zéro n'entraîne pas le pluriel.
      expect(montantEnLettres(0), 'zéro dinar');
    });
    test('un dinar reste au singulier', () {
      expect(montantEnLettres(1), 'un dinar');
    });
    test('deux dinars prennent le pluriel', () {
      expect(montantEnLettres(2), 'deux dinars');
    });
    test('les nombres jusqu a dix-neuf sont d un bloc', () {
      expect(montantEnLettres(17), 'dix-sept dinars');
    });
  });

  group('Les pieges du francais', () {
    test('21 prend « et un »', () {
      expect(montantEnLettres(21), 'vingt et un dinars');
    });
    test('22 prend un trait d union', () {
      expect(montantEnLettres(22), 'vingt-deux dinars');
    });
    test('70 se dit soixante-dix', () {
      expect(montantEnLettres(70), 'soixante-dix dinars');
    });
    test('71 se dit soixante et onze', () {
      expect(montantEnLettres(71), 'soixante et onze dinars');
    });
    test('80 prend un s', () {
      expect(montantEnLettres(80), 'quatre-vingts dinars');
    });
    test('81 ne prend pas de s ni de « et »', () {
      expect(montantEnLettres(81), 'quatre-vingt-un dinars');
    });
    test('90 se dit quatre-vingt-dix', () {
      expect(montantEnLettres(90), 'quatre-vingt-dix dinars');
    });
    test('99', () {
      expect(montantEnLettres(99), 'quatre-vingt-dix-neuf dinars');
    });
    test('cent est seul quand il vaut un', () {
      expect(montantEnLettres(100), 'cent dinars');
    });
    test('deux cents prend un s', () {
      expect(montantEnLettres(200), 'deux cents dinars');
    });
    test('deux cent un ne prend pas de s', () {
      expect(montantEnLettres(201), 'deux cent un dinars');
    });
    test('mille est invariable et sans « un »', () {
      expect(montantEnLettres(1000), 'mille dinars');
      expect(montantEnLettres(2000), 'deux mille dinars');
    });
  });

  group('Montants de cabinet', () {
    test('un tarif courant', () {
      expect(montantEnLettres(2000), 'deux mille dinars');
    });
    test('un montant compose', () {
      expect(
        montantEnLettres(3500),
        'trois mille cinq cents dinars',
      );
    });
    test('un montant a quatre chiffres irregulier', () {
      expect(
        montantEnLettres(1580),
        'mille cinq cent quatre-vingts dinars',
      );
    });
    test('un million', () {
      expect(montantEnLettres(1000000), 'un million dinars');
    });
  });

  group('Centimes', () {
    test('les centimes sont ecrits quand il y en a', () {
      expect(
        montantEnLettres(1500.5),
        'mille cinq cents dinars et cinquante centimes',
      );
    });
    test('un seul centime reste au singulier', () {
      expect(montantEnLettres(1.01), 'un dinar et un centime');
    });
    test('les centimes nuls ne sont pas ecrits', () {
      expect(montantEnLettres(1500.0), 'mille cinq cents dinars');
    });
    test('l arrondi se fait avant le decoupage', () {
      // 1999.999 doit donner deux mille dinars, pas « mille neuf cent
      // quatre-vingt-dix-neuf et 100 centimes ».
      expect(montantEnLettres(1999.999), 'deux mille dinars');
    });
    test('un arrondi au centime superieur', () {
      expect(montantEnLettres(0.126), 'zéro dinar et treize centimes');
    });
  });

  group('Cas refuses', () {
    test('un montant negatif ne produit rien', () {
      // Un recu ne constate pas une dette.
      expect(montantEnLettres(-100), '');
    });
    test('un montant hors d echelle ne produit rien', () {
      expect(montantEnLettres(1000000000), '');
    });
    test('les valeurs non finies ne font pas planter', () {
      expect(montantEnLettres(double.nan), '');
      expect(montantEnLettres(double.infinity), '');
    });
  });

  group('Robustesse', () {
    test('aucun montant courant ne produit de chaine vide', () {
      for (var i = 0; i <= 5000; i += 50) {
        expect(montantEnLettres(i), isNotEmpty, reason: '$i');
      }
    });

    test('aucun resultat ne contient de double espace ni de tiret orphelin', () {
      for (var i = 0; i <= 2000; i++) {
        final s = montantEnLettres(i);
        expect(s.contains('  '), isFalse, reason: '$i -> $s');
        expect(s.contains('--'), isFalse, reason: '$i -> $s');
        expect(s.trim(), s, reason: '$i -> $s');
      }
    });
  });
}

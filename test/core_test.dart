import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/clinical.dart';
import 'package:ordimed/core/coerce.dart';
import 'package:ordimed/core/format.dart';
import 'package:ordimed/core/validate.dart' as v;

void main() {
  group('Conversions tolérantes', () {
    test('accepte les nombres et les chaînes', () {
      expect(asDoubleOrNull(12.5), 12.5);
      expect(asDoubleOrNull(12), 12.0);
      expect(asDoubleOrNull('12.5'), 12.5);
      // L'app enregistre parfois la virgule décimale.
      expect(asDoubleOrNull('12,5'), 12.5);
      // Et parfois des espaces de milliers venus d'un copier-coller.
      expect(asDoubleOrNull('12 500'), 12500);
    });

    test('renvoie null plutôt que zéro sur une valeur absente', () {
      // La distinction compte : « pas de prix fixé » n'est pas « prix zéro ».
      expect(asDoubleOrNull(null), isNull);
      expect(asDoubleOrNull(''), isNull);
      expect(asDoubleOrNull('   '), isNull);
      expect(asDoubleOrNull('abc'), isNull);
      expect(asDouble(null), 0);
    });

    test("l'âge stocké en chaîne reste lisible", () {
      // Régression : add_patient_form enregistre 'age' en String.
      expect(asIntOrNull('42'), 42);
      expect(asIntOrNull(42), 42);
      expect(asIntOrNull('42.7'), 42);
      expect(asIntOrNull(''), isNull);
    });

    test('accepte les trois formes de date utilisées dans la base', () {
      final d = DateTime(2026, 8, 5, 14, 30);
      expect(asDateOrNull(Timestamp.fromDate(d)), d);
      expect(asDateOrNull(d), d);
      expect(asDateOrNull(d.toIso8601String()), d);
      expect(asDateOrNull(null), isNull);
      expect(asDateOrNull('pas une date'), isNull);
    });

    test('clé de journée : aller-retour', () {
      expect(dayKeyOf(DateTime(2026, 8, 5)), '2026-08-05');
      expect(dayKeyOf(DateTime(2026, 12, 25)), '2026-12-25');
      expect(dateFromDayKey('2026-08-05'), DateTime(2026, 8, 5));
      expect(dateFromDayKey('nawak'), isNull);
      expect(dateFromDayKey('2026-13-05'), isNull);
    });
  });

  group('IMC', () {
    test('calcule et classe correctement', () {
      final imc = Bmi.compute(poidsKg: 70, tailleCm: 175);
      expect(imc, isNotNull);
      expect(imc!.formatted, '22.9');
      expect(imc.category, BmiCategory.normal);
    });

    test('couvre les catégories OMS', () {
      expect(Bmi.compute(poidsKg: 45, tailleCm: 175)!.category,
          BmiCategory.underweight);
      expect(Bmi.compute(poidsKg: 80, tailleCm: 175)!.category,
          BmiCategory.overweight);
      expect(Bmi.compute(poidsKg: 100, tailleCm: 175)!.category,
          BmiCategory.obese1);
      expect(Bmi.compute(poidsKg: 130, tailleCm: 175)!.category,
          BmiCategory.obese3);
    });

    test('refuse une taille saisie en mètres', () {
      // L'erreur de saisie la plus fréquente : 1,75 au lieu de 175.
      // Mieux vaut ne rien afficher qu'un IMC de 22857.
      expect(Bmi.compute(poidsKg: 70, tailleCm: 1.75), isNull);
    });

    test('refuse les mesures absentes ou aberrantes', () {
      expect(Bmi.compute(poidsKg: null, tailleCm: 175), isNull);
      expect(Bmi.compute(poidsKg: 70, tailleCm: null), isNull);
      expect(Bmi.compute(poidsKg: 0, tailleCm: 175), isNull);
      expect(Bmi.compute(poidsKg: 700, tailleCm: 175), isNull);
    });
  });

  group('Règlement', () {
    test('distingue « pas de prix » de « prix zéro »', () {
      final sansPrix = Reglement.fromPatient({'totalVersements': 500});
      expect(sansPrix.sansPrix, isTrue);
      expect(sansPrix.reste, isNull);
      expect(sansPrix.solde, isFalse);
    });

    test('calcule le reste à payer', () {
      final r = Reglement.fromPatient({'prix': 10000, 'totalVersements': 3500});
      expect(r.reste, 6500);
      expect(r.solde, isFalse);
      expect(r.progression, closeTo(0.35, 0.001));
    });

    test('le reste ne devient jamais négatif', () {
      final r = Reglement.fromPatient({'prix': 5000, 'totalVersements': 7000});
      expect(r.reste, 0);
      expect(r.tropPercu, 2000);
      expect(r.solde, isTrue);
      expect(r.progression, 1.0);
    });

    test('tolère un prix enregistré en chaîne', () {
      final r = Reglement.fromPatient({'prix': '10000', 'totalVersements': '2500'});
      expect(r.reste, 7500);
    });
  });

  group('Séances', () {
    test('calcule les restantes', () {
      final s = Seances.fromPatient({'nombreSeances': 10, 'seancesEffectuees': 3});
      expect(s.restantes, 7);
      expect(s.termine, isFalse);
      expect(s.libelle, '3 / 10');
    });

    test('signale le dépassement sans passer en négatif', () {
      final s = Seances.fromPatient({'nombreSeances': 5, 'seancesEffectuees': 8});
      expect(s.restantes, 0);
      expect(s.depassement, 3);
      expect(s.termine, isTrue);
    });

    test('sans forfait, on affiche juste le compte', () {
      final s = Seances.fromPatient({'seancesEffectuees': 4});
      expect(s.sansForfait, isTrue);
      expect(s.restantes, isNull);
      expect(s.libelle, '4');
    });
  });

  group('Formatage', () {
    test('montants avec séparateurs, décimales seulement si utiles', () {
      // On référence la constante plutôt que de recopier une espace
      // insécable : à l'œil elle est identique à une espace normale, et le
      // test échouerait pour une raison invisible en relecture.
      const s = thousandsSeparator;
      expect(money(12500), '12${s}500 DA');
      expect(money(1250.5), '1${s}250,5 DA');
      expect(money(999), '999 DA');
      expect(money(1000000), '1${s}000${s}000 DA');
      expect(money(null), '— DA');
      expect(money(12500, withSuffix: false), '12${s}500');
    });

    test('téléphone algérien groupé', () {
      expect(phone('0551686212'), '0551 68 62 12');
      expect(phone('021234567'), '021 23 45 67');
      // Un format inconnu est rendu tel quel plutôt que déformé.
      expect(phone('12345'), '12345');
      expect(phone(null), '—');
    });

    test('dates', () {
      expect(date(DateTime(2026, 8, 5)), '05/08/2026');
      expect(dateTime(DateTime(2026, 8, 5, 14, 30)), '05/08/2026 à 14:30');
      expect(date(null), '—');
    });

    test('ancienneté en langage courant', () {
      final now = DateTime(2026, 8, 5, 12);
      expect(relativeDay(DateTime(2026, 8, 5, 9), now: now), "aujourd'hui");
      expect(relativeDay(DateTime(2026, 8, 4), now: now), 'hier');
      expect(relativeDay(DateTime(2026, 8, 2), now: now), 'il y a 3 jours');
    });

    test('libellés lisibles et initiales', () {
      expect(humanize('famille_amis_bouche_a_oreille'),
          'famille amis bouche a oreille');
      expect(capitalize('perte de poids'), 'Perte de poids');
      expect(initials('Belkacem', 'Amina'), 'BA');
      expect(initials('', ''), '?');
    });
  });

  group('Validation', () {
    test('nom', () {
      expect(v.nom('Belkacem'), isNull);
      expect(v.nom(''), isNotNull);
      expect(v.nom('A'), isNotNull);
    });

    test('âge borné', () {
      expect(v.age('42'), isNull);
      expect(v.age(''), isNull, reason: 'facultatif par défaut');
      expect(v.age('', obligatoire: true), isNotNull);
      expect(v.age('abc'), isNotNull);
      expect(v.age('200'), isNotNull);
      expect(v.age('-5'), isNotNull);
    });

    test('téléphone algérien', () {
      expect(v.phone('0551686212'), isNull);
      expect(v.phone('0551 68 62 12'), isNull, reason: 'espaces tolérés');
      expect(v.phone('+213551686212'), isNull, reason: 'indicatif normalisé');
      expect(v.phone('021234567'), isNull, reason: 'fixe à 9 chiffres');
      expect(v.phone('0451686212'), isNotNull, reason: 'opérateur inexistant');
      expect(v.phone('123'), isNotNull);
      expect(v.phone(''), isNull, reason: 'facultatif par défaut');
    });

    test('normalisation du téléphone', () {
      expect(v.normalizePhone('+213551686212'), '0551686212');
      expect(v.normalizePhone('00213551686212'), '0551686212');
      expect(v.normalizePhone('0551 68 62 12'), '0551686212');
      expect(v.normalizePhone('551686212'), '0551686212');
    });

    test('e-mail', () {
      expect(v.email('nom@domaine.com'), isNull);
      expect(v.email('nom@domaine'), isNotNull);
      expect(v.email('nom.domaine.com'), isNotNull);
      expect(v.email(''), isNull, reason: 'facultatif par défaut');
    });

    test('montant', () {
      expect(v.montant('12500'), isNull);
      expect(v.montant('12,5'), isNull);
      expect(v.montant('-100'), isNotNull);
      expect(v.montant('abc'), isNotNull);
      expect(v.montant('99999999'), isNotNull, reason: 'au-delà du plafond');
    });

    test('taille : rappelle les centimètres', () {
      expect(v.taille('175'), isNull);
      final erreur = v.taille('1.75');
      expect(erreur, isNotNull);
      expect(erreur, contains('centimètres'));
    });

    test('code PIN', () {
      expect(v.pin('1234'), isNull);
      expect(v.pin('123'), isNotNull);
      expect(v.pin('12a4'), isNotNull);
      expect(v.pin('1234567'), isNotNull);
    });

    test('enchaînement de validateurs', () {
      final check = v.all([v.required, v.age]);
      expect(check('42'), isNull);
      expect(check(''), contains('obligatoire'));
      expect(check('abc'), contains('nombre'));
    });
  });
}

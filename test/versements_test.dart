import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/versements.dart';

void main() {
  Map<String, dynamic> v(double montant, DateTime? date) => {
    'montant': montant,
    if (date != null) 'createdAt': date,
  };

  group('Bornage du tableau', () {
    test('un tableau vide accueille le premier versement', () {
      final r = versementsBornes(null, v(2000, DateTime(2026, 8, 1)));
      expect(r, hasLength(1));
      expect(r.first['montant'], 2000);
    });

    test('les versements s accumulent tant qu on est sous la limite', () {
      var liste = <Map<String, dynamic>>[];
      for (var i = 1; i <= 10; i++) {
        liste = versementsBornes(liste, v(100.0 * i, DateTime(2026, 8, i)));
      }
      expect(liste, hasLength(10));
    });

    test('au-dela de la limite, le tableau cesse de grossir', () {
      // C'est tout l'objet : un document Firestore plafonne a 1 Mo et
      // l'echec d'ecriture serait silencieux.
      var liste = <Map<String, dynamic>>[];
      for (var i = 1; i <= 200; i++) {
        liste = versementsBornes(
          liste,
          v(100.0 * i, DateTime(2026, 1, 1).add(Duration(days: i))),
          maximum: 50,
        );
      }
      expect(liste, hasLength(50));
    });

    test('ce sont les plus recents qui restent', () {
      var liste = <Map<String, dynamic>>[];
      for (var i = 1; i <= 60; i++) {
        liste = versementsBornes(
          liste,
          v(i.toDouble(), DateTime(2026, 1, 1).add(Duration(days: i))),
          maximum: 5,
        );
      }
      final montants = liste.map((e) => e['montant']).toList();
      expect(montants, [60, 59, 58, 57, 56]);
    });

    test('le resultat est trie du plus recent au plus ancien', () {
      final liste = versementsBornes([
        v(100, DateTime(2026, 8, 1)),
        v(300, DateTime(2026, 8, 3)),
      ], v(200, DateTime(2026, 8, 2)));
      expect(liste.map((e) => e['montant']).toList(), [300, 200, 100]);
    });

    test('une entree sans date passe en dernier sans tout casser', () {
      final liste = versementsBornes([
        v(100, null),
        v(300, DateTime(2026, 8, 3)),
      ], v(200, DateTime(2026, 8, 2)));
      expect(liste.last['montant'], 100);
    });

    test('des donnees inattendues ne font pas planter', () {
      expect(versementsBornes('pas une liste', v(50, null)), hasLength(1));
      expect(
        versementsBornes([1, 'deux', null], v(50, null)),
        hasLength(1),
      );
    });

    test('les champs des anciennes entrees sont preserves', () {
      final liste = versementsBornes([
        {'montant': 100, 'dayKey': '2026-08-01', 'auteurProfileId': 'a1'},
      ], v(200, DateTime(2026, 8, 2)));
      final ancienne = liste.firstWhere((e) => e['montant'] == 100);
      expect(ancienne['dayKey'], '2026-08-01');
      expect(ancienne['auteurProfileId'], 'a1');
    });
  });

  group('Fusion tableau et sous-collection', () {
    test('un versement present des deux cotes n est compte qu une fois', () {
      // Pendant la transition les deux coexistent : le compter deux fois
      // gonflerait le total affiche au patient.
      final date = DateTime(2026, 8, 1, 10, 30);
      final fusion = fusionnerVersements(
        sousCollection: [Versement(montant: 2000, date: date, id: 'x1')],
        tableauHerite: [v(2000, date)],
      );
      expect(fusion, hasLength(1));
      expect(totalDe(fusion), 2000);
    });

    test('deux versements du meme montant a des dates differentes comptent double', () {
      final fusion = fusionnerVersements(
        sousCollection: [
          Versement(montant: 2000, date: DateTime(2026, 8, 1), id: 'x1'),
        ],
        tableauHerite: [v(2000, DateTime(2026, 8, 2))],
      );
      expect(fusion, hasLength(2));
      expect(totalDe(fusion), 4000);
    });

    test('les versements herites seuls sont conserves', () {
      // Tout l'historique d'avant la sous-collection vit dans le tableau.
      final fusion = fusionnerVersements(
        sousCollection: const [],
        tableauHerite: [
          v(1000, DateTime(2026, 7, 1)),
          v(500, DateTime(2026, 7, 15)),
        ],
      );
      expect(fusion, hasLength(2));
      expect(totalDe(fusion), 1500);
    });

    test('un versement herite se reconnait a son identifiant vide', () {
      final fusion = fusionnerVersements(
        sousCollection: [
          Versement(montant: 100, date: DateTime(2026, 8, 2), id: 'x1'),
        ],
        tableauHerite: [v(200, DateTime(2026, 8, 1))],
      );
      expect(fusion.firstWhere((x) => x.montant == 200).estHerite, isTrue);
      expect(fusion.firstWhere((x) => x.montant == 100).estHerite, isFalse);
    });

    test('la fusion est triee du plus recent au plus ancien', () {
      final fusion = fusionnerVersements(
        sousCollection: [
          Versement(montant: 300, date: DateTime(2026, 8, 3), id: 'x'),
        ],
        tableauHerite: [
          v(100, DateTime(2026, 8, 1)),
          v(200, DateTime(2026, 8, 2)),
        ],
      );
      expect(fusion.map((e) => e.montant).toList(), [300, 200, 100]);
    });

    test('un tableau herite absent ou invalide est ignore', () {
      final sous = [
        Versement(montant: 100, date: DateTime(2026, 8, 1), id: 'x'),
      ];
      expect(
        fusionnerVersements(sousCollection: sous, tableauHerite: null),
        hasLength(1),
      );
      expect(
        fusionnerVersements(sousCollection: sous, tableauHerite: 'nimporte'),
        hasLength(1),
      );
    });

    test('tout vide donne un total nul', () {
      final fusion = fusionnerVersements(
        sousCollection: const [],
        tableauHerite: null,
      );
      expect(fusion, isEmpty);
      expect(totalDe(fusion), 0);
    });
  });

  group('Relecture d un versement', () {
    test('les montants en texte sont convertis', () {
      final x = Versement.fromMap({'montant': '2 000,5'});
      expect(x.montant, 2000.5);
    });

    test('le champ date sert de repli a createdAt', () {
      final x = Versement.fromMap({
        'montant': 100,
        'date': DateTime(2026, 8, 1),
      });
      expect(x.date, DateTime(2026, 8, 1));
    });

    test('un versement sans montant vaut zero plutot que de planter', () {
      expect(Versement.fromMap({}).montant, 0);
    });
  });
}

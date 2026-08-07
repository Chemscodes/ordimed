import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/creneaux.dart';
import 'package:ordimed/core/parcours.dart';

void main() {
  // Lundi 10 aout 2026.
  final lundi = DateTime(2026, 8, 10);
  final vendredi = DateTime(2026, 8, 14);

  Creneau a(int h, int m, [int duree = 20]) =>
      Creneau(debut: DateTime(2026, 8, 10, h, m), duree: duree);

  Occupation occupe(
    String id,
    int h,
    int m, {
    int duree = 20,
    EtapeParcours etape = EtapeParcours.planifie,
  }) => Occupation(
    rdvId: id,
    patient: 'Patient $id',
    creneau: a(h, m, duree),
    etape: etape,
  );

  group('Chevauchement', () {
    test('deux creneaux identiques se chevauchent', () {
      expect(a(10, 0).chevauche(a(10, 0)), isTrue);
    });

    test('des creneaux qui se suivent ne se chevauchent pas', () {
      // 10h00-10h20 puis 10h20-10h40 : les bornes ne comptent pas, sinon
      // aucune journee pleine ne serait possible.
      expect(a(10, 0).chevauche(a(10, 20)), isFalse);
      expect(a(10, 20).chevauche(a(10, 0)), isFalse);
    });

    test('un chevauchement partiel est detecte dans les deux sens', () {
      expect(a(10, 0).chevauche(a(10, 10)), isTrue);
      expect(a(10, 10).chevauche(a(10, 0)), isTrue);
    });

    test('un long rendez-vous en avale plusieurs courts', () {
      final long = a(10, 0, 60);
      expect(long.chevauche(a(10, 20)), isTrue);
      expect(long.chevauche(a(10, 40)), isTrue);
      expect(long.chevauche(a(11, 0)), isFalse);
    });

    test('des creneaux eloignes sont independants', () {
      expect(a(9, 0).chevauche(a(15, 0)), isFalse);
    });
  });

  group('Detection de conflit', () {
    test('le conflit nomme le rendez-vous qui bloque', () {
      final conflit = conflitPour(a(10, 10), [occupe('r1', 10, 0)]);
      expect(conflit, isNotNull);
      expect(conflit!.rdvId, 'r1');
    });

    test('un creneau libre ne renvoie aucun conflit', () {
      expect(conflitPour(a(14, 0), [occupe('r1', 10, 0)]), isNull);
    });

    test('un rendez-vous annule libere son creneau', () {
      // Sinon une annulation laisse un trou inutilisable et l'assistant
      // contourne l'outil.
      final annule = occupe('r1', 10, 0, etape: EtapeParcours.annule);
      expect(conflitPour(a(10, 0), [annule]), isNull);
    });

    test('un patient absent libere son creneau', () {
      final absent = occupe('r1', 10, 0, etape: EtapeParcours.absent);
      expect(conflitPour(a(10, 0), [absent]), isNull);
    });

    test('un rendez-vous honore bloque toujours son creneau', () {
      // Il a bien eu lieu : reproposer l'heure creerait un doublon dans
      // l'historique de la journee.
      final honore = occupe('r1', 10, 0, etape: EtapeParcours.honore);
      expect(conflitPour(a(10, 0), [honore]), isNotNull);
    });

    test('un rendez-vous deplace ne se detecte pas lui-meme', () {
      final existant = [occupe('r1', 10, 0)];
      expect(conflitPour(a(10, 0), existant, ignorer: 'r1'), isNull);
      expect(conflitPour(a(10, 0), existant, ignorer: 'autre'), isNotNull);
    });

    test('aucune occupation, aucun conflit', () {
      expect(conflitPour(a(10, 0), const []), isNull);
    });
  });

  group('Etat d un creneau', () {
    final maintenant = DateTime(2026, 8, 10, 11, 0);

    test('un creneau depasse est passe', () {
      expect(
        etatDe(a(9, 0), const [], maintenant: maintenant),
        EtatCreneau.passe,
      );
    });

    test('le passe prime sur l occupation', () {
      // Un creneau de ce matin deja pris reste avant tout un creneau qu'on
      // ne peut plus proposer : dire « occupe » laisserait croire qu'il se
      // libererait en cas d annulation.
      expect(
        etatDe(a(9, 0), [occupe('r1', 9, 0)], maintenant: maintenant),
        EtatCreneau.passe,
      );
    });

    test('un creneau a venir et pris est occupe', () {
      expect(
        etatDe(a(15, 0), [occupe('r1', 15, 0)], maintenant: maintenant),
        EtatCreneau.occupe,
      );
    });

    test('un creneau a venir et libre est libre', () {
      expect(
        etatDe(a(15, 0), const [], maintenant: maintenant),
        EtatCreneau.libre,
      );
    });
  });

  group('Decoupage de la journee', () {
    const horaires = HorairesCabinet();

    test('la journee commence a l ouverture et finit avant la fermeture', () {
      final c = horaires.creneauxDuJour(lundi);
      expect(c.first.debut.hour, 8);
      expect(c.first.debut.minute, 0);
      expect(c.last.fin.hour, lessThanOrEqualTo(17));
      // Aucun creneau ne doit deborder l'horaire de fermeture.
      for (final x in c) {
        expect(
          x.fin.isAfter(DateTime(2026, 8, 10, 17, 0)),
          isFalse,
          reason: x.plage,
        );
      }
    });

    test('la pause dejeuner ne produit aucun creneau', () {
      final c = horaires.creneauxDuJour(lundi);
      final pendant = c.where(
        (x) => x.debut.hour == 12 || (x.debut.hour == 13 && x.debut.minute == 0),
      );
      expect(pendant.where((x) => x.debut.hour == 12), isEmpty);
      // 13h00 est la reprise : il doit exister.
      expect(c.any((x) => x.debut.hour == 13 && x.debut.minute == 0), isTrue);
    });

    test('un creneau qui mordrait sur la pause est exclu', () {
      // Consultation d'une heure : celle de 11h30 finirait a 12h30.
      const longues = HorairesCabinet(duree: 30);
      final c = longues.creneauxDuJour(lundi, dureeCreneau: 60);
      expect(
        c.any((x) => x.debut.hour == 11 && x.debut.minute == 30),
        isFalse,
      );
    });

    test('les creneaux ne se chevauchent jamais entre eux', () {
      final c = horaires.creneauxDuJour(lundi);
      for (var i = 0; i + 1 < c.length; i++) {
        expect(c[i].chevauche(c[i + 1]), isFalse, reason: c[i].plage);
      }
    });

    test('le vendredi est ferme par defaut', () {
      // Semaine algerienne : le repos est le vendredi, pas le dimanche.
      expect(horaires.estOuvertLe(vendredi), isFalse);
      expect(horaires.creneauxDuJour(vendredi), isEmpty);
      expect(horaires.estOuvertLe(DateTime(2026, 8, 9)), isTrue); // dimanche
    });

    test('une duree plus longue produit moins de creneaux', () {
      final courts = const HorairesCabinet(duree: 15).creneauxDuJour(lundi);
      final longs = const HorairesCabinet(duree: 45).creneauxDuJour(lundi);
      expect(courts.length, greaterThan(longs.length));
    });

    test('sans pause, la journee est continue', () {
      const sansPause = HorairesCabinet(pauseDebut: null, pauseFin: null);
      final c = sansPause.creneauxDuJour(lundi);
      expect(c.any((x) => x.debut.hour == 12), isTrue);
    });
  });

  group('Lecture des reglages', () {
    test('des reglages absents donnent les valeurs par defaut', () {
      final h = HorairesCabinet.fromMap(null);
      expect(h.ouverture, 8 * 60);
      expect(h.duree, 20);
    });

    test('une fermeture avant l ouverture revient au defaut', () {
      // Sinon la journee ne produit aucun creneau et personne ne comprend
      // pourquoi l'agenda est vide.
      final h = HorairesCabinet.fromMap({'ouverture': 600, 'fermeture': 300});
      expect(h.fermeture, greaterThan(h.ouverture));
      expect(h.creneauxDuJour(lundi), isNotEmpty);
    });

    test('une duree absurde revient au defaut', () {
      expect(HorairesCabinet.fromMap({'duree': 0}).duree, 20);
      expect(HorairesCabinet.fromMap({'duree': -5}).duree, 20);
    });

    test('des jours invalides sont ignores', () {
      final h = HorairesCabinet.fromMap({
        'joursOuvres': [1, 2, 99, 0, -3],
      });
      expect(h.joursOuvres, {1, 2});
    });

    test('une liste de jours vide revient au defaut', () {
      final h = HorairesCabinet.fromMap({'joursOuvres': <int>[]});
      expect(h.joursOuvres, isNotEmpty);
    });

    test('les reglages survivent a un aller-retour', () {
      const origine = HorairesCabinet(
        ouverture: 9 * 60,
        fermeture: 18 * 60,
        pauseDebut: null,
        pauseFin: null,
        duree: 30,
        joursOuvres: {1, 3, 5},
      );
      final revenu = HorairesCabinet.fromMap(origine.toMap());
      expect(revenu.ouverture, origine.ouverture);
      expect(revenu.fermeture, origine.fermeture);
      expect(revenu.duree, origine.duree);
      expect(revenu.joursOuvres, origine.joursOuvres);
      expect(revenu.pauseDebut, isNull);
    });

    test('l heure est formatee sur deux chiffres', () {
      expect(HorairesCabinet.formatHeure(480), '08:00');
      expect(HorairesCabinet.formatHeure(605), '10:05');
      expect(HorairesCabinet.formatHeure(0), '00:00');
    });
  });

  group('Relecture des rendez-vous', () {
    test('un rendez-vous sans date ne prend aucun creneau', () {
      // Le supposer a minuit fabriquerait un conflit imaginaire.
      expect(Occupation.fromRendezVous('r1', {'patientNom': 'Amina'}), isNull);
    });

    test('la duree du document prime sur le defaut', () {
      final o = Occupation.fromRendezVous('r1', {
        'datetime': DateTime(2026, 8, 10, 10, 0),
        'duree': 45,
      }, dureeParDefaut: 20);
      expect(o!.creneau.duree, 45);
    });

    test('un rendez-vous sans duree prend celle du cabinet', () {
      final o = Occupation.fromRendezVous('r1', {
        'datetime': DateTime(2026, 8, 10, 10, 0),
      }, dureeParDefaut: 30);
      expect(o!.creneau.duree, 30);
    });

    test('le nom du patient est reconstitue', () {
      final o = Occupation.fromRendezVous('r1', {
        'datetime': DateTime(2026, 8, 10, 10, 0),
        'patientNom': 'Benali',
        'patientPrenom': 'Amina',
      });
      expect(o!.patient, 'Benali Amina');
    });

    test('un rendez-vous anonyme reste affichable', () {
      final o = Occupation.fromRendezVous('r1', {
        'datetime': DateTime(2026, 8, 10, 10, 0),
      });
      expect(o!.patient, 'Patient');
    });
  });
}

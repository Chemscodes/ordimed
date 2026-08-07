import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/parcours.dart';
import 'package:ordimed/widgets/historique_seances.dart';

void main() {
  group('Lecture des documents existants', () {
    // Le cabinet tourne deja. Le nouveau vocabulaire ne doit pas rendre
    // illisible ce qui est deja en base : c'est le risque principal de ce
    // changement, donc ce que ces tests couvrent en premier.

    test('une entree de file sans etape est relue par son ancien statut', () {
      expect(
        EtapeParcours.fromWaiting({'status': 'waiting'}),
        EtapeParcours.arrive,
      );
      expect(
        EtapeParcours.fromWaiting({'status': 'in_consultation'}),
        EtapeParcours.enCours,
      );
      expect(
        EtapeParcours.fromWaiting({'status': 'done'}),
        EtapeParcours.honore,
      );
    });

    test('les deux orthographes de cancelled sont reconnues', () {
      expect(
        EtapeParcours.fromWaiting({'status': 'cancelled'}),
        EtapeParcours.annule,
      );
      expect(
        EtapeParcours.fromWaiting({'status': 'canceled'}),
        EtapeParcours.annule,
      );
    });

    test('closedAt ferme l entree meme sans statut', () {
      expect(
        EtapeParcours.fromWaiting({'closedAt': DateTime(2026, 8, 8)}),
        EtapeParcours.honore,
      );
    });

    test('inConsultationAt suffit a deduire la consultation', () {
      expect(
        EtapeParcours.fromWaiting({'inConsultationAt': DateTime(2026, 8, 8)}),
        EtapeParcours.enCours,
      );
    });

    test('etape prime sur l ancien statut quand les deux sont presents', () {
      // Les deux champs sont ecrits ensemble pendant la transition. Si un
      // jour ils divergent, c'est le nouveau qui fait foi.
      expect(
        EtapeParcours.fromWaiting({'etape': 'absent', 'status': 'waiting'}),
        EtapeParcours.absent,
      );
    });

    test('un rendez-vous sans etape est planifie', () {
      expect(
        EtapeParcours.fromRendezVous({'patientNom': 'Amina'}),
        EtapeParcours.planifie,
      );
    });

    test('un code inconnu ne fait pas planter la lecture', () {
      expect(EtapeParcours.fromCode('n_importe_quoi'), isNull);
      expect(EtapeParcours.fromCode(null), isNull);
      expect(
        EtapeParcours.fromRendezVous({'etape': 'n_importe_quoi'}),
        EtapeParcours.planifie,
      );
    });

    test('la casse et les espaces ne cassent pas la lecture', () {
      expect(EtapeParcours.fromCode('  HONORE '), EtapeParcours.honore);
    });
  });

  group('Coherence du parcours', () {
    test('les codes sont uniques', () {
      final codes = EtapeParcours.values.map((e) => e.code).toSet();
      expect(codes.length, EtapeParcours.values.length);
    });

    test('aucun code ne porte d accent ni d espace', () {
      // Ces valeurs partent dans Firestore et reviennent : elles doivent
      // survivre a un aller-retour sans encodage exotique.
      for (final e in EtapeParcours.values) {
        expect(e.code, matches(RegExp(r'^[a-z_]+$')), reason: e.name);
      }
    });

    test('une etape ouverte a toujours une suite', () {
      for (final e in EtapeParcours.values.where((e) => e.estOuverte)) {
        expect(e.suivantes, isNotEmpty, reason: e.name);
        expect(e.suivante, isNotNull, reason: e.name);
      }
    });

    test('une etape close est un cul-de-sac', () {
      for (final e in EtapeParcours.values.where((e) => e.estClose)) {
        expect(e.suivantes, isEmpty, reason: e.name);
        expect(e.suivante, isNull, reason: e.name);
      }
    });

    test('ouverte et close sont exclusives', () {
      for (final e in EtapeParcours.values) {
        expect(e.estOuverte, isNot(e.estClose), reason: e.name);
      }
    });

    test('le chemin normal mene de planifie a honore', () {
      var e = EtapeParcours.planifie;
      final visitees = <EtapeParcours>[e];
      // Borne haute : si une transition boucle, le test s'arrete au lieu
      // de tourner indefiniment.
      for (var i = 0; i < 10 && e.suivante != null; i++) {
        e = e.suivante!;
        visitees.add(e);
      }
      expect(e, EtapeParcours.honore);
      expect(visitees, contains(EtapeParcours.arrive));
      expect(visitees, contains(EtapeParcours.enCours));
    });

    test('on ne revient pas en arriere', () {
      for (final e in EtapeParcours.values) {
        for (final s in e.suivantes) {
          expect(
            s.ordre,
            greaterThan(e.ordre),
            reason: '${e.name} -> ${s.name}',
          );
        }
      }
    });

    test('un patient present est ni planifie ni termine', () {
      expect(EtapeParcours.arrive.estPresent, isTrue);
      expect(EtapeParcours.enCours.estPresent, isTrue);
      expect(EtapeParcours.planifie.estPresent, isFalse);
      expect(EtapeParcours.honore.estPresent, isFalse);
    });

    test('absent et annule sont les seules issues manquees', () {
      final manquees = EtapeParcours.values.where((e) => e.estManquee);
      expect(manquees, containsAll([EtapeParcours.absent, EtapeParcours.annule]));
      expect(manquees.length, 2);
      expect(EtapeParcours.honore.estManquee, isFalse);
    });

    test('chaque transition a un verbe non vide', () {
      for (final e in EtapeParcours.values) {
        for (final s in e.suivantes) {
          expect(e.verbeVers(s).trim(), isNotEmpty, reason: '${e.name}->${s.name}');
        }
      }
    });
  });

  group('Relecture des seances', () {
    test('une consultation typee est relue telle quelle', () {
      final s = Seance.fromForm({
        'type': 'Consultation',
        'poids': 72.5,
        'taille': 175,
        'imc': '23,7',
        'notes': 'Rien a signaler',
        'createdAt': DateTime(2026, 8, 1),
      });
      expect(s.poids, 72.5);
      expect(s.taille, 175);
      expect(s.imc, '23,7');
      expect(s.notes, 'Rien a signaler');
      expect(s.date, DateTime(2026, 8, 1));
      expect(s.aDesMesures, isTrue);
      expect(s.estVide, isFalse);
    });

    test('une ancienne consultation garde son texte en notes', () {
      // Les documents anterieurs n'ont que `contenu`. On ne cherche pas a y
      // deviner un poids : un chiffre faux vaut moins qu'un champ vide.
      final s = Seance.fromForm({
        'type': 'Consultation',
        'contenu': 'Poids : 72.5 kg\nRAS',
      });
      expect(s.notes, 'Poids : 72.5 kg\nRAS');
      expect(s.poids, isNull);
      expect(s.aDesMesures, isFalse);
      expect(s.estVide, isFalse);
    });

    test('un document sans rien est vide', () {
      expect(Seance.fromForm({'type': 'Consultation'}).estVide, isTrue);
      expect(Seance.fromForm({}).estVide, isTrue);
    });

    test('les mesures en texte sont converties', () {
      // Firestore rend des types heterogenes selon comment le champ a ete
      // ecrit : nombre ici, chaine la, virgule decimale parfois.
      final s = Seance.fromForm({'poids': '72,5', 'taille': '175'});
      expect(s.poids, 72.5);
      expect(s.taille, 175);
    });
  });
}

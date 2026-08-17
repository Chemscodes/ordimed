import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/visite.dart';

/// Le regroupement des documents en visites.
///
/// Le dossier patient groupait ses documents par type : toutes les
/// ordonnances ensemble, tous les bilans ensemble. Repondre a « qu'ai-je fait
/// le 3 mars ? » demandait de parcourir quatre listes et de recouper les
/// dates de tete.
///
/// Ces tests portent sur la regle de regroupement, parce que c'est elle qui
/// decide de ce que le medecin voit.

Map<String, dynamic> doc(String type, String iso, {String? visiteId}) => {
  'type': type,
  'createdAt': DateTime.parse(iso),
  if (visiteId != null) 'visiteId': visiteId,
};

void main() {
  group('Lecture du type', () {
    test('les types ecrits par l app sont reconnus', () {
      expect(TypeDocument.depuis('Consultation'), TypeDocument.consultation);
      expect(TypeDocument.depuis('Ordonnance medecin'), TypeDocument.ordonnance);
      expect(TypeDocument.depuis('Demande de bilan'), TypeDocument.bilan);
      expect(TypeDocument.depuis('Formulaire medecin'), TypeDocument.formulaire);
      expect(TypeDocument.depuis('Dossier initial'), TypeDocument.dossierInitial);
    });

    test('« Ordonnance medecin » n est pas un formulaire medecin', () {
      // Les deux contiennent « medecin » : l'ordre des tests compte.
      expect(TypeDocument.depuis('Ordonnance medecin'), TypeDocument.ordonnance);
    });

    test('la casse et les accents ne changent rien', () {
      expect(TypeDocument.depuis('ORDONNANCE'), TypeDocument.ordonnance);
      expect(TypeDocument.depuis('Formulaire médecin'), TypeDocument.formulaire);
    });

    test('un type inconnu devient une note', () {
      // Le dossier contient des types libres saisis a la main.
      expect(TypeDocument.depuis('Compte rendu'), TypeDocument.note);
      expect(TypeDocument.depuis(''), TypeDocument.note);
      expect(TypeDocument.depuis(null), TypeDocument.note);
    });
  });

  group('Regroupement', () {
    test('les documents du meme jour forment une visite', () {
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        doc('Ordonnance medecin', '2026-03-03T09:20:00Z'),
        doc('Demande de bilan', '2026-03-03T09:25:00Z'),
      ]);
      expect(v, hasLength(1));
      expect(v.first.documents, hasLength(3));
      expect(v.first.consultation, isNotNull);
      expect(v.first.ordonnances, hasLength(1));
      expect(v.first.bilans, hasLength(1));
    });

    test('deux jours differents font deux visites', () {
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        doc('Consultation', '2026-04-10T09:00:00Z'),
      ]);
      expect(v, hasLength(2));
    });

    test('un visiteId ne separe pas ce que le jour joint', () {
      // Regle deliberee. La consultation porte un visiteId, l'ordonnance
      // redigee ensuite depuis le dossier n'en a pas : preferer
      // l'identifiant les mettrait dans deux groupes differents, et
      // separerait une visite unique.
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z', visiteId: 'v1'),
        doc('Ordonnance medecin', '2026-03-03T14:00:00Z'),
      ]);
      expect(v, hasLength(1));
      expect(v.first.documents, hasLength(2));
    });

    test('la visite la plus recente vient en premier', () {
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        doc('Consultation', '2026-05-20T09:00:00Z'),
        doc('Consultation', '2026-04-10T09:00:00Z'),
      ]);
      expect(v.map((x) => x.date!.month).toList(), [5, 4, 3]);
    });

    test('dans une visite, les documents sont dans l ordre du travail', () {
      // Du plus ancien au plus recent : la consultation, puis l'ordonnance
      // qu'elle a produite.
      final v = grouperEnVisites([
        doc('Ordonnance medecin', '2026-03-03T09:20:00Z'),
        doc('Consultation', '2026-03-03T09:00:00Z'),
      ]);
      expect(
        v.first.documents.map((d) => d['type']).toList(),
        ['Consultation', 'Ordonnance medecin'],
      );
    });

    test('la date d une visite est celle de son premier document', () {
      // L'heure d'arrivee, pas celle du dernier papier imprime.
      final v = grouperEnVisites([
        doc('Ordonnance medecin', '2026-03-03T11:00:00Z'),
        doc('Consultation', '2026-03-03T09:00:00Z'),
      ]);
      expect(v.first.date!.hour, 9);
    });
  });

  group('Numerotation', () {
    test('la plus ancienne visite est la premiere', () {
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        doc('Consultation', '2026-04-10T09:00:00Z'),
        doc('Consultation', '2026-05-20T09:00:00Z'),
      ]);
      // La liste est du plus recent au plus ancien ; les numeros comptent
      // depuis le debut du suivi.
      expect(v.map((x) => x.numero).toList(), [3, 2, 1]);
    });

    test('une seule visite porte le numero 1', () {
      final v = grouperEnVisites([doc('Consultation', '2026-03-03T09:00:00Z')]);
      expect(v.first.numero, 1);
    });
  });

  group('Documents sans date', () {
    test('ils ne sont pas perdus', () {
      // Il en existe en base. Les ecarter reviendrait a effacer des pieces
      // du dossier medical.
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        {'type': 'Note'},
      ]);
      expect(v, hasLength(2));
      expect(v.any((x) => x.sansDate), isTrue);
    });

    test('ils passent en dernier', () {
      final v = grouperEnVisites([
        {'type': 'Note'},
        doc('Consultation', '2026-03-03T09:00:00Z'),
      ]);
      expect(v.last.sansDate, isTrue);
    });

    test('ils ne recoivent pas de numero invente', () {
      // Leur donner un rang mentirait sur la chronologie.
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        {'type': 'Note'},
      ]);
      expect(v.firstWhere((x) => x.sansDate).numero, 0);
      expect(v.firstWhere((x) => !x.sansDate).numero, 1);
    });

    test('les documents sans date se regroupent entre eux', () {
      final v = grouperEnVisites([{'type': 'Note'}, {'type': 'Note'}]);
      expect(v, hasLength(1));
      expect(v.first.documents, hasLength(2));
    });
  });

  group('Resume d une visite', () {
    test('il dit ce qui a ete produit', () {
      final v = grouperEnVisites([
        doc('Consultation', '2026-03-03T09:00:00Z'),
        doc('Ordonnance medecin', '2026-03-03T09:20:00Z'),
      ]);
      expect(v.first.resume, ['Consultation', 'Ordonnance']);
    });

    test('il compte quand il y en a plusieurs', () {
      final v = grouperEnVisites([
        doc('Ordonnance medecin', '2026-03-03T09:00:00Z'),
        doc('Ordonnance medecin', '2026-03-03T09:05:00Z'),
      ]);
      expect(v.first.resume, ['2 ordonnances']);
    });

    test('l ouverture du dossier est signalee', () {
      final v = grouperEnVisites([
        doc('Dossier initial', '2026-03-03T09:00:00Z'),
        doc('Consultation', '2026-03-03T09:10:00Z'),
      ]);
      expect(v.first.resume, contains('Ouverture du dossier'));
      expect(v.first.resume, contains('Consultation'));
    });

    test('une visite vide a un resume vide', () {
      expect(grouperEnVisites(const []), isEmpty);
    });
  });

  group('Robustesse', () {
    test('un examen reenregistre remplace le premier', () {
      // Le medecin corrige une mesure et enregistre de nouveau. C'est la
      // seconde version qui doit s'afficher.
      //
      // La premiere version de ce test n'assertait que « non nul » : elle
      // passait avec l'ancienne implementation, qui rendait le plus ancien.
      final v = grouperEnVisites([
        {
          'type': 'Consultation',
          'poids': 70,
          'createdAt': DateTime.parse('2026-03-03T09:00:00Z'),
        },
        {
          'type': 'Consultation',
          'poids': 72,
          'createdAt': DateTime.parse('2026-03-03T09:40:00Z'),
        },
      ]);
      expect(v, hasLength(1));
      expect(v.first.consultation!['poids'], 72);
    });

    test('un document sans type reste dans sa visite', () {
      final v = grouperEnVisites([
        {'createdAt': DateTime.parse('2026-03-03T09:00:00Z')},
      ]);
      expect(v, hasLength(1));
      expect(v.first.notes, hasLength(1));
    });
  });
}

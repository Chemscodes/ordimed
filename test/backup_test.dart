import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/services/backup_service.dart';

void main() {
  // Une sauvegarde qu'on ne peut pas relire ne protege de rien. C'est
  // l'aller-retour qui compte, pas l'ecriture — d'ou ces tests, qui passent
  // par un vrai encodage JSON plutot que de comparer des Map en memoire.
  final service = BackupService();

  dynamic allerRetour(dynamic valeur) =>
      service.decoder(jsonDecode(jsonEncode(BackupService.encoder(valeur))));

  group('Aller-retour des types Firestore', () {
    test('une date survit au passage par JSON', () {
      final date = DateTime(2026, 8, 8, 14, 30, 5);
      final revenu = allerRetour(Timestamp.fromDate(date));
      expect(revenu, isA<Timestamp>());
      expect((revenu as Timestamp).toDate(), date);
    });

    test('un DateTime revient en Timestamp', () {
      // Certains documents portent des DateTime bruts selon la facon dont
      // ils ont ete ecrits. Ils doivent revenir utilisables.
      final date = DateTime(2026, 1, 2, 3, 4, 5);
      final revenu = allerRetour(date);
      expect(revenu, isA<Timestamp>());
      expect((revenu as Timestamp).toDate(), date);
    });

    test('les valeurs simples ne sont pas alterees', () {
      expect(allerRetour('Amina'), 'Amina');
      expect(allerRetour(42), 42);
      expect(allerRetour(72.5), 72.5);
      expect(allerRetour(true), true);
      expect(allerRetour(null), isNull);
    });

    test('un dossier patient complet revient identique', () {
      final cree = DateTime(2026, 3, 15, 9, 0);
      final origine = {
        'nom': 'Benali',
        'prenom': 'Amina',
        'age': 34,
        'poids_actuel': 72.5,
        'tel': '0551234567',
        'createdAt': Timestamp.fromDate(cree),
        'deletedAt': null,
        'versements': [
          {'montant': 2000, 'date': Timestamp.fromDate(cree)},
          {'montant': 1500.5, 'date': Timestamp.fromDate(cree)},
        ],
        'meta': {
          'origine': 'bouche_a_oreille',
          'derniere': Timestamp.fromDate(cree),
        },
      };

      final revenu = allerRetour(origine) as Map;
      expect(revenu['nom'], 'Benali');
      expect(revenu['age'], 34);
      expect(revenu['poids_actuel'], 72.5);
      expect(revenu['deletedAt'], isNull);
      expect((revenu['createdAt'] as Timestamp).toDate(), cree);

      // Les dates imbriquees dans un tableau sont le piege classique : un
      // encodeur naif les aplatit en chaines.
      final versements = revenu['versements'] as List;
      expect(versements, hasLength(2));
      expect((versements[0] as Map)['montant'], 2000);
      expect(
        ((versements[1] as Map)['date'] as Timestamp).toDate(),
        cree,
      );
      expect(
        ((revenu['meta'] as Map)['derniere'] as Timestamp).toDate(),
        cree,
      );
    });

    test('un GeoPoint garde ses coordonnees', () {
      final revenu = allerRetour(const GeoPoint(36.75, 3.06));
      expect(revenu, isA<GeoPoint>());
      expect((revenu as GeoPoint).latitude, 36.75);
      expect(revenu.longitude, 3.06);
    });

    test('un tableau vide reste un tableau vide', () {
      expect(allerRetour([]), isEmpty);
      expect(allerRetour(<String, dynamic>{}), isEmpty);
    });

    test('une chaine ressemblant a une date reste une chaine', () {
      // Sans etiquette de type, rien ne doit etre devine : un numero de
      // dossier « 2026-08-08 » ne doit pas devenir une date.
      expect(allerRetour('2026-08-08'), '2026-08-08');
    });

    test('une cle nommee __type dans les donnees ne casse pas la relecture', () {
      // Peu probable, mais le decodeur choisirait alors une branche vide et
      // renverrait null en silence — donc on verifie qu'il renvoie null
      // plutot que de planter.
      final revenu = allerRetour({'__type': 'inconnu', 'value': 'x'});
      expect(revenu, isNull);
    });
  });

  group('Nommage et coherence', () {
    test('le nom de fichier est horodate et triable', () {
      final nom = BackupService.nomFichier(
        maintenant: DateTime(2026, 8, 8, 9, 5),
      );
      expect(nom, 'ordimed-2026-08-08-0905.json');
    });

    test('les noms se trient dans l ordre chronologique', () {
      final tot = BackupService.nomFichier(
        maintenant: DateTime(2026, 8, 8, 9, 5),
      );
      final tard = BackupService.nomFichier(
        maintenant: DateTime(2026, 8, 8, 14, 30),
      );
      final mois = BackupService.nomFichier(
        maintenant: DateTime(2026, 12, 1, 0, 0),
      );
      final tries = [mois, tard, tot]..sort();
      expect(tries, [tot, tard, mois]);
    });

    test('les collections sauvegardees couvrent celles que l app ecrit', () {
      // Firestore ne sait pas lister les sous-collections cote client : la
      // liste est ecrite a la main, donc elle peut se desynchroniser du
      // code. Une collection absente ici n'est pas sauvegardee, en silence.
      expect(
        BackupService.collectionsProfil,
        containsAll([
          'patients',
          'rendezvous',
          'salle_attente',
          'purchases',
          'daily_stats',
        ]),
      );
      expect(BackupService.collectionsPatient, contains('forms'));
    });

    test('le dossier par defaut est en dehors du dossier de l app', () {
      // Une sauvegarde rangee a cote de l'executable disparait avec lui.
      final chemin = BackupService.dossierParDefaut();
      expect(chemin, contains('Ordimed'));
      expect(chemin, contains('sauvegardes'));
    });
  });
}

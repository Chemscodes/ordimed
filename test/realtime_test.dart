import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/services/realtime_service.dart';

void main() {
  // `fluxDepuis` remplace `snapshots()` de Firestore. Trente StreamBuilder
  // en dependent : s'il se tait, s'il double ses charges ou s'il meurt a la
  // premiere erreur, ce sont trente ecrans qui se figent. D'ou ces tests.

  const rapide = Duration(milliseconds: 20);

  test('emet une premiere fois sans attendre le moindre evenement', () async {
    // Un ecran ne doit pas rester vide en attendant qu'une ecriture
    // survienne quelque part dans le cabinet.
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async => 'valeur',
      declencheurs: [declencheur.stream],
      groupage: rapide,
    );

    expect(await flux.first, 'valeur');
  });

  test('recharge quand le serveur signale un changement', () async {
    var appels = 0;
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async => ++appels,
      declencheurs: [declencheur.stream],
      groupage: rapide,
    );

    final recus = <int>[];
    final abo = flux.listen(recus.add);
    addTearDown(abo.cancel);

    await Future<void>.delayed(rapide);
    declencheur.add(null);
    await Future<void>.delayed(rapide * 4);

    expect(recus, [1, 2]);
  });

  test('groupe une rafale de changements en un seul rechargement', () async {
    // Cloturer une consultation ecrit trois fois : la file, le patient, le
    // rendez-vous. Sans groupage, chaque ecran rechargerait trois fois.
    var appels = 0;
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async => ++appels,
      declencheurs: [declencheur.stream],
      groupage: const Duration(milliseconds: 60),
    );

    final abo = flux.listen((_) {});
    addTearDown(abo.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 5; i++) {
      declencheur.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Une charge initiale, puis une seule pour toute la rafale.
    expect(appels, 2);
  });

  test('ecoute plusieurs entites a la fois', () async {
    // Le dossier patient se recharge quand le patient, un document ou un
    // versement bouge.
    var appels = 0;
    final a = StreamController<void>.broadcast();
    final b = StreamController<void>.broadcast();
    addTearDown(a.close);
    addTearDown(b.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async => ++appels,
      declencheurs: [a.stream, b.stream],
      groupage: rapide,
    );

    final abo = flux.listen((_) {});
    addTearDown(abo.cancel);

    await Future<void>.delayed(rapide);
    a.add(null);
    await Future<void>.delayed(rapide * 4);
    b.add(null);
    await Future<void>.delayed(rapide * 4);

    expect(appels, 3);
  });

  test('une erreur ne ferme pas le flux', () async {
    // Firestore reessayait tout seul. Une coupure passagere ne doit pas
    // eteindre definitivement un ecran ouvert.
    var appels = 0;
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async {
        appels++;
        if (appels == 1) throw Exception('serveur injoignable');
        return appels;
      },
      declencheurs: [declencheur.stream],
      groupage: rapide,
    );

    final erreurs = <Object>[];
    final valeurs = <int>[];
    final abo = flux.listen(valeurs.add, onError: erreurs.add);
    addTearDown(abo.cancel);

    await Future<void>.delayed(rapide * 2);
    expect(erreurs, hasLength(1));

    declencheur.add(null);
    await Future<void>.delayed(rapide * 4);

    // Le flux a survecu et redonne des valeurs.
    expect(valeurs, [2]);
  });

  test('deux rechargements ne se croisent pas', () async {
    // Deux requetes en vol dont l'ordre d'arrivee decide de l'affichage
    // feraient clignoter un ecran entre deux etats — et pourraient laisser
    // l'ancien gagner.
    var demarres = 0;
    var simultanes = 0;
    var maxSimultanes = 0;
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async {
        demarres++;
        simultanes++;
        if (simultanes > maxSimultanes) maxSimultanes = simultanes;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        simultanes--;
        return demarres;
      },
      declencheurs: [declencheur.stream],
      groupage: const Duration(milliseconds: 5),
    );

    final abo = flux.listen((_) {});
    addTearDown(abo.cancel);

    // Change pendant que la charge initiale est encore en vol.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    declencheur.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(maxSimultanes, 1);
    // Le changement survenu pendant la charge n'est pas perdu pour autant.
    expect(demarres, greaterThanOrEqualTo(2));
  });

  test('plus rien ne charge apres annulation', () async {
    // Un ecran ferme qui continue d'interroger le serveur, c'est une fuite
    // qui grandit a chaque navigation.
    var appels = 0;
    final declencheur = StreamController<void>.broadcast();
    addTearDown(declencheur.close);

    final flux = RealtimeService.fluxDepuis(
      charger: () async => ++appels,
      declencheurs: [declencheur.stream],
      groupage: rapide,
    );

    final abo = flux.listen((_) {});
    await Future<void>.delayed(rapide * 2);
    final avant = appels;

    await abo.cancel();
    declencheur.add(null);
    await Future<void>.delayed(rapide * 4);

    expect(appels, avant);
  });
}

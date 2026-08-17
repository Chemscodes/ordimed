import 'dart:async';

import 'package:flutter/foundation.dart';

/// Libère des contrôleurs après la fermeture complète d'un dialogue.
///
/// Le motif fautif est partout dans l'app :
///
/// ```dart
/// await showDialog(...);
/// monCtrl.dispose();   // trop tôt
/// ```
///
/// `showDialog` rend la main dès que la route est retirée, mais **la
/// transition de sortie continue** : le dialogue s'efface encore, et ses
/// champs se rebâtissent pendant ce temps. Un `ListenableBuilder` réabonne
/// alors son écouteur à un contrôleur déjà libéré, ce qui lève :
///
///     A TextEditingController was used after being disposed.
///
/// Et cette première erreur en entraîne une seconde, plus obscure, pendant
/// que Flutter démonte le sous-arbre :
///
///     framework.dart: Failed assertion: '_dependents.isEmpty'
///
/// C'est la seconde qui s'affiche en rouge à l'écran, alors que la cause est
/// la première. C'est ce qui rendait le symptôme illisible : la trace parlait
/// d'`InheritedElement` alors que le problème était un champ de texte.
///
/// Le délai couvre la transition de sortie d'un dialogue Material (150 ms).
/// Rien n'attend : la libération part en arrière-plan, l'appelant continue.
void libererApresFermeture(Iterable<ChangeNotifier> controleurs) {
  final aLiberer = controleurs.toList(growable: false);
  apresFermeture(() {
    for (final c in aLiberer) {
      c.dispose();
    }
  });
}

/// Variante pour ce qui n'est pas un [ChangeNotifier].
///
/// Plusieurs objets de l'app — une ligne d'ordonnance, une ligne de bilan —
/// possèdent des contrôleurs et exposent leur propre `dispose()`. Ils ne
/// peuvent pas passer par la liste ci-dessus.
void apresFermeture(void Function() liberer) {
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      // Un contrôleur peut avoir été libéré entre-temps par un autre chemin :
      // mieux vaut l'ignorer que planter l'app en libérant de la mémoire.
      try {
        liberer();
      } catch (_) {}
    }),
  );
}

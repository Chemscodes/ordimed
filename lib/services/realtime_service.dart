import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';

/// Le temps réel, et la raison pour laquelle les écrans ne changent pas.
///
/// Firestore donnait des `Stream` : `snapshots()` réémettait à chaque
/// changement, et 30 `StreamBuilder` s'appuient là-dessus. Une API REST
/// donne des `Future` — les brancher directement obligerait à réécrire
/// chaque écran en `FutureBuilder` avec un rafraîchissement manuel.
///
/// [fluxRafraichi] rend la forme d'origine : un `Stream` qui émet une
/// première fois, puis rejoue la requête quand le serveur signale que
/// l'entité a bougé. Les écrans gardent leur `StreamBuilder`, et la salle
/// d'attente continue de se mettre à jour toute seule chez le médecin
/// pendant que l'assistant y ajoute un patient.
class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;

  /// Un flux par entité (`patients`, `salle_attente`, `rendezvous`…).
  final Map<String, StreamController<void>> _canaux = {};

  /// Émet à chaque reconnexion.
  ///
  /// Pendant une coupure, les événements sont perdus — Socket.IO ne les
  /// rejoue pas. Tout ce qui écoute doit donc recharger au retour, sinon
  /// l'écran affiche l'état d'avant la coupure sans que rien ne l'indique.
  final _reconnecte = StreamController<void>.broadcast();

  bool get connecte => _socket?.connected ?? false;

  void connecter() {
    final jeton = ApiClient.instance.jeton;
    if (jeton == null) return;

    deconnecter();

    final socket = io.io(
      ApiClient.instance.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': jeton})
          .enableReconnection()
          // Un cabinet dont le Wi-Fi saute doit se rebrancher seul, sans
          // que personne ne relance l'app.
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .build(),
    );

    socket.onConnect((_) => _reconnecte.add(null));

    socket.on('changement', (donnees) {
      if (donnees is! Map) return;
      final entite = donnees['entite']?.toString();
      if (entite == null) return;
      _canaux[entite]?.add(null);
    });

    _socket = socket;
  }

  void deconnecter() {
    _socket?.dispose();
    _socket = null;
  }

  /// Signale les changements d'une entité.
  Stream<void> changements(String entite) {
    final canal = _canaux.putIfAbsent(
      entite,
      () => StreamController<void>.broadcast(),
    );
    return canal.stream;
  }

  /// Un `Stream` qui se recharge quand le serveur le dit.
  ///
  /// Remplace `.snapshots()`. Les différences honnêtes avec Firestore :
  ///
  /// - la donnée est **rechargée**, pas poussée : le serveur annonce qu'une
  ///   entité a bougé, l'app redemande. Un aller-retour de plus, invisible
  ///   sur un réseau local ;
  /// - les changements sont **groupés** : cinq écritures d'affilée — une
  ///   clôture de consultation en fait trois — ne déclenchent qu'un seul
  ///   rechargement ;
  /// - une erreur ne **ferme pas** le flux. Firestore réessayait tout seul ;
  ///   ici une coupure passagère ne doit pas éteindre définitivement un
  ///   écran ouvert.
  Stream<T> fluxRafraichi<T>({
    required Future<T> Function() charger,
    required List<String> entites,
    Duration groupage = const Duration(milliseconds: 120),
  }) => fluxDepuis(
    charger: charger,
    declencheurs: [
      for (final e in entites) changements(e),
      // Au retour du réseau, l'état affiché date d'avant la coupure.
      _reconnecte.stream,
    ],
    groupage: groupage,
  );

  /// Le mécanisme, séparé de sa source.
  ///
  /// [fluxRafraichi] le branche sur Socket.IO ; un test le branche sur un
  /// contrôleur qu'il pilote. Sans cette séparation, vérifier le groupage
  /// des rechargements exigerait un vrai serveur.
  static Stream<T> fluxDepuis<T>({
    required Future<T> Function() charger,
    required List<Stream<void>> declencheurs,
    Duration groupage = const Duration(milliseconds: 120),
  }) {
    /// Diffusé, et non à abonnement unique.
    ///
    /// La première version rendait un `StreamController` ordinaire : écoutable
    /// une seule fois. Un écran qui gardait le flux dans un champ et le
    /// donnait à deux `StreamBuilder` — ou qui revenait sur une étape déjà
    /// affichée — obtenait :
    ///
    ///     Bad state: Stream has already been listened to
    ///
    /// Le défaut était dans cette fabrique, pas dans les écrans : un flux de
    /// lecture doit pouvoir être lu plusieurs fois.
    final diffusion = StreamController<T>.broadcast();

    final abonnements = <StreamSubscription>[];
    Timer? minuteur;
    var actif = false;
    var enCours = false;
    var redemander = false;

    Future<void> recharger() async {
      if (!actif) return;
      if (enCours) {
        // Un rechargement est déjà en vol : on note qu'il en faudra un autre
        // après, plutôt que d'en lancer deux en parallèle dont l'ordre
        // d'arrivée déciderait de ce qui s'affiche.
        redemander = true;
        return;
      }
      enCours = true;
      try {
        final valeur = await charger();
        if (actif) diffusion.add(valeur);
      } catch (e, pile) {
        if (actif) diffusion.addError(e, pile);
      } finally {
        enCours = false;
        if (redemander && actif) {
          redemander = false;
          unawaited(recharger());
        }
      }
    }

    void programmer() {
      minuteur?.cancel();
      minuteur = Timer(groupage, recharger);
    }

    /// Branche les déclencheurs. Doit pouvoir être rejouée : un écran fermé
    /// puis réouvert repasse par ici.
    void demarrer() {
      actif = true;
      for (final d in declencheurs) {
        abonnements.add(d.listen((_) => programmer()));
      }
    }

    Future<void> arreter() async {
      actif = false;
      minuteur?.cancel();
      minuteur = null;
      for (final a in abonnements) {
        await a.cancel();
      }
      abonnements.clear();
    }

    return Stream<T>.multi((abonne) {
      // Le premier abonné branche les déclencheurs ; le dernier à partir les
      // débranche. Sans ça, un écran fermé continuerait d'interroger le
      // serveur à chaque changement.
      final premier = !diffusion.hasListener;

      final sub = diffusion.stream.listen(
        abonne.add,
        onError: abonne.addError,
      );
      abonne.onCancel = () async {
        await sub.cancel();
        if (!diffusion.hasListener) await arreter();
      };

      if (premier) demarrer();

      // Chaque nouvel abonné demande les données : un contrôleur diffusé ne
      // rejoue pas ce qui est déjà passé, et un écran qui arrive en second
      // resterait vide jusqu'à la prochaine écriture. Les abonnés déjà en
      // place reçoivent la même valeur une fois de plus — sans conséquence.
      recharger();
    });
  }
}

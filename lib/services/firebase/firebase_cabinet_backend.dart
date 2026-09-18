import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/coerce.dart';
import '../api_client.dart';
import '../cabinet_backend.dart';
import '../realtime_service.dart';
import 'firebase_refs.dart';

/// Le cabinet stocké dans Firestore, sans serveur intermédiaire.
///
/// L'avantage tient en une phrase : le cabinet installe l'application et
/// les postes se synchronisent, il n'y a rien à administrer. Les lectures
/// sont de vrais `snapshots()` — la donnée est poussée, pas rechargée sur
/// annonce comme du côté Node.
///
/// Le prix à payer est que la logique métier redescend ici. Trois choses
/// que le backend Node garantissait doivent être reconstruites, et une
/// quatrième ne peut pas l'être complètement :
///
/// - **les écritures liées** (encaisser, clôturer) passent par
///   `runTransaction` : Firestore sait les rendre atomiques ;
/// - **les totaux de caisse** s'incrémentent par `FieldValue.increment`,
///   ce qui reste juste même quand deux postes encaissent en même temps ;
/// - **le PIN** est haché en SHA-256 et retiré de tout ce qui sort d'ici,
///   mais la comparaison a lieu dans l'app, et les règles Firestore donnent
///   au poste connecté l'accès à tout son cabinet. Autrement dit : le code
///   sépare les rôles entre collègues, il ne résiste pas à quelqu'un qui a
///   déjà les identifiants du cabinet. Côté Node, bcrypt sur le serveur en
///   faisait une vraie barrière ;
/// - **les conflits de créneaux** sont détectés par une requête faite juste
///   avant l'écriture, et non dans la transaction : Firestore ne sait pas
///   requêter dans une transaction. Deux postes qui posent la même heure à
///   la même seconde peuvent tous deux passer. La fenêtre est étroite et
///   sans gravité — un créneau en double se voit et se corrige — mais elle
///   existe, là où le backend Node la fermait.
///
/// Ces différences sont le vrai coût du sans-serveur. Elles sont
/// acceptables pour un cabinet qui ne veut rien administrer ; c'est
/// exactement le choix que [BackendConfig] laisse ouvert.
class FirebaseCabinetBackend implements CabinetBackend {
  FirebaseCabinetBackend._();

  static final FirebaseCabinetBackend instance = FirebaseCabinetBackend._();

  CollectionReference<Map<String, dynamic>> _c(String nom) =>
      FirebaseRefs.c(nom);

  DocumentReference<Map<String, dynamic>> get _cabinet =>
      FirebaseRefs.cabinetDoc();

  /// Exécute en traduisant les échecs Firestore en [ApiException].
  ///
  /// Les écrans attrapent déjà cette exception et lisent `estReseau` ou
  /// `estConflit` ; laisser remonter un `FirebaseException` les obligerait
  /// à connaître les deux vocabulaires.
  static Future<T> _garde<T>(Future<T> Function() corps) async {
    try {
      return await corps();
    } catch (e) {
      throw FirebaseRefs.traduire(e);
    }
  }

  /// Le code par défaut d'un profil qui n'en a pas encore choisi un.
  ///
  /// Repris du backend Node, qui crée le médecin principal avec ce code.
  /// Un profil sans code du tout ouvrirait le poste à n'importe quelle
  /// saisie.
  static const _pinParDefaut = '0000';

  /// Quatre à six chiffres, comme le valide le backend Node.
  static final _formatPin = RegExp(r'^\d{4,6}$');

  /// Retire le haché du code avant de rendre un profil.
  ///
  /// Le backend Node le retire de ses réponses, et il faut faire pareil :
  /// un PIN de quatre à six chiffres se retrouve à partir de son SHA-256 en
  /// parcourant le million de combinaisons, c'est-à-dire instantanément.
  /// Le laisser passer annulerait le hachage.
  ///
  /// C'est une précaution de couche, pas une barrière : sur Firebase, les
  /// règles donnent au poste connecté l'accès à tout son cabinet, documents
  /// de profils compris. Qui contrôle le compte du cabinet peut lire ces
  /// hachés directement. Le code PIN sépare les rôles entre collègues ; il
  /// ne protège pas d'un poste dont on a déjà les identifiants.
  static Map<String, dynamic> _sansPin(Map<String, dynamic> profil) =>
      profil..remove('pinHash');

  /// Ce qu'un profil voit des listes partagées.
  ///
  /// Le médecin principal voit tout le cabinet. Les autres voient ce qui
  /// les concerne **comme médecin ou comme assistant** : l'assistant qui a
  /// ouvert un dossier doit le retrouver, alors que le patient est suivi
  /// par un autre. Filtrer sur le seul `doctorId` viderait l'écran de
  /// l'assistant, et réduirait celui du médecin principal à ses propres
  /// patients.
  ///
  /// C'est la règle qu'applique le backend Node ; elle est reproduite ici à
  /// l'identique, sans quoi les deux bases ne montreraient pas la même
  /// chose au même poste.
  Future<Query<Map<String, dynamic>>> _portee(
    String collection,
    String? profileId,
  ) async {
    final col = _c(collection);
    if (profileId == null) return col;

    final p = await _c('profiles').doc(profileId).get();
    if (!p.exists) {
      throw const ApiException(message: 'Profil introuvable', code: 404);
    }
    if (p.data()?['role'] == 'medecin_principal') return col;

    return col.where(
      Filter.or(
        Filter('doctorId', isEqualTo: profileId),
        Filter('assistantId', isEqualTo: profileId),
      ),
    );
  }

  /// La même portée, en flux.
  ///
  /// Le rôle doit être lu avant de pouvoir construire la requête, d'où le
  /// `Future` déroulé en amont : sans lui, l'abonnement se ferait sur une
  /// portée encore inconnue.
  Stream<QuerySnapshot<Map<String, dynamic>>> _porteeFlux(
    String collection,
    String? profileId,
  ) => Stream.fromFuture(
    _portee(collection, profileId),
  ).asyncExpand((q) => q.snapshots());

  /// Le tri par date, fait dans l'app plutôt que par la requête.
  ///
  /// Un `orderBy` sur `createdAt` combiné à un `where` exige un index
  /// composite, et un index manquant fait échouer la requête en production
  /// alors qu'elle passait en développement. Les volumes d'un cabinet —
  /// quelques centaines de documents par patient au pire — ne justifient
  /// pas ce risque.
  static List<Map<String, dynamic>> _parDateDesc(
    List<Map<String, dynamic>> liste,
  ) {
    DateTime cle(Map<String, dynamic> m) =>
        DateTime.tryParse('${m['createdAt']}') ?? DateTime(1970);
    return liste..sort((a, b) => cle(b).compareTo(cle(a)));
  }

  // -----------------------------------------------------------------
  //  Le cabinet
  // -----------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> cabinet() => _garde(() async {
    final d = await _cabinet.get();
    return FirebaseRefs.versMap(d);
  });

  @override
  Future<Map<String, dynamic>> majCabinet(Map<String, dynamic> champs) =>
      _garde(() async {
        await _cabinet.set(
          FirebaseRefs.versFirestore(champs),
          SetOptions(merge: true),
        );
        return cabinet();
      });

  @override
  Future<void> majHoraires(Map<String, dynamic> horaires) =>
      majCabinet({'horaires': horaires});

  @override
  Future<void> ajouterListe(String liste, Iterable<String> valeurs) =>
      _garde(() async {
        final propres = valeurs
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList();
        if (propres.isEmpty) return;
        // `arrayUnion` dédoublonne tout seul : la liste s'enrichit sans que
        // l'app ait à relire ce qu'elle contient déjà.
        await _cabinet.set({
          'listesReference': {liste: FieldValue.arrayUnion(propres)},
        }, SetOptions(merge: true));
      });

  // -----------------------------------------------------------------
  //  Profils
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> profils() => _garde(() async {
    final s = await _c('profiles').get();
    return FirebaseRefs.versListe(s).map(_sansPin).toList();
  });

  @override
  Stream<List<Map<String, dynamic>>> profilsFlux() => _c('profiles')
      .snapshots()
      .map((s) => FirebaseRefs.versListe(s).map(_sansPin).toList())
      .handleError((e) => throw FirebaseRefs.traduire(e));

  @override
  Future<Map<String, dynamic>> creerProfil({
    required String name,
    required String role,
    required String pin,
  }) => _garde(() async {
    if (!_formatPin.hasMatch(pin.trim())) {
      throw const ApiException(
        message: 'Le code doit comporter 4 à 6 chiffres',
        code: 400,
      );
    }
    final ref = _c('profiles').doc();
    await ref.set({
      'parentUid': FirebaseRefs.cabinetId,
      'name': name.trim(),
      'role': role,
      'pinHash': FirebaseRefs.hacherPin(pin),
      'wilaya': '',
      'address': '',
      'tel': '',
      'nameAr': '',
      'subtitle': '',
      'ordonnanceCounter': 0,
      'whatsappTemplate': '',
      'createdAt': Timestamp.now(),
    });
    return _sansPin(FirebaseRefs.versMap(await ref.get()));
  });

  @override
  Future<Map<String, dynamic>> majProfil(
    String id,
    Map<String, dynamic> champs,
  ) => _garde(() async {
    final propres = FirebaseRefs.versFirestore(champs);
    // Le code arrive en clair depuis l'écran de réglages ; il ne doit pas
    // se retrouver tel quel en base.
    if (propres.containsKey('pin')) {
      final pin = '${propres.remove('pin')}'.trim();
      if (!_formatPin.hasMatch(pin)) {
        throw const ApiException(
          message: 'Le code doit comporter 4 à 6 chiffres',
          code: 400,
        );
      }
      propres['pinHash'] = FirebaseRefs.hacherPin(pin);
    }
    final ref = _c('profiles').doc(id);
    await ref.set(propres, SetOptions(merge: true));
    return _sansPin(FirebaseRefs.versMap(await ref.get()));
  });

  @override
  Future<void> supprimerProfil(String id) =>
      _garde(() => _c('profiles').doc(id).delete());

  @override
  Future<Map<String, dynamic>> verifierPin(String profileId, String pin) =>
      _garde(() async {
        final d = await _c('profiles').doc(profileId).get();
        if (!d.exists) {
          throw const ApiException(message: 'Profil introuvable', code: 404);
        }
        final profil = FirebaseRefs.versMap(d);
        final attendu = '${profil['pinHash'] ?? ''}';

        // Sans haché enregistré, seul le code par défaut passe — et non
        // n'importe quelle saisie. Le backend Node applique la même règle :
        // un profil mal initialisé ne doit pas devenir une porte ouverte.
        final ok = attendu.isEmpty
            ? pin.trim() == _pinParDefaut
            : attendu == FirebaseRefs.hacherPin(pin);
        if (!ok) {
          throw const ApiException(message: 'Code incorrect', code: 401);
        }
        return _sansPin(profil);
      });

  // -----------------------------------------------------------------
  //  Patients
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> patients({
    String? profileId,
    bool inclureSupprimes = false,
  }) => _garde(() async {
    final q = await _portee('patients', profileId);
    return _parDateDesc(
      _vivants(
        FirebaseRefs.versListe(await q.get()),
        inclureSupprimes: inclureSupprimes,
      ),
    );
  });

  @override
  Stream<List<Map<String, dynamic>>> patientsFlux({String? profileId}) =>
      _porteeFlux(
        'patients',
        profileId,
      ).map((s) => _parDateDesc(_vivants(FirebaseRefs.versListe(s))));

  /// Comme [patientsFlux], filtré sur `createdAt` après lecture plutôt que
  /// dans la requête.
  ///
  /// Un `where('createdAt', ...)` combiné au filtre `Filter.or` d'un profil
  /// scopé (`doctorId`/`assistantId`) exigerait un index composite non
  /// déployé — Firestore refuse la requête (`FAILED_PRECONDITION`) sans lui.
  /// Filtrer côté client garde le même unique listener sur la portée déjà
  /// réduite au médecin/assistant plutôt qu'au cabinet entier, sans ce
  /// risque : le gain vient de la portée, pas d'un `where` supplémentaire.
  @override
  Stream<List<Map<String, dynamic>>> patientsRecentsFlux({
    String? profileId,
    required DateTime depuis,
  }) => _porteeFlux('patients', profileId).map((s) {
    final tous = _parDateDesc(_vivants(FirebaseRefs.versListe(s)));
    return tous.where((p) {
      final d = DateTime.tryParse('${p['createdAt']}');
      return d != null && !d.isBefore(depuis);
    }).toList();
  });

  /// Écarte les dossiers supprimés.
  ///
  /// En mémoire et non par la requête : `where('deletedAt', isNull: true)`
  /// ne trouverait pas les dossiers où le champ est absent — ceux d'avant
  /// la suppression douce, et ceux venus d'un import.
  static List<Map<String, dynamic>> _vivants(
    List<Map<String, dynamic>> liste, {
    bool inclureSupprimes = false,
  }) => inclureSupprimes
      ? liste
      : liste.where((p) => p['deletedAt'] == null).toList();

  @override
  Future<Map<String, dynamic>> patient(String id) => _garde(() async {
    final d = await _c('patients').doc(id).get();
    if (!d.exists) {
      throw const ApiException(message: 'Patient introuvable', code: 404);
    }
    return FirebaseRefs.versMap(d);
  });

  @override
  Future<Map<String, dynamic>> dossier(String id) => _garde(() async {
    // Les trois lectures partent ensemble : la page du dossier les affiche
    // ensemble, les enchaîner tripleraient le temps d'ouverture.
    final (p, formulaires, regles) = await (
      _c('patients').doc(id).get(),
      _c('forms').where('patientId', isEqualTo: id).get(),
      _c('versements').where('patientId', isEqualTo: id).get(),
    ).wait;

    if (!p.exists) {
      throw const ApiException(message: 'Patient introuvable', code: 404);
    }

    return {
      'patient': FirebaseRefs.versMap(p),
      'forms': _parDateDesc(FirebaseRefs.versListe(formulaires)),
      'versements': _parDateDesc(FirebaseRefs.versListe(regles)),
    };
  });

  /// Trois sources, un seul flux.
  ///
  /// Réutilise le mécanisme écrit pour Socket.IO : il groupe les
  /// déclenchements rapprochés — une clôture de consultation touche le
  /// patient et son rendez-vous — et ne ferme pas le flux sur une erreur
  /// passagère.
  @override
  Stream<Map<String, dynamic>> dossierFlux(String id) =>
      RealtimeService.fluxDepuis(
        charger: () => dossier(id),
        declencheurs: [
          _c('patients').doc(id).snapshots().map((_) {}),
          _c('forms').where('patientId', isEqualTo: id).snapshots().map((_) {}),
          _c(
            'versements',
          ).where('patientId', isEqualTo: id).snapshots().map((_) {}),
        ],
      );

  @override
  Stream<Map<String, dynamic>> patientDocFlux(String id) =>
      _c('patients').doc(id).snapshots().map(FirebaseRefs.versMap);

  /// Écrit `motif` à partir de `motifs` quand l'appelant n'a donné que la
  /// liste.
  ///
  /// Les deux champs coexistent en base : `motifs` est la liste, `motif` la
  /// même chose jointe par « , ». Plusieurs vues ne lisent que le second, et
  /// l'écran d'accueil n'envoie que le premier — sans cette dérivation, le
  /// motif s'afficherait vide dans la file et sur le dossier.
  static Map<String, dynamic> _avecMotif(Map<String, dynamic> champs) {
    if (champs.containsKey('motif') || !champs.containsKey('motifs')) {
      return champs;
    }
    final motifs = (champs['motifs'] as List? ?? const [])
        .map((m) => '$m'.trim())
        .where((m) => m.isNotEmpty);
    return {...champs, 'motif': motifs.join(', ')};
  }

  /// Le dossier, son formulaire initial et son entrée en salle.
  ///
  /// Les trois partaient ensemble depuis l'écran d'accueil, et c'est
  /// volontaire : un échec partiel laisserait le patient visible d'un côté
  /// et absent de l'autre — inscrit mais introuvable dans la file, ou en
  /// file sans dossier ouvert. Le lot garantit que les trois arrivent, ou
  /// aucun.
  @override
  Future<Map<String, dynamic>> creerPatient(Map<String, dynamic> champs) =>
      _garde(() async {
        final propres = _avecMotif(FirebaseRefs.versFirestore(champs));

        // Ces deux-là pilotent la création ; ce ne sont pas des champs du
        // dossier et ils n'ont rien à faire dans le document.
        final formulaireInitial = '${propres.remove('formulaireInitial') ?? ''}'
            .trim();
        final ajouterEnSalle = propres.remove('ajouterEnSalle') != false;

        if ('${propres['nom'] ?? ''}'.trim().isEmpty) {
          throw const ApiException(
            message: 'Le nom est obligatoire',
            code: 400,
          );
        }

        final maintenant = Timestamp.now();
        final ref = _c('patients').doc();
        final dossier = {
          ...propres,
          'parentUid': FirebaseRefs.cabinetId,
          'totalVersements': 0,
          'seancesEffectuees': 0,
          'versements': <Map<String, dynamic>>[],
          'deletedAt': null,
          'createdAt': maintenant,
        };

        final lot = FirebaseRefs.base.batch();
        lot.set(ref, dossier);

        lot.set(_c('forms').doc(), {
          'parentUid': FirebaseRefs.cabinetId,
          'patientId': ref.id,
          'auteurProfileId': propres['assistantId'] ?? propres['doctorId'],
          'type': 'Dossier initial',
          'contenu': formulaireInitial.isEmpty
              ? "Dossier initial créé par l'assistant"
              : formulaireInitial,
          'createdAt': maintenant,
        });

        if (ajouterEnSalle) {
          lot.set(
            _c('salle_attente').doc(),
            _ligneFile(
              patient: dossier,
              patientId: ref.id,
              rdvId: null,
              motif: '',
              maintenant: maintenant,
            ),
          );
        }

        await lot.commit();
        return FirebaseRefs.versMap(await ref.get());
      });

  @override
  Future<Map<String, dynamic>> majPatient(
    String id,
    Map<String, dynamic> champs,
  ) => _garde(() async {
    final ref = _c('patients').doc(id);
    await ref.set(
      _avecMotif(FirebaseRefs.versFirestore(champs)),
      SetOptions(merge: true),
    );
    return FirebaseRefs.versMap(await ref.get());
  });

  @override
  Future<void> supprimerPatient(String id) => _garde(
    () => _c('patients').doc(id).update({'deletedAt': Timestamp.now()}),
  );

  @override
  Future<void> restaurerPatient(String id) =>
      _garde(() => _c('patients').doc(id).update({'deletedAt': null}));

  // -----------------------------------------------------------------
  //  Documents
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> documents({
    String? patientId,
    String? type,
    DateTime? jour,
  }) => _garde(() async {
    Query<Map<String, dynamic>> q = _c('forms');
    if (patientId != null) q = q.where('patientId', isEqualTo: patientId);
    if (type != null) q = q.where('type', isEqualTo: type);
    var liste = FirebaseRefs.versListe(await q.get());
    if (jour != null) {
      // Filtré en mémoire : un intervalle de dates combiné aux deux `where`
      // ci-dessus demanderait encore un index composite.
      final cle = FirebaseRefs.dayKey(jour);
      liste = liste.where((f) {
        final d = DateTime.tryParse('${f['createdAt']}');
        return d != null && FirebaseRefs.dayKey(d) == cle;
      }).toList();
    }
    return _parDateDesc(liste);
  });

  @override
  Stream<List<Map<String, dynamic>>> documentsFlux({String? patientId}) {
    Query<Map<String, dynamic>> q = _c('forms');
    if (patientId != null) q = q.where('patientId', isEqualTo: patientId);
    return q.snapshots().map((s) => _parDateDesc(FirebaseRefs.versListe(s)));
  }

  @override
  Future<Map<String, dynamic>> creerDocument(Map<String, dynamic> champs) =>
      _garde(() async {
        final ref = _c('forms').doc();
        await ref.set({
          ...FirebaseRefs.versFirestore(champs),
          'parentUid': FirebaseRefs.cabinetId,
          'createdAt': Timestamp.now(),
        });
        return FirebaseRefs.versMap(await ref.get());
      });

  @override
  Future<Map<String, dynamic>> majDocument(
    String id,
    Map<String, dynamic> champs,
  ) => _garde(() async {
    final propres = FirebaseRefs.versFirestore(champs);
    // Le type décide de la mise en page et de ce que la consultation
    // considère comme rédigé aujourd'hui : le changer après coup
    // déplacerait un document déjà imprimé dans une autre catégorie.
    propres.remove('type');
    final ref = _c('forms').doc(id);
    await ref.set(propres, SetOptions(merge: true));
    return FirebaseRefs.versMap(await ref.get());
  });

  @override
  Future<void> supprimerDocument(String id) =>
      _garde(() => _c('forms').doc(id).delete());

  // -----------------------------------------------------------------
  //  Versements
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> versements({String? patientId}) =>
      _garde(() async {
        Query<Map<String, dynamic>> q = _c('versements');
        if (patientId != null) q = q.where('patientId', isEqualTo: patientId);
        return _parDateDesc(FirebaseRefs.versListe(await q.get()));
      });

  @override
  Stream<List<Map<String, dynamic>>> versementsFlux({String? patientId}) {
    Query<Map<String, dynamic>> q = _c('versements');
    if (patientId != null) q = q.where('patientId', isEqualTo: patientId);
    return q.snapshots().map((s) => _parDateDesc(FirebaseRefs.versListe(s)));
  }

  /// Trois écritures, une transaction.
  ///
  /// Le versement, le total du patient et la recette du jour doivent
  /// bouger ensemble. Une caisse juste à moitié est pire qu'une caisse
  /// fausse : on ne sait pas laquelle des deux croire.
  @override
  Future<Map<String, dynamic>> encaisser({
    required String patientId,
    required double montant,
    String? auteurProfileId,
  }) => _garde(() async {
    if (montant <= 0) {
      throw const ApiException(message: 'Montant invalide', code: 400);
    }

    final maintenant = DateTime.now();
    final horodatage = Timestamp.fromDate(maintenant);
    final jour = FirebaseRefs.dayKey(maintenant);

    final refPatient = _c('patients').doc(patientId);
    final refVersement = _c('versements').doc();
    final refStat = _c('daily_stats').doc(jour);

    await FirebaseRefs.base.runTransaction((tx) async {
      final snap = await tx.get(refPatient);
      if (!snap.exists) {
        throw const ApiException(message: 'Patient introuvable', code: 404);
      }
      final patient = snap.data()!;
      final doctorId = '${patient['doctorId'] ?? ''}';
      final doctorNom = '${patient['assignedMedecinName'] ?? ''}';

      tx.set(refVersement, {
        'parentUid': FirebaseRefs.cabinetId,
        'patientId': patientId,
        'doctorId': patient['doctorId'],
        'auteurProfileId': auteurProfileId,
        'montant': montant,
        'dayKey': jour,
        'createdAt': horodatage,
      });

      // Le cache des versements récents, recopié en tête.
      //
      // Il doublonne la collection `versements`, qui porte l'historique
      // complet. Le doublon est assumé : le dossier patient affiche les
      // derniers règlements sans seconde requête, et la borne de 50
      // empêche le document d'enfler indéfiniment.
      final cache = [
        {
          'montant': montant,
          'createdAt': horodatage,
          'dayKey': jour,
          'auteurProfileId': auteurProfileId ?? '',
        },
        ...(patient['versements'] as List? ?? const []),
      ];

      tx.update(refPatient, {
        'totalVersements': FieldValue.increment(montant),
        'versements': cache.take(50).toList(),
      });

      // `increment` plutôt qu'une lecture suivie d'une écriture : deux
      // postes qui encaissent à la même seconde s'additionnent au lieu de
      // s'écraser.
      tx.set(refStat, {
        'parentUid': FirebaseRefs.cabinetId,
        'dayKey': jour,
        'date': horodatage,
        'versementsTotal': FieldValue.increment(montant),
        'versementsCount': FieldValue.increment(1),
        if (doctorId.isNotEmpty)
          'doctorVersements': {
            doctorId: {
              'name': doctorNom,
              'total': FieldValue.increment(montant),
              'count': FieldValue.increment(1),
            },
          },
        'updatedAt': horodatage,
      }, SetOptions(merge: true));
    });

    return FirebaseRefs.versMap(await refVersement.get());
  });

  // -----------------------------------------------------------------
  //  Rendez-vous
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> rendezVous({
    String? profileId,
    DateTime? jour,
    DateTime? depuis,
    int? limit,
  }) => _garde(() async {
    final q = await _portee('rendezvous', profileId);
    final liste = _agenda(
      FirebaseRefs.versListe(await q.get()),
      jour: jour,
      depuis: depuis,
    );
    return limit == null ? liste : liste.take(limit).toList();
  });

  @override
  Stream<List<Map<String, dynamic>>> rendezVousFlux({
    String? profileId,
    DateTime? jour,
  }) => _porteeFlux(
    'rendezvous',
    profileId,
  ).map((s) => _agenda(FirebaseRefs.versListe(s), jour: jour));

  /// Les rendez-vous filtrés et remis dans l'ordre d'un agenda.
  ///
  /// Croissant, contrairement aux autres listes : un agenda se lit du plus
  /// proche au plus lointain.
  static List<Map<String, dynamic>> _agenda(
    List<Map<String, dynamic>> liste, {
    DateTime? jour,
    DateTime? depuis,
  }) {
    DateTime? quand(Map<String, dynamic> r) =>
        DateTime.tryParse('${r['datetime']}');

    var gardes = liste;
    if (jour != null) {
      final cle = FirebaseRefs.dayKey(jour);
      gardes = gardes.where((r) {
        final d = quand(r);
        return d != null && FirebaseRefs.dayKey(d) == cle;
      }).toList();
    }
    if (depuis != null) {
      gardes = gardes.where((r) {
        final d = quand(r);
        return d != null && !d.isBefore(depuis);
      }).toList();
    }

    final sortie = [...gardes];
    sortie.sort(
      (a, b) =>
          (quand(a) ?? DateTime(1970)).compareTo(quand(b) ?? DateTime(1970)),
    );
    return sortie;
  }

  /// Pose un rendez-vous, si le créneau est libre.
  ///
  /// Le contrôle de conflit précède l'écriture au lieu de l'accompagner :
  /// Firestore ne sait pas requêter dans une transaction. Deux postes qui
  /// posent la même heure dans le même souffle passeront tous les deux —
  /// c'est la limite annoncée en tête de fichier, et la raison pour
  /// laquelle un cabinet très fréquenté gagne à rester sur le backend Node.
  @override
  Future<Map<String, dynamic>> planifier(Map<String, dynamic> champs) =>
      _garde(() async {
        final debut = DateTime.tryParse('${champs['datetime']}');
        if (debut == null) {
          throw const ApiException(message: 'Date invalide', code: 400);
        }
        final duree = (champs['duree'] as num?)?.toInt() ?? 20;
        final fin = debut.add(Duration(minutes: duree));
        final medecin = '${champs['doctorId'] ?? ''}';

        if (medecin.isNotEmpty) {
          final jour = await rendezVous(profileId: medecin, jour: debut);
          for (final r in jour) {
            // Un rendez-vous annulé ou manqué libère sa place.
            final etape = '${r['etape'] ?? ''}';
            if (etape == 'annule' || etape == 'absent') continue;

            final d = DateTime.tryParse('${r['datetime']}');
            if (d == null) continue;
            final f = d.add(
              Duration(minutes: (r['duree'] as num?)?.toInt() ?? 20),
            );
            // Deux intervalles se chevauchent si chacun commence avant que
            // l'autre finisse.
            if (debut.isBefore(f) && d.isBefore(fin)) {
              throw ApiException(
                message: 'Ce créneau est déjà pris',
                code: 409,
                donnees: r,
              );
            }
          }
        }

        final ref = _c('rendezvous').doc();
        await ref.set({
          ...FirebaseRefs.versFirestore(champs),
          'parentUid': FirebaseRefs.cabinetId,
          'duree': duree,
          'etape': '${champs['etape'] ?? 'planifie'}',
          'etapesAt': <String, dynamic>{},
          'createdAt': Timestamp.now(),
        });
        return FirebaseRefs.versMap(await ref.get());
      });

  @override
  Future<Map<String, dynamic>> majRendezVous(
    String id,
    Map<String, dynamic> champs,
  ) => _garde(() async {
    final propres = FirebaseRefs.versFirestore(champs);
    // L'app envoie `reminderSentAt: true` pour dire « envoyé maintenant » :
    // c'est le serveur Node qui posait l'heure, il faut le faire ici.
    if (propres['reminderSentAt'] == true) {
      propres['reminderSentAt'] = Timestamp.now();
    }
    propres['updatedAt'] = Timestamp.now();
    final ref = _c('rendezvous').doc(id);
    await ref.set(propres, SetOptions(merge: true));
    return FirebaseRefs.versMap(await ref.get());
  });

  @override
  Future<Map<String, dynamic>> changerEtapeRdv(
    String id,
    String etape, {
    String? motifAnnulation,
  }) => _garde(() async {
    final maintenant = Timestamp.now();
    final ref = _c('rendezvous').doc(id);
    await ref.set({
      'etape': etape,
      // Un horodatage par étape franchie : savoir *quand* un patient est
      // arrivé est ce qui permettra plus tard de mesurer une attente réelle.
      'etapesAt': {etape: maintenant},
      if (motifAnnulation != null) 'motifAnnulation': motifAnnulation,
      'updatedAt': maintenant,
    }, SetOptions(merge: true));
    return FirebaseRefs.versMap(await ref.get());
  });

  /// Le patient se présente.
  ///
  /// Crée l'entrée en salle **et** marque le rendez-vous, en un seul lot :
  /// les deux sont indissociables. Un patient présent au comptoir mais
  /// absent de la file n'existe pour aucun des trois postes, et un
  /// rendez-vous resté « à venir » alors que le patient est déjà là se
  /// signalerait comme un oubli le soir venu.
  @override
  Future<Map<String, dynamic>> marquerArrive(String rdvId) => _garde(() async {
    final rdv = await _c('rendezvous').doc(rdvId).get();
    if (!rdv.exists) {
      throw const ApiException(message: 'Rendez-vous introuvable', code: 404);
    }
    final r = FirebaseRefs.versMap(rdv);
    final patientId = '${r['patientId']}';

    final p = await _c('patients').doc(patientId).get();
    if (!p.exists) {
      throw const ApiException(message: 'Patient introuvable', code: 404);
    }

    final maintenant = Timestamp.now();
    final refRdv = _c('rendezvous').doc(rdvId);
    final etape = {
      'etape': 'arrive',
      'etapesAt': {'arrive': maintenant},
      'updatedAt': maintenant,
    };

    // Déjà dans la file : le rendez-vous reste à marquer, mais il ne faut
    // surtout pas créer une seconde ligne — deux lignes pour la même
    // personne feraient décompter deux séances.
    final dejaLa = await _ligneOuverte(patientId);
    if (dejaLa != null) {
      await refRdv.set(etape, SetOptions(merge: true));
      return FirebaseRefs.versMap(dejaLa);
    }

    final ref = _c('salle_attente').doc();
    final lot = FirebaseRefs.base.batch();
    lot.set(
      ref,
      _ligneFile(
        patient: FirebaseRefs.versMap(p),
        patientId: patientId,
        rdvId: rdvId,
        motif: '${r['motif'] ?? ''}',
        maintenant: maintenant,
      ),
    );
    lot.set(refRdv, etape, SetOptions(merge: true));
    await lot.commit();

    return FirebaseRefs.versMap(await ref.get());
  });

  @override
  Future<void> supprimerRendezVous(String id) =>
      _garde(() => _c('rendezvous').doc(id).delete());

  // -----------------------------------------------------------------
  //  Salle d'attente
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> salleAttente({
    String? profileId,
    bool toutes = false,
  }) => _garde(() async {
    final q = await _portee('salle_attente', profileId);
    return _fileDuJour(FirebaseRefs.versListe(await q.get()), toutes: toutes);
  });

  @override
  Stream<List<Map<String, dynamic>>> salleAttenteFlux({String? profileId}) =>
      _porteeFlux(
        'salle_attente',
        profileId,
      ).map((s) => _fileDuJour(FirebaseRefs.versListe(s)));

  /// La file du jour : les entrées ouvertes, plus celles closes aujourd'hui.
  ///
  /// Les entrées closes du jour comptent : le tableau de bord affiche
  /// « Historique du jour » à côté de la file en cours. Ne garder que les
  /// entrées ouvertes viderait cette colonne, et un patient déjà reçu
  /// disparaîtrait de l'écran au moment où on le clôture.
  ///
  /// Le filtre porte sur `closedAt` et non sur l'étape : c'est le champ que
  /// la clôture pose, et le seul qui distingue sûrement une visite finie
  /// d'une visite en cours.
  static List<Map<String, dynamic>> _fileDuJour(
    List<Map<String, dynamic>> liste, {
    bool toutes = false,
  }) {
    final debut = DateTime.now();
    final minuit = DateTime(debut.year, debut.month, debut.day);

    final gardees = toutes
        ? [...liste]
        : liste.where((e) {
            final close = asDateOrNull(e['closedAt']);
            if (close != null) return !close.isBefore(minuit);
            return !_termineeSansCloture(e, debut);
          }).toList();

    DateTime cle(Map<String, dynamic> m) =>
        DateTime.tryParse('${m['createdAt']}') ?? DateTime(1970);
    // Décroissant, comme le backend Node : c'est l'ordre contre lequel les
    // écrans ont été construits.
    gardees.sort((a, b) => cle(b).compareTo(cle(a)));
    return gardees;
  }

  /// Une entrée sans `closedAt` mais qu'il ne faut plus traiter comme en
  /// cours.
  ///
  /// L'ancienne version en a laissé dans les données migrées : des lignes
  /// marquées terminées ou annulées sans date de clôture, et des lignes
  /// jamais clôturées. Elle les masquait (statut, ou plus de 24 h
  /// d'ancienneté) ; sans cette règle elles reviendraient dans la file du
  /// jour et bloqueraient le patient comme « déjà en salle d'attente ».
  static bool _termineeSansCloture(
    Map<String, dynamic> e,
    DateTime maintenant,
  ) {
    final statut = '${e['status'] ?? ''}'.toLowerCase();
    if (const {'done', 'closed', 'cancelled', 'canceled'}.contains(statut)) {
      return true;
    }
    final creee = asDateOrNull(e['createdAt']);
    return creee != null &&
        maintenant.difference(creee) > const Duration(hours: 24);
  }

  /// L'entrée encore ouverte d'un patient, s'il en a une.
  ///
  /// Le filtre sur `closedAt` se fait en mémoire : un `where` composé avec
  /// celui sur `patientId` demanderait un index, et une file de cabinet
  /// tient dans quelques dizaines de lignes.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _ligneOuverte(
    String patientId,
  ) async {
    final s = await _c(
      'salle_attente',
    ).where('patientId', isEqualTo: patientId).get();
    final maintenant = DateTime.now();
    for (final d in s.docs) {
      final e = d.data();
      if (e['closedAt'] == null && !_termineeSansCloture(e, maintenant)) {
        return d;
      }
    }
    return null;
  }

  /// Les champs d'une ligne de file.
  ///
  /// Les noms du patient et du médecin y sont recopiés : la file les
  /// affiche sans charger chaque dossier, ce qui reste vrai avec trente
  /// personnes en attente.
  static Map<String, dynamic> _ligneFile({
    required Map<String, dynamic> patient,
    required String patientId,
    required String? rdvId,
    required String motif,
    required Timestamp maintenant,
  }) => {
    'parentUid': FirebaseRefs.cabinetId,
    'patientId': patientId,
    'doctorId': patient['doctorId'],
    'assistantId': patient['assistantId'],
    'rdvId': rdvId,
    'patientNom': patient['nom'] ?? '',
    'patientPrenom': patient['prenom'] ?? '',
    'doctorName': patient['assignedMedecinName'] ?? '',
    'assistantName': patient['assistantName'] ?? '',
    'motif': motif.isNotEmpty ? motif : (patient['motif'] ?? ''),
    'nombreSeances': patient['nombreSeances'],
    'seancesEffectuees': patient['seancesEffectuees'],
    'etape': 'arrive',
    'status': 'waiting',
    'createdAt': maintenant,
    'closedAt': null,
  };

  @override
  Future<Map<String, dynamic>> mettreEnSalle({
    required String patientId,
    String? rdvId,
    String motif = '',
  }) => _garde(() async {
    final p = await _c('patients').doc(patientId).get();
    if (!p.exists) {
      throw const ApiException(message: 'Patient introuvable', code: 404);
    }

    // Un même patient ne peut pas figurer deux fois dans la file : deux
    // lignes pour la même personne feraient décompter deux séances.
    //
    // Un conflit, et non l'entrée existante rendue en silence : l'écran
    // distingue les deux, et annoncer « patient ajouté » alors qu'il y
    // était déjà ferait croire à une seconde visite.
    final dejaLa = await _ligneOuverte(patientId);
    if (dejaLa != null) {
      throw const ApiException(
        message: 'Ce patient est déjà dans la file',
        code: 409,
      );
    }

    final ref = _c('salle_attente').doc();
    await ref.set(
      _ligneFile(
        patient: FirebaseRefs.versMap(p),
        patientId: patientId,
        rdvId: rdvId,
        motif: motif,
        maintenant: Timestamp.now(),
      ),
    );
    return FirebaseRefs.versMap(await ref.get());
  });

  @override
  Future<Map<String, dynamic>> demarrerConsultation(String waitingId) =>
      _garde(() async {
        final maintenant = Timestamp.now();
        final ref = _c('salle_attente').doc(waitingId);
        await ref.set({
          'etape': 'en_cours',
          // L'ancien vocabulaire reste écrit : les entrées existantes ne
          // portent que `status`, et cesser de l'écrire rendrait illisible
          // la file en cours au moment de la bascule.
          'status': 'in_consultation',
          'inConsultationAt': maintenant,
          // Rouvre l'entrée : une consultation relancée après une clôture
          // garderait sinon sa date de fermeture, et disparaîtrait de la
          // file en cours tout en s'affichant « en consultation ».
          'closedAt': null,
        }, SetOptions(merge: true));
        return FirebaseRefs.versMap(await ref.get());
      });

  /// Clôt la visite : sort le patient, décompte la séance, facture.
  ///
  /// Tout passe par une transaction parce que le décompte de séance et la
  /// facturation ne doivent avoir lieu qu'une fois. Une entrée déjà close
  /// ressort sans rien écrire — le double clic sur « Terminer » ne
  /// refacture pas une seconde consultation.
  @override
  Future<void> cloturerConsultation(
    String waitingId, {
    bool decompterSeance = true,
    double? prixSeance,
  }) => _garde(() async {
    final refEntree = _c('salle_attente').doc(waitingId);

    await FirebaseRefs.base.runTransaction((tx) async {
      final snap = await tx.get(refEntree);
      if (!snap.exists) {
        throw const ApiException(message: 'Entrée introuvable', code: 404);
      }
      final entree = snap.data()!;
      if (entree['closedAt'] != null) return; // Déjà close : rien à refaire.

      final maintenant = Timestamp.now();
      final refPatient = _c('patients').doc('${entree['patientId']}');

      tx.update(refEntree, {
        'etape': 'honore',
        'status': 'done',
        'closedAt': maintenant,
      });

      final majPatient = <String, dynamic>{};
      if (decompterSeance) {
        majPatient['seancesEffectuees'] = FieldValue.increment(1);
      }
      // Le montant vient de l'appel, pas du tarif enregistré : le médecin
      // peut l'avoir ajusté pour cette visite — un contrôle ne coûte pas le
      // prix d'une première consultation.
      if (prixSeance != null && prixSeance > 0) {
        majPatient['prix'] = FieldValue.increment(prixSeance);
      }
      if (majPatient.isNotEmpty) tx.update(refPatient, majPatient);

      // Referme le rendez-vous d'où vient la visite. Sans ce retour, un
      // rendez-vous honoré resterait affiché « à venir » indéfiniment.
      final rdvId = entree['rdvId'];
      if (rdvId != null && '$rdvId'.isNotEmpty) {
        tx.set(_c('rendezvous').doc('$rdvId'), {
          'etape': 'honore',
          'etapesAt': {'honore': maintenant},
          'updatedAt': maintenant,
        }, SetOptions(merge: true));
      }
    });
  });

  // -----------------------------------------------------------------
  //  Achats et statistiques
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> achats({String? dayKey}) =>
      _garde(() async {
        Query<Map<String, dynamic>> q = _c('purchases');
        if (dayKey != null) q = q.where('dayKey', isEqualTo: dayKey);
        return _parDateDesc(FirebaseRefs.versListe(await q.get()));
      });

  @override
  Stream<List<Map<String, dynamic>>> achatsFlux() => _c(
    'purchases',
  ).snapshots().map((s) => _parDateDesc(FirebaseRefs.versListe(s)));

  @override
  Future<Map<String, dynamic>> creerAchat(Map<String, dynamic> champs) =>
      _garde(() async {
        final maintenant = DateTime.now();
        final horodatage = Timestamp.fromDate(maintenant);
        final jour = '${champs['dayKey'] ?? FirebaseRefs.dayKey(maintenant)}';
        final montant = (champs['montant'] as num?)?.toDouble() ?? 0;

        final ref = _c('purchases').doc();
        final lot = FirebaseRefs.base.batch();

        lot.set(ref, {
          ...FirebaseRefs.versFirestore(champs),
          'parentUid': FirebaseRefs.cabinetId,
          'montant': montant,
          'dayKey': jour,
          'createdAt': horodatage,
        });

        // Le résultat net du jour se lit sans reparcourir les achats.
        lot.set(_c('daily_stats').doc(jour), {
          'parentUid': FirebaseRefs.cabinetId,
          'dayKey': jour,
          'date': horodatage,
          'achatsTotal': FieldValue.increment(montant),
          'achatsCount': FieldValue.increment(1),
          'updatedAt': horodatage,
        }, SetOptions(merge: true));

        await lot.commit();
        return FirebaseRefs.versMap(await ref.get());
      });

  @override
  Future<void> supprimerAchat(String id) => _garde(() async {
    final ref = _c('purchases').doc(id);
    final snap = await ref.get();
    if (!snap.exists) return;

    final achat = snap.data()!;
    final montant = (achat['montant'] as num?)?.toDouble() ?? 0;
    final jour = '${achat['dayKey'] ?? ''}';

    final lot = FirebaseRefs.base.batch();
    lot.delete(ref);
    if (jour.isNotEmpty) {
      // Décrémenter, et non recalculer : le total doit redescendre du
      // montant retiré, même si d'autres postes écrivent en même temps.
      //
      // `dayKey` et `parentUid` sont réécrits bien que le document existe
      // déjà : si l'achat supprimé était le seul de sa journée et que la
      // statistique avait été purgée, le `merge` la recréerait sans eux, et
      // un document sans `dayKey` échappe aux requêtes par intervalle — la
      // journée disparaîtrait des écrans financiers.
      lot.set(_c('daily_stats').doc(jour), {
        'parentUid': FirebaseRefs.cabinetId,
        'dayKey': jour,
        'achatsTotal': FieldValue.increment(-montant),
        'achatsCount': FieldValue.increment(-1),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
    await lot.commit();
  });

  @override
  Future<List<Map<String, dynamic>>> statsJournalieres({
    String? depuis,
    String? jusqua,
  }) => _garde(() async {
    Query<Map<String, dynamic>> q = _c('daily_stats');
    // Sur le champ `dayKey`, et non sur l'identifiant du document, bien que
    // les deux portent la même valeur : une comparaison sur `documentId`
    // porte en réalité sur le *chemin* du document, ce qui ne se compare
    // pas comme la chaîne qu'on croit écrire. Le champ est sans surprise,
    // et son index est automatique.
    //
    // Le format `YYYY-MM-DD` fait le reste : l'ordre alphabétique y est
    // l'ordre chronologique.
    if (depuis != null) {
      q = q.where('dayKey', isGreaterThanOrEqualTo: depuis);
    }
    if (jusqua != null) {
      q = q.where('dayKey', isLessThanOrEqualTo: jusqua);
    }
    final liste = FirebaseRefs.versListe(await q.get());
    liste.sort((a, b) => '${b['dayKey']}'.compareTo('${a['dayKey']}'));
    return liste;
  });

  @override
  Stream<List<Map<String, dynamic>>> statsFlux({String? depuis}) {
    Query<Map<String, dynamic>> q = _c('daily_stats');
    if (depuis != null) {
      q = q.where('dayKey', isGreaterThanOrEqualTo: depuis);
    }
    return q.snapshots().map((s) {
      final liste = FirebaseRefs.versListe(s);
      liste.sort((a, b) => '${b['dayKey']}'.compareTo('${a['dayKey']}'));
      return liste;
    });
  }

  // -----------------------------------------------------------------
  //  Journal d'erreurs
  // -----------------------------------------------------------------

  @override
  Future<void> signalerErreur(Map<String, dynamic> champs) async {
    try {
      await FirebaseRefs.base.collection('errors').add({
        ...FirebaseRefs.versFirestore(champs),
        'parentUid': FirebaseRefs.cabinetId,
        'createdAt': Timestamp.now(),
      });
    } catch (_) {
      // Silence volontaire : signaler une erreur ne doit pas en créer une
      // seconde, et le journal n'est pas ce qui fait tourner le cabinet.
    }
  }
}

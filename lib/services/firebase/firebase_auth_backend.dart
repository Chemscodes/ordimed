import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../api_client.dart';
import '../auth_backend.dart';
import 'firebase_refs.dart';

/// L'ouverture de session contre Firebase Auth.
///
/// Beaucoup plus court que son équivalent Node, parce que Firebase fait
/// seul ce qu'il fallait écrire à la main : la persistance de session, le
/// renouvellement du jeton, et la notification quand l'état change.
///
/// Les échecs sont traduits en [ApiException] — la même que lève le
/// backend Node. Sans cette traduction, les écrans de connexion devraient
/// connaître les deux vocabulaires d'erreur, et un médecin lirait
/// « [firebase_auth/invalid-credential] ».
class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend._();

  static final FirebaseAuthBackend instance = FirebaseAuthBackend._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  String? get cabinetId => _auth.currentUser?.uid;

  @override
  Stream<String?> sessionChanges() async* {
    // `authStateChanges()` émet l'état courant, mais de façon asynchrone :
    // un écran branché juste après le démarrage verrait un cadre vide avant
    // la première émission. Le rendu immédiat évite ce clignotement.
    yield cabinetId;
    yield* _auth.authStateChanges().map((u) => u?.uid);
  }

  /// Firebase rouvre la session tout seul ; il n'y a qu'à lire le résultat.
  ///
  /// Le document du cabinet est vérifié au passage : un compte Auth qui
  /// n'en a pas vient d'une inscription interrompue entre les deux
  /// écritures, et l'app s'ouvrirait sur un cabinet sans horaires ni profil.
  @override
  Future<String?> restaurer() async {
    final uid = cabinetId;
    if (uid == null) return null;
    try {
      final doc = await FirebaseRefs.cabinetDoc(uid).get();
      if (!doc.exists) {
        await _initialiserCabinet(uid, _auth.currentUser?.email ?? '');
      }
      return uid;
    } on FirebaseException {
      // Hors ligne, rules non déployées, ou toute autre erreur Firestore :
      // la session Auth reste valable, on entre quand même. L'écran suivant
      // affichera l'erreur précise si la base ne répond pas.
      return uid;
    }
  }

  @override
  Future<String> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      // Un cabinet créé sur un autre poste, ou une inscription interrompue :
      // dans les deux cas il faut que le document existe avant d'entrer.
      final doc = await FirebaseRefs.cabinetDoc(uid).get();
      if (!doc.exists) await _initialiserCabinet(uid, email);
      return uid;
    } on FirebaseAuthException catch (e) {
      throw _traduire(e);
    }
  }

  @override
  Future<String> signUp(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await _initialiserCabinet(uid, email);
      return uid;
    } on FirebaseAuthException catch (e) {
      throw _traduire(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Le cabinet et son médecin principal, écrits ensemble.
  ///
  /// Un cabinet sans profil est inutilisable : le sélecteur de profils
  /// s'ouvrirait vide et personne ne pourrait entrer. Le lot garantit que
  /// les deux arrivent, ou aucun.
  Future<void> _initialiserCabinet(String uid, String email) async {
    final base = FirebaseFirestore.instance;
    final lot = base.batch();
    final maintenant = DateTime.now();

    lot.set(FirebaseRefs.cabinetDoc(uid), {
      'email': email.trim().toLowerCase(),
      'horaires': {
        // Minutes depuis minuit, comme dans lib/core/creneaux.dart.
        'ouverture': 8 * 60,
        'fermeture': 17 * 60,
        'pauseDebut': 12 * 60,
        'pauseFin': 13 * 60,
        'duree': 20,
        // Samedi à jeudi : la semaine algérienne, le repos est le vendredi.
        'joursOuvres': [6, 7, 1, 2, 3, 4],
      },
      'motifsPredefinis': <String>[],
      'motifPrototypes': <String, dynamic>{},
      'listesReference': <String, dynamic>{},
      'createdAt': Timestamp.fromDate(maintenant),
    }, SetOptions(merge: true));

    lot.set(FirebaseRefs.col(uid, 'profiles').doc(), {
      'parentUid': uid,
      'name': 'Médecin principal',
      'role': 'medecin_principal',
      // Code par défaut `0000`, comme le fait le backend Node à
      // l'inscription. Un profil sans code du tout laisserait le poste
      // s'ouvrir sur n'importe quelle saisie ; le médecin choisit le sien
      // depuis ses réglages.
      'pinHash': FirebaseRefs.hacherPin('0000'),
      'wilaya': '',
      'address': '',
      'tel': '',
      'nameAr': '',
      'subtitle': '',
      'ordonnanceCounter': 0,
      'whatsappTemplate': '',
      'createdAt': Timestamp.fromDate(maintenant),
    });

    await lot.commit();
  }

  /// Traduit un échec Firebase dans le vocabulaire du reste de l'app.
  ///
  /// Les codes sont ramenés aux codes HTTP qu'aurait rendus le backend Node,
  /// pour que `estAuth` et `estReseau` gardent leur sens de part et d'autre.
  ApiException _traduire(FirebaseAuthException e) => switch (e.code) {
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => const ApiException(
      message: 'E-mail ou mot de passe incorrect',
      code: 401,
    ),
    'invalid-email' => const ApiException(
      message: 'Adresse e-mail invalide',
      code: 400,
    ),
    'email-already-in-use' => const ApiException(
      message: 'Un cabinet existe déjà avec cette adresse',
      code: 409,
    ),
    'weak-password' => const ApiException(
      message: 'Mot de passe trop court — six caractères au minimum',
      code: 400,
    ),
    'too-many-requests' => const ApiException(
      message: 'Trop de tentatives. Réessaie dans quelques minutes.',
      code: 429,
    ),
    'network-request-failed' => const ApiException(
      message: 'Pas de connexion Internet',
      // `code: 0` fait passer `estReseau` à vrai : l'app sait alors que
      // c'est le réseau qui manque, pas les identifiants.
      code: 0,
    ),
    _ => ApiException(message: e.message ?? 'Connexion impossible', code: 400),
  };
}

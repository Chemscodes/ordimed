import 'api_client.dart';
import 'realtime_service.dart';

/// Les appels au backend, entité par entité.
///
/// Remplace `firestore_service.dart`. Deux formes coexistent, exprès :
///
/// - `Future` pour les écritures ;
/// - `Stream` pour les lectures affichées, via
///   [RealtimeService.fluxRafraichi], qui rend aux écrans la forme que
///   `snapshots()` leur donnait.
///
/// Les méthodes renvoient des `Map<String, dynamic>` plutôt que des classes
/// typées, et ce n'est pas de la paresse : les écrans lisent aujourd'hui des
/// `data['nom']` de documents Firestore. Garder la même forme permet de
/// migrer un écran à la fois. Le typage viendra une fois Firebase parti.
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  final _api = ApiClient.instance;
  final _rt = RealtimeService.instance;

  static List<Map<String, dynamic>> _liste(dynamic brut) =>
      (brut as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, dynamic> _objet(dynamic brut) =>
      Map<String, dynamic>.from(brut as Map);

  // -----------------------------------------------------------------
  //  Authentification
  // -----------------------------------------------------------------

  /// Remplace `createUserWithEmailAndPassword`.
  ///
  /// Le backend crée le cabinet *et* son médecin principal : les deux
  /// allaient ensemble dans `signup_page.dart`, et un cabinet sans profil
  /// est inutilisable — on ne peut même pas s'y connecter.
  Future<Map<String, dynamic>> inscrire(String email, String motDePasse) async {
    final r = _objet(
      await _api.post('/auth/register', {
        'email': email,
        'password': motDePasse,
      }),
    );
    await _apresConnexion(r);
    return r;
  }

  Future<Map<String, dynamic>> connecter(
    String email,
    String motDePasse,
  ) async {
    final r = _objet(
      await _api.post('/auth/login', {'email': email, 'password': motDePasse}),
    );
    await _apresConnexion(r);
    return r;
  }

  Future<void> _apresConnexion(Map<String, dynamic> reponse) async {
    await _api.memoriserJeton(reponse['token'].toString());
    // Le temps réel n'a de sens qu'authentifié : le salon est déduit du
    // jeton, pas demandé par le client.
    _rt.connecter();
  }

  Future<void> deconnecter() async {
    _rt.deconnecter();
    await _api.deconnecter();
  }

  /// Vérifie le PIN d'un profil.
  ///
  /// Était une comparaison de chaînes dans l'app, sur une valeur stockée en
  /// clair. Le PIN ne quitte plus jamais le serveur.
  Future<Map<String, dynamic>> verifierPin(String profileId, String pin) async {
    final r = _objet(
      await _api.post('/auth/pin', {'profileId': profileId, 'pin': pin}),
    );
    return _objet(r['profile']);
  }

  Future<Map<String, dynamic>> cabinet() async =>
      _objet(await _api.get('/auth/me'));

  /// Reglages du cabinet : horaires, motifs predefinis.
  Future<Map<String, dynamic>> majCabinet(Map<String, dynamic> champs) async =>
      _objet(await _api.put('/auth/cabinet', champs));

  Future<void> majHoraires(Map<String, dynamic> horaires) =>
      majCabinet({'horaires': horaires});

  // -----------------------------------------------------------------
  //  Profils
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> profils() async =>
      _liste(await _api.get('/profiles'));

  Stream<List<Map<String, dynamic>>> profilsFlux() => _rt.fluxRafraichi(
    charger: profils,
    entites: const ['comptes'],
  );

  Future<Map<String, dynamic>> creerProfil({
    required String name,
    required String role,
    required String pin,
  }) async => _objet(
    await _api.post('/profiles', {'name': name, 'role': role, 'pin': pin}),
  );

  Future<Map<String, dynamic>> majProfil(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/profiles/$id', champs));

  Future<void> supprimerProfil(String id) => _api.delete('/profiles/$id');

  // -----------------------------------------------------------------
  //  Patients
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> patients({
    String? profileId,
    bool inclureSupprimes = false,
  }) async => _liste(
    await _api.get('/patients', params: {
      if (profileId != null) 'profileId': profileId,
      if (inclureSupprimes) 'inclureSupprimes': '1',
    }),
  );

  Stream<List<Map<String, dynamic>>> patientsFlux({String? profileId}) =>
      _rt.fluxRafraichi(
        charger: () => patients(profileId: profileId),
        entites: const ['patients'],
      );

  Future<Map<String, dynamic>> patient(String id) async =>
      _objet(await _api.get('/patients/$id'));

  /// Le dossier et tout ce qui pend dessous, en une requête.
  Future<Map<String, dynamic>> dossier(String id) async =>
      _objet(await _api.get('/patients/$id/detail'));

  /// Se recharge aussi quand un document ou un versement bouge : la page du
  /// dossier affiche les trois ensemble.
  Stream<Map<String, dynamic>> dossierFlux(String id) => _rt.fluxRafraichi(
    charger: () => dossier(id),
    entites: const ['patients', 'forms', 'versements'],
  );

  Future<Map<String, dynamic>> creerPatient(Map<String, dynamic> champs) async =>
      _objet(await _api.post('/patients', champs));

  Future<Map<String, dynamic>> majPatient(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/patients/$id', champs));

  /// Suppression douce : le dossier reste, ses versements aussi.
  Future<void> supprimerPatient(String id) => _api.delete('/patients/$id');

  Future<void> restaurerPatient(String id) =>
      _api.post('/patients/$id/restaurer');

  // -----------------------------------------------------------------
  //  Documents
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> documents({
    String? patientId,
    String? type,
    DateTime? jour,
  }) async => _liste(
    await _api.get('/forms', params: {
      if (patientId != null) 'patientId': patientId,
      if (type != null) 'type': type,
      if (jour != null) 'jour': jour.toIso8601String(),
    }),
  );

  Stream<List<Map<String, dynamic>>> documentsFlux({String? patientId}) =>
      _rt.fluxRafraichi(
        charger: () => documents(patientId: patientId),
        entites: const ['forms'],
      );

  Future<Map<String, dynamic>> creerDocument(
    Map<String, dynamic> champs,
  ) async => _objet(await _api.post('/forms', champs));

  /// Modifie un document existant.
  ///
  /// Le type n'est pas modifiable : il decide de la mise en page et de ce que
  /// la consultation considere comme redige aujourd'hui.
  Future<Map<String, dynamic>> majDocument(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/forms/$id', champs));

  Future<void> supprimerDocument(String id) => _api.delete('/forms/$id');

  // -----------------------------------------------------------------
  //  Versements
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> versements({String? patientId}) async =>
      _liste(
        await _api.get('/versements', params: {
          if (patientId != null) 'patientId': patientId,
        }),
      );

  Future<Map<String, dynamic>> encaisser({
    required String patientId,
    required double montant,
    String? auteurProfileId,
  }) async => _objet(
    await _api.post('/versements', {
      'patientId': patientId,
      'montant': montant,
      if (auteurProfileId != null) 'auteurProfileId': auteurProfileId,
    }),
  );

  // -----------------------------------------------------------------
  //  Rendez-vous
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> rendezVous({
    String? profileId,
    DateTime? jour,
    DateTime? depuis,
    int? limit,
  }) async => _liste(
    await _api.get('/rendezvous', params: {
      if (profileId != null) 'profileId': profileId,
      if (jour != null) 'jour': jour.toIso8601String(),
      if (depuis != null) 'depuis': depuis.toIso8601String(),
      if (limit != null) 'limit': limit,
    }),
  );

  Stream<List<Map<String, dynamic>>> rendezVousFlux({
    String? profileId,
    DateTime? jour,
  }) => _rt.fluxRafraichi(
    charger: () => rendezVous(profileId: profileId, jour: jour),
    entites: const ['rendezvous'],
  );

  /// Planifie un rendez-vous.
  ///
  /// Lève une [ApiException] avec `estConflit` si le créneau vient d'être
  /// pris. Le contrôle existe aussi côté Flutter, mais il ne suffit plus :
  /// deux postes peuvent poser la même heure à la même seconde.
  Future<Map<String, dynamic>> planifier(Map<String, dynamic> champs) async =>
      _objet(await _api.post('/rendezvous', champs));

  Future<Map<String, dynamic>> majRendezVous(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/rendezvous/$id', champs));

  Future<Map<String, dynamic>> changerEtapeRdv(
    String id,
    String etape, {
    String? motifAnnulation,
  }) async => _objet(
    await _api.post('/rendezvous/$id/etape', {
      'etape': etape,
      if (motifAnnulation != null) 'motifAnnulation': motifAnnulation,
    }),
  );

  /// Le patient se présente : crée l'entrée en salle **et** marque le
  /// rendez-vous. Les deux étaient indissociables.
  Future<Map<String, dynamic>> marquerArrive(String rdvId) async =>
      _objet(await _api.post('/rendezvous/$rdvId/arrive'));

  Future<void> supprimerRendezVous(String id) =>
      _api.delete('/rendezvous/$id');

  // -----------------------------------------------------------------
  //  Salle d'attente
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> salleAttente({
    String? profileId,
    bool toutes = false,
  }) async => _liste(
    await _api.get('/waiting', params: {
      if (profileId != null) 'profileId': profileId,
      if (toutes) 'toutes': '1',
    }),
  );

  /// L'écran le plus partagé du cabinet : il doit bouger seul.
  Stream<List<Map<String, dynamic>>> salleAttenteFlux({String? profileId}) =>
      _rt.fluxRafraichi(
        charger: () => salleAttente(profileId: profileId),
        entites: const ['salle_attente'],
      );

  Future<Map<String, dynamic>> mettreEnSalle({
    required String patientId,
    String? rdvId,
    String motif = '',
  }) async => _objet(
    await _api.post('/waiting', {
      'patientId': patientId,
      if (rdvId != null) 'rdvId': rdvId,
      if (motif.isNotEmpty) 'motif': motif,
    }),
  );

  Future<Map<String, dynamic>> demarrerConsultation(String waitingId) async =>
      _objet(await _api.post('/waiting/$waitingId/demarrer'));

  /// Décompte la séance, sort le patient, marque le rendez-vous honoré.
  Future<void> cloturerConsultation(
    String waitingId, {
    bool decompterSeance = true,
  }) => _api.post('/waiting/$waitingId/cloturer', {
    'decompterSeance': decompterSeance,
  });

  // -----------------------------------------------------------------
  //  Achats et statistiques
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> achats({String? dayKey}) async => _liste(
    await _api.get('/purchases', params: {if (dayKey != null) 'dayKey': dayKey}),
  );

  Stream<List<Map<String, dynamic>>> achatsFlux() => _rt.fluxRafraichi(
    charger: achats,
    entites: const ['purchases'],
  );

  Future<Map<String, dynamic>> creerAchat(Map<String, dynamic> champs) async =>
      _objet(await _api.post('/purchases', champs));

  Future<void> supprimerAchat(String id) => _api.delete('/purchases/$id');

  Future<List<Map<String, dynamic>>> statsJournalieres({
    String? depuis,
    String? jusqua,
  }) async => _liste(
    await _api.get('/stats/daily', params: {
      if (depuis != null) 'depuis': depuis,
      if (jusqua != null) 'jusqua': jusqua,
    }),
  );

  Stream<List<Map<String, dynamic>>> statsFlux({String? depuis}) =>
      _rt.fluxRafraichi(
        charger: () => statsJournalieres(depuis: depuis),
        // Les statistiques bougent quand l'argent bouge.
        entites: const ['versements', 'purchases'],
      );

  // -----------------------------------------------------------------
  //  Journal d'erreurs
  // -----------------------------------------------------------------

  /// N'échoue jamais bruyamment : signaler une erreur ne doit pas en créer
  /// une seconde.
  Future<void> signalerErreur(Map<String, dynamic> champs) async {
    try {
      await _api.post('/errors', champs);
    } catch (_) {
      // Silence volontaire.
    }
  }
}

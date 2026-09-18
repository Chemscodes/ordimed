import '../api_client.dart';
import '../cabinet_backend.dart';
import '../realtime_service.dart';

/// Le cabinet stocké dans MongoDB, derrière le backend Node.
///
/// C'est l'implémentation historique : la logique métier — transactions,
/// conflits de créneaux, incréments de caisse — vit sur le serveur, et
/// l'app ne fait qu'appeler. Tout ce qui est délicat se règle en un aller
/// simple, ce qui est le principal avantage de cette branche.
///
/// Les lectures affichées passent par [RealtimeService.fluxRafraichi] :
/// le serveur signale qu'une entité a bougé, l'app redemande. Un
/// aller-retour de plus que Firestore, invisible sur un réseau local.
class MongoCabinetBackend implements CabinetBackend {
  MongoCabinetBackend._();

  static final MongoCabinetBackend instance = MongoCabinetBackend._();

  final _api = ApiClient.instance;
  final _rt = RealtimeService.instance;

  static List<Map<String, dynamic>> _liste(dynamic brut) =>
      (brut as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, dynamic> _objet(dynamic brut) =>
      Map<String, dynamic>.from(brut as Map);

  // -----------------------------------------------------------------
  //  Le cabinet
  // -----------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> cabinet() async =>
      _objet(await _api.get('/auth/me'));

  @override
  Future<Map<String, dynamic>> majCabinet(Map<String, dynamic> champs) async =>
      _objet(await _api.put('/auth/cabinet', champs));

  @override
  Future<void> majHoraires(Map<String, dynamic> horaires) =>
      majCabinet({'horaires': horaires});

  @override
  Future<void> ajouterListe(String liste, Iterable<String> valeurs) =>
      _api.post('/auth/cabinet/liste', {
        'liste': liste,
        'valeurs': valeurs.toList(),
      });

  // -----------------------------------------------------------------
  //  Profils
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> profils() async =>
      _liste(await _api.get('/profiles'));

  @override
  Stream<List<Map<String, dynamic>>> profilsFlux() =>
      _rt.fluxRafraichi(charger: profils, entites: const ['comptes']);

  @override
  Future<Map<String, dynamic>> creerProfil({
    required String name,
    required String role,
    required String pin,
  }) async => _objet(
    await _api.post('/profiles', {'name': name, 'role': role, 'pin': pin}),
  );

  @override
  Future<Map<String, dynamic>> majProfil(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/profiles/$id', champs));

  @override
  Future<void> supprimerProfil(String id) => _api.delete('/profiles/$id');

  /// Le PIN était comparé dans l'app, sur une valeur stockée en clair.
  /// Il ne quitte plus jamais le serveur.
  @override
  Future<Map<String, dynamic>> verifierPin(String profileId, String pin) async {
    final r = _objet(
      await _api.post('/auth/pin', {'profileId': profileId, 'pin': pin}),
    );
    return _objet(r['profile']);
  }

  // -----------------------------------------------------------------
  //  Patients
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> patients({
    String? profileId,
    bool inclureSupprimes = false,
  }) async => _liste(
    await _api.get(
      '/patients',
      params: {
        if (profileId != null) 'profileId': profileId,
        if (inclureSupprimes) 'inclureSupprimes': '1',
      },
    ),
  );

  @override
  Stream<List<Map<String, dynamic>>> patientsFlux({String? profileId}) =>
      _rt.fluxRafraichi(
        charger: () => patients(profileId: profileId),
        entites: const ['patients'],
      );

  /// Le filtre se fait ici, après lecture : l'API `/patients` ne connaît pas
  /// de paramètre de date, et ce backend n'est pas celui visé par
  /// l'optimisation (facturation au document, propre à Firestore) — le
  /// filtrage en mémoire donne la même liste sans exiger un endpoint de
  /// plus à maintenir côté serveur.
  @override
  Stream<List<Map<String, dynamic>>> patientsRecentsFlux({
    String? profileId,
    required DateTime depuis,
  }) => patientsFlux(profileId: profileId).map(
    (liste) => liste.where((p) {
      final d = DateTime.tryParse('${p['createdAt']}');
      return d != null && !d.isBefore(depuis);
    }).toList(),
  );

  @override
  Future<Map<String, dynamic>> patient(String id) async =>
      _objet(await _api.get('/patients/$id'));

  @override
  Future<Map<String, dynamic>> dossier(String id) async =>
      _objet(await _api.get('/patients/$id/detail'));

  /// Se recharge aussi quand un document ou un versement bouge : la page du
  /// dossier affiche les trois ensemble.
  @override
  Stream<Map<String, dynamic>> dossierFlux(String id) => _rt.fluxRafraichi(
    charger: () => dossier(id),
    entites: const ['patients', 'forms', 'versements'],
  );

  @override
  Stream<Map<String, dynamic>> patientDocFlux(String id) => _rt.fluxRafraichi(
    charger: () => patient(id),
    entites: const ['patients'],
  );

  @override
  Future<Map<String, dynamic>> creerPatient(
    Map<String, dynamic> champs,
  ) async => _objet(await _api.post('/patients', champs));

  @override
  Future<Map<String, dynamic>> majPatient(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/patients/$id', champs));

  @override
  Future<void> supprimerPatient(String id) => _api.delete('/patients/$id');

  @override
  Future<void> restaurerPatient(String id) =>
      _api.post('/patients/$id/restaurer');

  // -----------------------------------------------------------------
  //  Documents
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> documents({
    String? patientId,
    String? type,
    DateTime? jour,
  }) async => _liste(
    await _api.get(
      '/forms',
      params: {
        if (patientId != null) 'patientId': patientId,
        if (type != null) 'type': type,
        if (jour != null) 'jour': jour.toIso8601String(),
      },
    ),
  );

  @override
  Stream<List<Map<String, dynamic>>> documentsFlux({String? patientId}) =>
      _rt.fluxRafraichi(
        charger: () => documents(patientId: patientId),
        entites: const ['forms'],
      );

  @override
  Future<Map<String, dynamic>> creerDocument(
    Map<String, dynamic> champs,
  ) async => _objet(await _api.post('/forms', champs));

  @override
  Future<Map<String, dynamic>> majDocument(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/forms/$id', champs));

  @override
  Future<void> supprimerDocument(String id) => _api.delete('/forms/$id');

  // -----------------------------------------------------------------
  //  Versements
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> versements({String? patientId}) async =>
      _liste(
        await _api.get(
          '/versements',
          params: {if (patientId != null) 'patientId': patientId},
        ),
      );

  @override
  Stream<List<Map<String, dynamic>>> versementsFlux({String? patientId}) =>
      _rt.fluxRafraichi(
        charger: () => versements(patientId: patientId),
        entites: const ['versements'],
      );

  @override
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

  @override
  Future<List<Map<String, dynamic>>> rendezVous({
    String? profileId,
    DateTime? jour,
    DateTime? depuis,
    int? limit,
  }) async => _liste(
    await _api.get(
      '/rendezvous',
      params: {
        if (profileId != null) 'profileId': profileId,
        if (jour != null) 'jour': jour.toIso8601String(),
        if (depuis != null) 'depuis': depuis.toIso8601String(),
        if (limit != null) 'limit': limit,
      },
    ),
  );

  @override
  Stream<List<Map<String, dynamic>>> rendezVousFlux({
    String? profileId,
    DateTime? jour,
  }) => _rt.fluxRafraichi(
    charger: () => rendezVous(profileId: profileId, jour: jour),
    entites: const ['rendezvous'],
  );

  @override
  Future<Map<String, dynamic>> planifier(Map<String, dynamic> champs) async =>
      _objet(await _api.post('/rendezvous', champs));

  @override
  Future<Map<String, dynamic>> majRendezVous(
    String id,
    Map<String, dynamic> champs,
  ) async => _objet(await _api.put('/rendezvous/$id', champs));

  @override
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

  @override
  Future<Map<String, dynamic>> marquerArrive(String rdvId) async =>
      _objet(await _api.post('/rendezvous/$rdvId/arrive'));

  @override
  Future<void> supprimerRendezVous(String id) => _api.delete('/rendezvous/$id');

  // -----------------------------------------------------------------
  //  Salle d'attente
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> salleAttente({
    String? profileId,
    bool toutes = false,
  }) async => _liste(
    await _api.get(
      '/waiting',
      params: {
        if (profileId != null) 'profileId': profileId,
        if (toutes) 'toutes': '1',
      },
    ),
  );

  /// L'écran le plus partagé du cabinet : il doit bouger seul.
  @override
  Stream<List<Map<String, dynamic>>> salleAttenteFlux({String? profileId}) =>
      _rt.fluxRafraichi(
        charger: () => salleAttente(profileId: profileId),
        entites: const ['salle_attente'],
      );

  @override
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

  @override
  Future<Map<String, dynamic>> demarrerConsultation(String waitingId) async =>
      _objet(await _api.post('/waiting/$waitingId/demarrer'));

  @override
  Future<void> cloturerConsultation(
    String waitingId, {
    bool decompterSeance = true,
    double? prixSeance,
  }) => _api.post('/waiting/$waitingId/cloturer', {
    'decompterSeance': decompterSeance,
    if (prixSeance != null && prixSeance > 0) 'prixSeance': prixSeance,
  });

  // -----------------------------------------------------------------
  //  Achats et statistiques
  // -----------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> achats({String? dayKey}) async => _liste(
    await _api.get(
      '/purchases',
      params: {if (dayKey != null) 'dayKey': dayKey},
    ),
  );

  @override
  Stream<List<Map<String, dynamic>>> achatsFlux() =>
      _rt.fluxRafraichi(charger: achats, entites: const ['purchases']);

  @override
  Future<Map<String, dynamic>> creerAchat(Map<String, dynamic> champs) async =>
      _objet(await _api.post('/purchases', champs));

  @override
  Future<void> supprimerAchat(String id) => _api.delete('/purchases/$id');

  @override
  Future<List<Map<String, dynamic>>> statsJournalieres({
    String? depuis,
    String? jusqua,
  }) async => _liste(
    await _api.get(
      '/stats/daily',
      params: {
        if (depuis != null) 'depuis': depuis,
        if (jusqua != null) 'jusqua': jusqua,
      },
    ),
  );

  @override
  Stream<List<Map<String, dynamic>>> statsFlux({String? depuis}) =>
      _rt.fluxRafraichi(
        charger: () => statsJournalieres(depuis: depuis),
        // Les statistiques bougent quand l'argent bouge.
        entites: const ['versements', 'purchases'],
      );

  // -----------------------------------------------------------------
  //  Journal d'erreurs
  // -----------------------------------------------------------------

  @override
  Future<void> signalerErreur(Map<String, dynamic> champs) async {
    try {
      await _api.post('/errors', champs);
    } catch (_) {
      // Silence volontaire.
    }
  }
}

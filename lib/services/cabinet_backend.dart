/// Ce qu'un cabinet sait faire, indépendamment de l'endroit où il est stocké.
///
/// Deux implémentations : `MongoCabinetBackend` parle au backend Node,
/// `FirebaseCabinetBackend` parle à Firestore. `ApiService` choisit l'une ou
/// l'autre selon [BackendConfig], et les écrans ne voient que ce contrat.
///
/// Les méthodes rendent des `Map<String, dynamic>` et non des classes
/// typées, parce que c'est la forme que les écrans lisent déjà — un
/// `data['nom']` hérité des documents Firestore. Les deux implémentations
/// doivent donc rendre les **mêmes clés** : `id` pour l'identifiant,
/// `createdAt` en ISO 8601, et les champs métier tels que les modèles
/// MongoDB les nomment. C'est le seul endroit où cette correspondance est
/// exigée, et c'est ce qui rend la bascule invisible.
///
/// Deux formes coexistent, exprès :
///
/// - `Future` pour les écritures ;
/// - `Stream` pour les lectures affichées — `snapshots()` côté Firestore,
///   rechargement sur événement Socket.IO côté Node.
abstract class CabinetBackend {
  // -----------------------------------------------------------------
  //  Le cabinet
  // -----------------------------------------------------------------

  /// Le document du cabinet : horaires, motifs prédéfinis, listes de
  /// référence.
  Future<Map<String, dynamic>> cabinet();

  Future<Map<String, dynamic>> majCabinet(Map<String, dynamic> champs);

  Future<void> majHoraires(Map<String, dynamic> horaires);

  /// Ajoute des valeurs à une liste de référence (`cabinetMedicaments`,
  /// `cabinetBilans`). Ce que le médecin écrit une fois lui est proposé la
  /// fois suivante.
  Future<void> ajouterListe(String liste, Iterable<String> valeurs);

  // -----------------------------------------------------------------
  //  Profils
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> profils();

  Stream<List<Map<String, dynamic>>> profilsFlux();

  Future<Map<String, dynamic>> creerProfil({
    required String name,
    required String role,
    required String pin,
  });

  Future<Map<String, dynamic>> majProfil(
    String id,
    Map<String, dynamic> champs,
  );

  Future<void> supprimerProfil(String id);

  /// Vérifie le code d'un profil et rend le profil si le code est bon.
  ///
  /// Le PIN ne doit jamais être comparé dans l'écran : côté Node c'est
  /// bcrypt sur le serveur, côté Firestore un SHA-256 confronté au haché
  /// stocké. Dans les deux cas le code saisi ne ressort pas d'ici.
  Future<Map<String, dynamic>> verifierPin(String profileId, String pin);

  // -----------------------------------------------------------------
  //  Patients
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> patients({
    String? profileId,
    bool inclureSupprimes = false,
  });

  Stream<List<Map<String, dynamic>>> patientsFlux({String? profileId});

  /// Les patients créés depuis [depuis], en direct.
  ///
  /// Pour une liste affichée en continu (l'onglet Patients) sans garder un
  /// listener ouvert sur tout l'historique du cabinet : au-delà de cette
  /// fenêtre, une recherche ponctuelle (non écoutée) via [patients] suffit —
  /// c'est rare, et ça n'a pas besoin d'être poussé en direct.
  Stream<List<Map<String, dynamic>>> patientsRecentsFlux({
    String? profileId,
    required DateTime depuis,
  });

  Future<Map<String, dynamic>> patient(String id);

  /// Le dossier et tout ce qui pend dessous — documents, versements — en
  /// une seule lecture.
  Future<Map<String, dynamic>> dossier(String id);

  Stream<Map<String, dynamic>> dossierFlux(String id);

  /// Le seul document patient, en direct — sans les formulaires ni les
  /// versements que charge [dossierFlux]. Pour un affichage qui ne lit que
  /// des champs du patient (prix, versements dénormalisés...), c'est un
  /// flux bien plus léger : un seul listener au lieu de trois, et aucune
  /// re-lecture déclenchée par un document ou un versement sans rapport.
  Stream<Map<String, dynamic>> patientDocFlux(String id);

  Future<Map<String, dynamic>> creerPatient(Map<String, dynamic> champs);

  Future<Map<String, dynamic>> majPatient(
    String id,
    Map<String, dynamic> champs,
  );

  /// Suppression douce : le dossier reste, ses versements aussi.
  Future<void> supprimerPatient(String id);

  Future<void> restaurerPatient(String id);

  // -----------------------------------------------------------------
  //  Documents médicaux
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> documents({
    String? patientId,
    String? type,
    DateTime? jour,
  });

  Stream<List<Map<String, dynamic>>> documentsFlux({String? patientId});

  Future<Map<String, dynamic>> creerDocument(Map<String, dynamic> champs);

  Future<Map<String, dynamic>> majDocument(
    String id,
    Map<String, dynamic> champs,
  );

  Future<void> supprimerDocument(String id);

  // -----------------------------------------------------------------
  //  Versements
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> versements({String? patientId});

  /// Les versements d'un patient, en direct — sans les formulaires ni le
  /// document patient que charge [dossierFlux]. Pour un affichage qui ne
  /// lit que les règlements, c'est un listener de moins.
  Stream<List<Map<String, dynamic>>> versementsFlux({String? patientId});

  /// Encaisse, et met à jour dans le même geste le total du patient et la
  /// recette du jour. Les trois écritures vont ensemble : une caisse juste
  /// à moitié est pire qu'une caisse fausse, on ne sait pas laquelle croire.
  Future<Map<String, dynamic>> encaisser({
    required String patientId,
    required double montant,
    String? auteurProfileId,
  });

  // -----------------------------------------------------------------
  //  Rendez-vous
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> rendezVous({
    String? profileId,
    DateTime? jour,
    DateTime? depuis,
    int? limit,
  });

  Stream<List<Map<String, dynamic>>> rendezVousFlux({
    String? profileId,
    DateTime? jour,
  });

  /// Planifie un rendez-vous.
  ///
  /// Lève une `ApiException` avec `estConflit` si le créneau vient d'être
  /// pris : deux postes peuvent poser la même heure à la même seconde, et
  /// le contrôle fait dans l'écran ne suffit pas.
  Future<Map<String, dynamic>> planifier(Map<String, dynamic> champs);

  Future<Map<String, dynamic>> majRendezVous(
    String id,
    Map<String, dynamic> champs,
  );

  Future<Map<String, dynamic>> changerEtapeRdv(
    String id,
    String etape, {
    String? motifAnnulation,
  });

  /// Le patient se présente : crée l'entrée en salle **et** marque le
  /// rendez-vous. Les deux sont indissociables.
  Future<Map<String, dynamic>> marquerArrive(String rdvId);

  Future<void> supprimerRendezVous(String id);

  // -----------------------------------------------------------------
  //  Salle d'attente
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> salleAttente({
    String? profileId,
    bool toutes = false,
  });

  Stream<List<Map<String, dynamic>>> salleAttenteFlux({String? profileId});

  Future<Map<String, dynamic>> mettreEnSalle({
    required String patientId,
    String? rdvId,
    String motif = '',
  });

  Future<Map<String, dynamic>> demarrerConsultation(String waitingId);

  /// Décompte la séance, sort le patient, marque le rendez-vous honoré.
  ///
  /// `prixSeance` est facturé au patient dans la même transaction que le
  /// décompte. Une entrée déjà close ne refacture rien — le double clic est
  /// sans effet.
  Future<void> cloturerConsultation(
    String waitingId, {
    bool decompterSeance = true,
    double? prixSeance,
  });

  // -----------------------------------------------------------------
  //  Achats et statistiques
  // -----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> achats({String? dayKey});

  Stream<List<Map<String, dynamic>>> achatsFlux();

  Future<Map<String, dynamic>> creerAchat(Map<String, dynamic> champs);

  Future<void> supprimerAchat(String id);

  Future<List<Map<String, dynamic>>> statsJournalieres({
    String? depuis,
    String? jusqua,
  });

  Stream<List<Map<String, dynamic>>> statsFlux({String? depuis});

  // -----------------------------------------------------------------
  //  Journal d'erreurs
  // -----------------------------------------------------------------

  /// N'échoue jamais bruyamment : signaler une erreur ne doit pas en créer
  /// une seconde.
  Future<void> signalerErreur(Map<String, dynamic> champs);
}

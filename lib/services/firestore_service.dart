import 'api_service.dart';

/// Les lectures du cabinet, désormais contre le backend.
///
/// Le nom reste `FirestoreService` le temps de la migration : neuf fichiers
/// l'appellent, et le renommer en même temps qu'on change son contenu
/// mélangerait deux modifications dans le même diff. Il deviendra
/// `CabinetService` une fois Firebase parti.
///
/// Ce qui change pour les appelants : les flux rendent des
/// `List<Map<String, dynamic>>` au lieu de `QuerySnapshot`. Un
/// `QuerySnapshot` ne se fabrique pas hors de Firestore, et écrire une
/// fausse classe qui l'imite aurait figé une forme Firestore dans une app
/// qui n'en a plus. Concrètement, `snap.data!.docs` devient `snap.data!`,
/// et `doc.data() as Map` disparaît.
///
/// L'identifiant du document, lu par `doc.id`, se lit maintenant
/// `doc['id']` : le backend le pose dans chaque objet renvoyé.
class FirestoreService {
  FirestoreService._internal();

  static final FirestoreService _instance = FirestoreService._internal();

  factory FirestoreService() => _instance;

  final _api = ApiService.instance;

  /// Les patients d'un profil.
  ///
  /// `parentUid` n'est plus utilisé : le cabinet est déduit du jeton, et le
  /// backend refuse tout ce qui sort du sien. Le paramètre reste pour ne
  /// pas toucher aux appelants dans le même commit — il disparaîtra avec le
  /// dernier d'entre eux.
  Stream<List<Map<String, dynamic>>> patientsStream({
    required String parentUid,
    required String profileId,
    bool orderByCreated = false,
    int? limit,
    DateTime? createdAfter,
  }) {
    return _api.patientsFlux(profileId: profileId).map((liste) {
      // Le filtrage par date se fait ici et non dans la requête : les
      // dossiers antérieurs à l'introduction de `createdAt` n'ont pas le
      // champ, et une contrainte serveur les exclurait tous en silence.
      if (createdAfter == null) return liste;
      return liste.where((p) {
        final d = DateTime.tryParse('${p['createdAt']}');
        return d != null && !d.isBefore(createdAfter);
      }).toList();
    });
  }

  /// Tous les patients du cabinet.
  ///
  /// Remplace le `collectionGroup` et son repli sur index manquant : la
  /// hiérarchie Firestore a disparu, c'est devenu une requête ordinaire.
  Stream<List<Map<String, dynamic>>> allPatientsStream({
    required String parentUid,
    bool includeLegacy = false,
  }) => _api.patientsFlux();

  Stream<List<Map<String, dynamic>>> rendezVousStream({
    required String parentUid,
    required String profileId,
    int? limit,
    DateTime? fromDate,
  }) {
    return _api
        .rendezVousFlux(profileId: profileId)
        .map((liste) {
          if (fromDate == null) return liste;
          return liste.where((r) {
            final d = DateTime.tryParse('${r['datetime']}');
            return d != null && !d.isBefore(fromDate);
          }).toList();
        })
        .map((liste) => limit == null ? liste : liste.take(limit).toList());
  }

  /// Un dossier patient. `null` s'il n'existe plus.
  Stream<Map<String, dynamic>?> patientDoc({
    required String parentUid,
    required String profileId,
    required String patientId,
  }) => _api.dossierFlux(patientId).map((d) => d['patient'] as Map<String, dynamic>?);

  Stream<List<Map<String, dynamic>>> patientForms({
    required String parentUid,
    required String profileId,
    required String patientId,
  }) => _api.documentsFlux(patientId: patientId);
}

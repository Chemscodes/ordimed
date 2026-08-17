import 'api_client.dart';
import 'api_service.dart';

/// La salle d'attente.
///
/// Le fichier faisait 322 lignes. L'essentiel n'etait pas de la logique
/// metier mais du travail que Firestore imposait :
///
///  - ecrire chaque entree **trois fois** (medecin, assistant, medecin
///    principal), parce qu'il ne sait pas joindre ;
///  - relire les trois copies pour verifier qu'un patient n'y figurait pas
///    deja, faute de contrainte d'unicite ;
///  - refermer a la main les entrees oubliees de la veille, aucune requete
///    ne pouvant le faire cote serveur.
///
/// Tout cela vit desormais dans le backend, ou une entree est un document et
/// une transaction une transaction. Il reste une facade : les signatures
/// sont conservees telles quelles pour que les sept appels existants n'aient
/// pas a changer dans le meme commit.
class WaitingService {
  WaitingService._internal();

  static final WaitingService _instance = WaitingService._internal();

  factory WaitingService() => _instance;

  final _api = ApiService.instance;

  /// Place un patient en salle.
  ///
  /// Renvoie `false` s'il y figure deja. Le garde-fou est maintenant cote
  /// serveur : deux postes qui cliquent en meme temps ne creent plus deux
  /// entrees, ce que trois lectures suivies d'une ecriture ne pouvaient pas
  /// garantir.
  ///
  /// `parentUid` et les noms ne servent plus : le cabinet vient du jeton, et
  /// le backend reprend les noms du dossier patient. Les parametres restent
  /// le temps que les appelants soient convertis.
  Future<bool> addToWaiting({
    required String parentUid,
    required String assistantId,
    String assistantName = '',
    required String doctorId,
    required String doctorName,
    required String patientId,
    required String patientNom,
    required String patientPrenom,
    int? nombreSeances,
    int? seancesEffectuees,
    String? rdvId,
    String motif = '',
  }) async {
    try {
      await _api.mettreEnSalle(
        patientId: patientId,
        rdvId: rdvId,
        motif: motif,
      );
      return true;
    } on ApiException catch (e) {
      // 409 : le patient est deja dans la file. Ce n'est pas une panne,
      // c'est la reponse a la question posee.
      if (e.estConflit) return false;
      rethrow;
    }
  }

  /// Le medecin demarre la consultation.
  Future<void> markInConsultation({
    required String parentUid,
    required String profileId,
    required String waitingId,
    required String doctorId,
    required String assistantId,
  }) => _api.demarrerConsultation(waitingId);

  /// Cloture : decompte la seance, sort le patient, marque le rendez-vous.
  ///
  /// Les trois etaient trois ecritures separees ici, chacune pouvant echouer
  /// seule — une seance decomptee sans sortie de file laissait le patient
  /// chez le medecin, seance deja comptee. C'est une transaction serveur.
  Future<void> closeEntryForAll({
    required String parentUid,
    required String profileId,
    required String waitingId,
    required String doctorId,
    required String assistantId,
    String patientId = '',
    int? seancesEffectuees,
    double? prixSeance,
  }) => _api.cloturerConsultation(
    waitingId,
    // Le decompte se fait cote serveur. L'ancien code calculait le nouveau
    // total dans l'app puis l'ecrivait, ce qui perdait un increment quand
    // deux postes cloturaient en meme temps.
    decompterSeance: seancesEffectuees != null,
    prixSeance: prixSeance,
  );

  /// La file d'un profil, mise a jour toute seule.
  Stream<List<Map<String, dynamic>>> waitingStream({
    required String parentUid,
    required String profileId,
  }) => _api.salleAttenteFlux(profileId: profileId);
}

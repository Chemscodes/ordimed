import 'api_client.dart';
import 'api_service.dart';
import '../core/parcours.dart';

/// Les rendez-vous.
///
/// Le fichier ecrivait chaque rendez-vous en trois exemplaires — medecin,
/// assistant, medecin principal — et refaisait ce fan-out a chaque
/// changement d'etape. Un seul document maintenant : les trois profils le
/// retrouvent par requete, et deux copies ne peuvent plus diverger.
///
/// Les signatures sont conservees pour que les appelants n'aient pas a
/// changer dans le meme commit.
class RendezVousRepository {
  final _api = ApiService.instance;

  Future<void> planifier({
    required String parentUid,
    required String doctorId,
    required String assistantId,
    required Map<String, dynamic> rdvData,
  }) async {
    await _api.planifier({
      ...rdvData,
      'doctorId': doctorId,
      'assistantId': assistantId,
    });
  }

  /// Fait avancer un rendez-vous d'une etape.
  Future<void> changerEtape({
    required String parentUid,
    required String rdvId,
    required String doctorId,
    required String assistantId,
    required EtapeParcours etape,
    String? motifAnnulation,
  }) => _api.changerEtapeRdv(
    rdvId,
    etape.code,
    motifAnnulation: motifAnnulation,
  );

  /// Le patient se presente : le rendez-vous entre en salle d'attente.
  ///
  /// C'etait le trou du parcours — l'assistant devait ressaisir le patient
  /// dans la file alors que le rendez-vous portait deja tout. Les deux
  /// ecritures sont maintenant une transaction serveur : le rendez-vous
  /// n'est pas marque si la mise en salle echoue.
  ///
  /// Renvoie `false` si le patient a deja une entree ouverte.
  Future<bool> marquerArrive({
    required String parentUid,
    required String rdvId,
    required Map<String, dynamic> rdv,
    required String profileId,
  }) async {
    try {
      await _api.marquerArrive(rdvId);
      return true;
    } on ApiException catch (e) {
      if (e.estConflit) return false;
      rethrow;
    }
  }

  /// Marque honore le rendez-vous d'ou vient une consultation.
  ///
  /// Sans effet quand la consultation n'est rattachee a aucun rendez-vous.
  /// La cloture le fait desormais elle-meme, dans sa transaction ; cette
  /// methode reste pour les appelants qui ne passent pas par la file.
  Future<void> honorerDepuisVisite({
    required String parentUid,
    required String? rdvId,
    required String doctorId,
    required String assistantId,
  }) async {
    if (rdvId == null || rdvId.isEmpty) return;
    await _api.changerEtapeRdv(rdvId, EtapeParcours.honore.code);
  }

  /// Les rendez-vous d'un medecin sur une journee.
  ///
  /// Sert a savoir ce qui est deja pris avant d'en poser un nouveau.
  Stream<List<Map<String, dynamic>>> journee({
    required String parentUid,
    required String profileId,
    required DateTime jour,
  }) => _api.rendezVousFlux(profileId: profileId, jour: jour);
}

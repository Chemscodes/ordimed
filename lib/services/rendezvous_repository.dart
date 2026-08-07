import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/coerce.dart';
import '../core/parcours.dart';
import 'waiting_service.dart';

/// Les rendez-vous, et leur avancement dans le parcours.
///
/// Un rendez-vous existe en trois exemplaires — médecin, assistant, médecin
/// principal — pour que chacun le lise dans sa propre collection sans
/// requête croisée. Toute écriture doit donc toucher les trois, sinon les
/// profils divergent : c'est le rôle de [_fanOut].
class RendezVousRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _comptes(String parentUid) =>
      _db.collection('users').doc(parentUid).collection('comptes');

  /// Les trois copies d'un rendez-vous, sans doublon.
  ///
  /// L'ensemble déduplique : quand le profil courant est déjà le médecin,
  /// écrire deux fois dans un batch sur la même référence est inutile.
  List<DocumentReference<Map<String, dynamic>>> _fanOut({
    required String parentUid,
    required String rdvId,
    required String doctorId,
    required String assistantId,
  }) {
    final base = _comptes(parentUid);
    final profils = <String>{
      'medecin_principal',
      if (doctorId.isNotEmpty) doctorId,
      if (assistantId.isNotEmpty) assistantId,
    };
    return [
      for (final p in profils) base.doc(p).collection('rendezvous').doc(rdvId),
    ];
  }

  Future<void> planifier({
    required String parentUid,
    required String doctorId,
    required String assistantId,
    required Map<String, dynamic> rdvData,
  }) async {
    final rdvId = _db.collection('tmp').doc().id;
    final data = {
      ...rdvData,
      'rdvId': rdvId,
      'etape': EtapeParcours.planifie.code,
    };

    final batch = _db.batch();
    for (final ref in _fanOut(
      parentUid: parentUid,
      rdvId: rdvId,
      doctorId: doctorId,
      assistantId: assistantId,
    )) {
      batch.set(ref, data);
    }
    await batch.commit();
  }

  /// Fait avancer un rendez-vous d'une étape, sur les trois copies.
  ///
  /// L'horodatage porte le nom de l'étape (`arriveAt`, `honoreAt`…) : savoir
  /// *quand* un patient est arrivé et *quand* il est passé est ce qui permet
  /// plus tard de mesurer une attente réelle.
  Future<void> changerEtape({
    required String parentUid,
    required String rdvId,
    required String doctorId,
    required String assistantId,
    required EtapeParcours etape,
    String? motifAnnulation,
  }) async {
    final payload = <String, dynamic>{
      'etape': etape.code,
      '${etape.code}At': FieldValue.serverTimestamp(),
    };
    if (motifAnnulation != null && motifAnnulation.trim().isNotEmpty) {
      payload['motifAnnulation'] = motifAnnulation.trim();
    }

    final batch = _db.batch();
    for (final ref in _fanOut(
      parentUid: parentUid,
      rdvId: rdvId,
      doctorId: doctorId,
      assistantId: assistantId,
    )) {
      batch.set(ref, payload, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Le patient se présente : le rendez-vous entre en salle d'attente.
  ///
  /// C'était le trou du parcours. L'assistant devait ressaisir le patient
  /// dans la file alors que le rendez-vous portait déjà tout — nom, médecin,
  /// motif. Deux saisies pour un seul fait, et aucun lien entre les deux :
  /// le rendez-vous restait « à venir » même une fois le patient reparti.
  ///
  /// Renvoie `false` si le patient a déjà une entrée ouverte, auquel cas le
  /// rendez-vous n'est pas marqué : rien ne s'est passé.
  Future<bool> marquerArrive({
    required String parentUid,
    required String rdvId,
    required Map<String, dynamic> rdv,
    required String profileId,
  }) async {
    final doctorId = asText(rdv['doctorId']);
    final assistantId = asText(rdv['assistantId']).isNotEmpty
        ? asText(rdv['assistantId'])
        : profileId;

    final place = await WaitingService().addToWaiting(
      parentUid: parentUid,
      assistantId: assistantId,
      assistantName: asText(rdv['assistantName']),
      doctorId: doctorId,
      doctorName: asText(rdv['doctorName']),
      patientId: asText(rdv['patientId']),
      patientNom: asText(rdv['patientNom']),
      patientPrenom: asText(rdv['patientPrenom']),
      rdvId: rdvId,
      motif: asText(rdv['motif']),
    );
    if (!place) return false;

    await changerEtape(
      parentUid: parentUid,
      rdvId: rdvId,
      doctorId: doctorId,
      assistantId: assistantId,
      etape: EtapeParcours.arrive,
    );
    return true;
  }

  /// Marque honoré le rendez-vous d'où vient une consultation.
  ///
  /// Sans effet quand la consultation n'est rattachée à aucun rendez-vous —
  /// un patient qui se présente sans rendez-vous est un cas normal, pas une
  /// erreur à signaler.
  Future<void> honorerDepuisVisite({
    required String parentUid,
    required String? rdvId,
    required String doctorId,
    required String assistantId,
  }) async {
    if (rdvId == null || rdvId.isEmpty) return;
    await changerEtape(
      parentUid: parentUid,
      rdvId: rdvId,
      doctorId: doctorId,
      assistantId: assistantId,
      etape: EtapeParcours.honore,
    );
  }

  /// Rendez-vous d'un profil sur une journée, du plus tôt au plus tard.
  Stream<QuerySnapshot<Map<String, dynamic>>> journee({
    required String parentUid,
    required String profileId,
    required DateTime jour,
  }) {
    final debut = DateTime(jour.year, jour.month, jour.day);
    final fin = debut.add(const Duration(days: 1));
    return _comptes(parentUid)
        .doc(profileId)
        .collection('rendezvous')
        .where('datetime', isGreaterThanOrEqualTo: Timestamp.fromDate(debut))
        .where('datetime', isLessThan: Timestamp.fromDate(fin))
        .orderBy('datetime')
        .snapshots();
  }
}

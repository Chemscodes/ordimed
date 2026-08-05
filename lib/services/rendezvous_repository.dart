import 'package:cloud_firestore/cloud_firestore.dart';

class RendezVousRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> planifier({
    required String parentUid,
    required String doctorId,
    required String assistantId,
    required Map<String, dynamic> rdvData,
  }) async {
    final rdvId = _db.collection('tmp').doc().id;

    final doctorRdv = _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(doctorId)
        .collection('rendezvous')
        .doc(rdvId);

    final assistantRdv = _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(assistantId)
        .collection('rendezvous')
        .doc(rdvId);

    final principalRdv = _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc('medecin_principal')
        .collection('rendezvous')
        .doc(rdvId);

    final batch = _db.batch();
    batch.set(doctorRdv, rdvData);
    batch.set(assistantRdv, rdvData);
    batch.set(principalRdv, rdvData);
    await batch.commit();
  }
}

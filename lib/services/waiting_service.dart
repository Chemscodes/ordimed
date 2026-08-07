import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/coerce.dart';
import '../core/parcours.dart';

class WaitingService {
  WaitingService._internal();
  static final WaitingService _instance = WaitingService._internal();
  factory WaitingService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration _staleOpenThreshold = Duration(hours: 24);

  DateTime? _asDateTime(dynamic value) => asDateOrNull(value);

  bool _isDoneEntry(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase();
    final closedAt = data['closedAt'];
    return status == 'done' ||
        status == 'closed' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        closedAt != null;
  }

  bool _isStaleOpenEntry(Map<String, dynamic> data, DateTime now) {
    final createdAt = _asDateTime(data['createdAt']);
    if (createdAt == null) return false;
    return now.difference(createdAt) > _staleOpenThreshold;
  }

  Future<void> _closeStaleEntries({
    required String parentUid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> staleDocs,
  }) async {
    if (staleDocs.isEmpty) return;
    final base = _db.collection('users').doc(parentUid).collection('comptes');
    final payload = {
      'closedAt': FieldValue.serverTimestamp(),
      'status': 'done',
      'autoClosedReason': 'stale_open_entry',
    };
    final batch = _db.batch();
    var writes = 0;

    for (final d in staleDocs) {
      final data = d.data();
      final waitingId = d.id;
      final doctorId = (data['doctorId'] ?? '').toString();
      final assistantId = (data['assistantId'] ?? '').toString();
      final targets = <String>{
        'medecin_principal',
        if (doctorId.isNotEmpty) doctorId,
        if (assistantId.isNotEmpty) assistantId,
      };
      for (final profileId in targets) {
        batch.set(
          base.doc(profileId).collection('salle_attente').doc(waitingId),
          payload,
          SetOptions(merge: true),
        );
        writes++;
      }
    }

    if (writes > 0) {
      await batch.commit();
    }
  }

  Future<bool> _hasOpenEntry({
    required String parentUid,
    required String patientId,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc('medecin_principal')
        .collection('salle_attente')
        .where('patientId', isEqualTo: patientId)
        .limit(80)
        .get();

    final now = DateTime.now();
    final staleDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (_isDoneEntry(data)) continue;
      if (_isStaleOpenEntry(data, now)) {
        staleDocs.add(d);
        continue;
      }
      return true;
    }
    if (staleDocs.isNotEmpty) {
      try {
        await _closeStaleEntries(parentUid: parentUid, staleDocs: staleDocs);
      } catch (_) {
        // On ignore cet echec pour ne pas bloquer l'ajout patient.
      }
    }
    return false;
  }

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
    if (await _hasOpenEntry(parentUid: parentUid, patientId: patientId)) {
      return false;
    }

    final waitingId = _db.collection('tmp').doc().id;

    final data = {
      'waitingId': waitingId,
      // Rattache l'entrée au rendez-vous dont elle est issue, pour que la
      // clôture de la consultation puisse marquer ce rendez-vous honoré.
      // Sans ce lien, un rendez-vous restait « à venir » indéfiniment.
      if (rdvId != null) 'rdvId': rdvId,
      if (motif.isNotEmpty) 'motif': motif,
      // Nouveau vocabulaire du parcours (core/parcours.dart). L'ancien
      // `status` reste écrit : des requêtes et des vues le lisent encore.
      'etape': EtapeParcours.arrive.code,
      'patientId': patientId,
      'patientNom': patientNom,
      'patientPrenom': patientPrenom,
      'assistantId': assistantId,
      'assistantName': assistantName,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'createdAt': FieldValue.serverTimestamp(),
      'closedAt': null,
      'inConsultationAt': null,
      'parentUid': parentUid,
      'status': 'waiting',
    };
    if (nombreSeances != null) data['nombreSeances'] = nombreSeances;
    if (seancesEffectuees != null) {
      data['seancesEffectuees'] = seancesEffectuees;
    }
    final base = _db.collection('users').doc(parentUid).collection('comptes');

    final batch = _db.batch();
    batch.set(
      base.doc(assistantId).collection('salle_attente').doc(waitingId),
      data,
    );
    batch.set(
      base.doc(doctorId).collection('salle_attente').doc(waitingId),
      data,
    );
    batch.set(
      base.doc('medecin_principal').collection('salle_attente').doc(waitingId),
      data,
    );
    await batch.commit();
    return true;
  }

  Stream<QuerySnapshot> waitingStream({
    required String parentUid,
    required String profileId,
  }) {
    return _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(profileId)
        .collection('salle_attente')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> markInConsultation({
    required String parentUid,
    required String profileId,
    required String waitingId,
    required String doctorId,
    required String assistantId,
  }) async {
    final base = _db.collection('users').doc(parentUid).collection('comptes');
    final payload = {
      'status': 'in_consultation',
      'etape': EtapeParcours.enCours.code,
      'inConsultationAt': FieldValue.serverTimestamp(),
      'closedAt': null,
    };
    final batch = _db.batch();
    batch.set(
      base.doc(profileId).collection('salle_attente').doc(waitingId),
      payload,
      SetOptions(merge: true),
    );
    batch.set(
      base.doc('medecin_principal').collection('salle_attente').doc(waitingId),
      payload,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty) {
      batch.set(
        base.doc(doctorId).collection('salle_attente').doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
    }
    if (assistantId.isNotEmpty) {
      batch.set(
        base.doc(assistantId).collection('salle_attente').doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> closeEntryForAll({
    required String parentUid,
    required String profileId,
    required String waitingId,
    required String doctorId,
    required String assistantId,
    String patientId = '',
    int? seancesEffectuees,
  }) async {
    final base = _db.collection('users').doc(parentUid).collection('comptes');
    final payload = {
      'closedAt': FieldValue.serverTimestamp(),
      'status': 'done',
      'etape': EtapeParcours.honore.code,
    };
    if (seancesEffectuees != null) {
      payload['seancesEffectuees'] = seancesEffectuees;
    }
    final batch = _db.batch();
    batch.set(
      base.doc(profileId).collection('salle_attente').doc(waitingId),
      payload,
      SetOptions(merge: true),
    );
    batch.set(
      base.doc('medecin_principal').collection('salle_attente').doc(waitingId),
      payload,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty) {
      batch.set(
        base.doc(doctorId).collection('salle_attente').doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
    }
    if (assistantId.isNotEmpty) {
      batch.set(
        base.doc(assistantId).collection('salle_attente').doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> closeAllOpenForProfile({
    required String parentUid,
    required String profileId,
  }) async {
    final snap = await waitingStream(
      parentUid: parentUid,
      profileId: profileId,
    ).first;
    final base = _db.collection('users').doc(parentUid).collection('comptes');
    final payload = {
      'closedAt': FieldValue.serverTimestamp(),
      'status': 'done',
    };
    final batch = _db.batch();
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final doctorId = (data['doctorId'] ?? '').toString();
      final assistantId = (data['assistantId'] ?? '').toString();
      final waitingId = d.id;
      batch.set(
        base.doc(profileId).collection('salle_attente').doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
      batch.set(
        base
            .doc('medecin_principal')
            .collection('salle_attente')
            .doc(waitingId),
        payload,
        SetOptions(merge: true),
      );
      if (doctorId.isNotEmpty) {
        batch.set(
          base.doc(doctorId).collection('salle_attente').doc(waitingId),
          payload,
          SetOptions(merge: true),
        );
      }
      if (assistantId.isNotEmpty) {
        batch.set(
          base.doc(assistantId).collection('salle_attente').doc(waitingId),
          payload,
          SetOptions(merge: true),
        );
      }
    }
    await batch.commit();
  }
}

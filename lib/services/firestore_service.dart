import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class FirestoreService {
  FirestoreService._internal();
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;

  final _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot> patientsStream({
    required String parentUid,
    required String profileId,
    bool orderByCreated = false,
    int? limit,
    DateTime? createdAfter,
  }) {
    Query<Map<String, dynamic>> ref = _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(profileId)
        .collection('patients');
    if (createdAfter != null) {
      ref = ref.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(createdAfter));
      orderByCreated = true;
    }
    if (orderByCreated) {
      ref = ref.orderBy('createdAt', descending: true);
    }
    if (limit != null) {
      ref = ref.limit(limit);
    }
    return ref.snapshots();
  }

  /// Stream of all patients (collectionGroup).
  /// Defaults to parentUid filter; falls back if the index is missing.
  Stream<QuerySnapshot<Map<String, dynamic>>> allPatientsStream({
    required String parentUid,
    bool includeLegacy = false,
  }) {
    final baseQuery = _db.collectionGroup('patients');
    if (includeLegacy) {
      return baseQuery.snapshots();
    }
    final filteredQuery = baseQuery.where('parentUid', isEqualTo: parentUid);
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    var fellBack = false;

    void listenTo(Query<Map<String, dynamic>> query) {
      sub?.cancel();
      sub = query.snapshots().listen(
        controller.add,
        onError: (error, stack) {
          if (!fellBack &&
              error is FirebaseException &&
              error.code == 'failed-precondition') {
            fellBack = true;
            listenTo(baseQuery);
            return;
          }
          controller.addError(error, stack);
        },
      );
    }

    controller.onListen = () => listenTo(filteredQuery);
    controller.onCancel = () {
      sub?.cancel();
      controller.close();
    };
    return controller.stream;
  }


  Stream<QuerySnapshot> rendezVousStream({
    required String parentUid,
    required String profileId,
    int? limit,
    DateTime? fromDate,
  }) {
    Query<Map<String, dynamic>> ref = _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(profileId)
        .collection('rendezvous');
    if (fromDate != null) {
      ref = ref.where('datetime', isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate));
    }
    ref = ref.orderBy('datetime', descending: false);
    if (limit != null) {
      ref = ref.limit(limit);
    }
    return ref.snapshots();
  }

  Stream<DocumentSnapshot> patientDoc({
    required String parentUid,
    required String profileId,
    required String patientId,
  }) {
    return _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(profileId)
        .collection('patients')
        .doc(patientId)
        .snapshots();
  }

  Stream<QuerySnapshot> patientForms({
    required String parentUid,
    required String profileId,
    required String patientId,
  }) {
    return _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .doc(profileId)
        .collection('patients')
        .doc(patientId)
        .collection('forms')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}


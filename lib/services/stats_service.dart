import 'package:cloud_firestore/cloud_firestore.dart';

class StatsService {
  StatsService._internal();
  static final StatsService _instance = StatsService._internal();
  factory StatsService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String dayKey(DateTime dt) {
    final d = DateTime(dt.year, dt.month, dt.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Stream<DocumentSnapshot<Map<String, dynamic>>> dailyStatsDoc({
    required String parentUid,
    required String dayKey,
  }) {
    return _db
        .collection('users')
        .doc(parentUid)
        .collection('daily_stats')
        .doc(dayKey)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> recentDailyStats({
    required String parentUid,
    int limit = 7,
  }) {
    return _db
        .collection('users')
        .doc(parentUid)
        .collection('daily_stats')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<void> addVersement({
    required String parentUid,
    required double montant,
    String? doctorId,
    String doctorName = '',
    DateTime? when,
  }) async {
    final dt = when ?? DateTime.now();
    final key = dayKey(dt);
    final ref =
        _db.collection('users').doc(parentUid).collection('daily_stats').doc(key);

    // Cle du medecin destinataire ('_none' si non renseigne). Permet au
    // tableau de bord directeur d'afficher le detail par medecin sans avoir
    // a scanner toute la base de patients.
    final docKey = (doctorId == null || doctorId.trim().isEmpty)
        ? '_none'
        : doctorId.trim();

    await ref.set({
      'dayKey': key,
      'date': Timestamp.fromDate(startOfDay(dt)),
      'versementsTotal': FieldValue.increment(montant),
      'versementsCount': FieldValue.increment(1),
      'doctorVersements': {
        docKey: {
          'total': FieldValue.increment(montant),
          'count': FieldValue.increment(1),
          if (doctorName.trim().isNotEmpty) 'name': doctorName.trim(),
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addAchat({
    required String parentUid,
    required double montant,
    DateTime? when,
  }) async {
    final dt = when ?? DateTime.now();
    final key = dayKey(dt);
    final ref =
        _db.collection('users').doc(parentUid).collection('daily_stats').doc(key);
    await ref.set({
      'dayKey': key,
      'date': Timestamp.fromDate(startOfDay(dt)),
      'achatsTotal': FieldValue.increment(montant),
      'achatsCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../api_client.dart';

/// Les chemins Firestore, et la traduction dans les deux sens.
///
/// Tout ce qui rend la bascule invisible aux écrans est ici. Le contrat de
/// `CabinetBackend` exige que les deux backends rendent les mêmes clés ;
/// côté Firestore cela demande deux conversions que MongoDB faisait seul :
///
/// - l'identifiant du document devient un champ `id`, parce que les écrans
///   lisent `doc['id']` et non `doc.id` ;
/// - les `Timestamp` deviennent des chaînes ISO 8601, parce que les écrans
///   font `DateTime.tryParse('${doc['createdAt']}')`. Laisser passer un
///   `Timestamp` brut donnerait `Timestamp(seconds=…)` à analyser, et
///   `tryParse` rendrait `null` sans rien signaler.
///
/// ## La forme de la base
///
/// ```
/// cabinets/{cabinetId}/
///   profiles/  patients/  forms/  versements/
///   rendezvous/  salle_attente/  purchases/  daily_stats/
/// ```
///
/// À plat, et non en arborescence par profil comme la première version
/// Firestore de l'app. Cette arborescence obligeait à écrire chaque patient
/// deux fois — chez le médecin et chez l'assistant — et chaque entrée de
/// salle d'attente trois fois, faute de jointures. Les copies finissaient
/// par diverger en silence. Ici `doctorId` et `assistantId` sont des champs
/// filtrés à la requête, comme dans les modèles Mongo : une seule copie, et
/// les deux backends lisent le même schéma.
class FirebaseRefs {
  FirebaseRefs._();

  static FirebaseFirestore get base => FirebaseFirestore.instance;

  /// L'identifiant du cabinet connecté, c'est-à-dire l'uid Firebase.
  ///
  /// Lève plutôt que de rendre `null` : une lecture sans session viserait
  /// `cabinets/null` et rendrait une liste vide, ce qui passerait pour un
  /// cabinet neuf au lieu d'une erreur.
  static String get cabinetId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const ApiException(message: 'Session expirée', code: 401);
    }
    return uid;
  }

  static DocumentReference<Map<String, dynamic>> cabinetDoc([String? uid]) =>
      base.collection('cabinets').doc(uid ?? cabinetId);

  static CollectionReference<Map<String, dynamic>> col(
    String uid,
    String nom,
  ) => cabinetDoc(uid).collection(nom);

  /// Une collection du cabinet connecté.
  static CollectionReference<Map<String, dynamic>> c(String nom) =>
      cabinetDoc().collection(nom);

  // -----------------------------------------------------------------
  //  Firestore → app
  // -----------------------------------------------------------------

  /// Un document, dans la forme que les écrans attendent.
  static Map<String, dynamic> versMap(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? <String, dynamic>{};
    final sortie = <String, dynamic>{};
    for (final e in data.entries) {
      sortie[e.key] = _versJson(e.value);
    }
    sortie['id'] = d.id;
    return sortie;
  }

  static List<Map<String, dynamic>> versListe(
    QuerySnapshot<Map<String, dynamic>> s,
  ) => s.docs.map(versMap).toList();

  static dynamic _versJson(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DocumentReference) return v.id;
    if (v is Map) {
      return v.map((k, x) => MapEntry(k.toString(), _versJson(x)));
    }
    if (v is List) return v.map(_versJson).toList();
    return v;
  }

  // -----------------------------------------------------------------
  //  App → Firestore
  // -----------------------------------------------------------------

  /// Prépare des champs venus d'un écran pour l'écriture.
  ///
  /// Les dates arrivent tantôt en `DateTime`, tantôt en chaîne ISO — les
  /// écrans ont été écrits contre une API REST. Les deux deviennent des
  /// `Timestamp`, sans quoi les requêtes par intervalle ne trouveraient
  /// rien : Firestore compare des chaînes comme des chaînes.
  static Map<String, dynamic> versFirestore(Map<String, dynamic> champs) {
    final sortie = <String, dynamic>{};
    for (final e in champs.entries) {
      // `id` est le nom du document, jamais un champ : le réécrire dedans
      // créerait deux sources pour la même chose.
      if (e.key == 'id') continue;
      sortie[e.key] = _versValeur(e.key, e.value);
    }
    return sortie;
  }

  /// Les noms de champs qui portent une date.
  ///
  /// Une liste explicite plutôt qu'une détection sur le contenu : une
  /// chaîne comme `'2024'` saisie dans un champ texte se convertirait en
  /// date, et le champ deviendrait illisible.
  static const _champsDate = {
    'createdAt',
    'updatedAt',
    'deletedAt',
    'datetime',
    'date',
    'closedAt',
    'inConsultationAt',
    'derniereConsultation',
    'reminderSentAt',
    'whatsappTemplateUpdatedAt',
  };

  static dynamic _versValeur(String cle, dynamic v) {
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is Map) {
      return v.map((k, x) => MapEntry(k.toString(), _versValeur('$k', x)));
    }
    if (v is List) return v.map((x) => _versValeur(cle, x)).toList();
    if (v is String && _champsDate.contains(cle)) {
      final d = DateTime.tryParse(v);
      if (d != null) return Timestamp.fromDate(d);
    }
    return v;
  }

  /// Le haché d'un code PIN.
  ///
  /// Ici et non dans l'un des deux backends, parce que les deux s'en
  /// servent : l'inscription pose le code du médecin principal, la
  /// vérification le relit. Deux implémentations séparées finiraient par
  /// diverger, et un profil créé d'un côté ne s'ouvrirait plus de l'autre.
  ///
  /// SHA-256 et non bcrypt : il n'existe pas d'implémentation bcrypt en
  /// Dart pur qui vaille celle du serveur, et le hachage joue ici un rôle
  /// différent — voir la note sur le PIN dans `FirebaseCabinetBackend`.
  static String hacherPin(String pin) =>
      sha256.convert(utf8.encode(pin.trim())).toString();

  /// `YYYY-MM-DD` en heure locale, comme le `dayKey` du backend Node.
  ///
  /// La caisse d'une journée doit tomber dans la même case des deux côtés :
  /// une base exportée depuis l'un et relue par l'autre garde ses totaux.
  static String dayKey([DateTime? date]) {
    final d = date ?? DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// Traduit un échec Firestore en [ApiException].
  static ApiException traduire(Object e) {
    if (e is ApiException) return e;
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' => const ApiException(
          message: 'Accès refusé par les règles de sécurité',
          code: 403,
        ),
        'not-found' => const ApiException(
          message: 'Introuvable',
          code: 404,
        ),
        'unavailable' => const ApiException(
          message: 'Pas de connexion. Les données affichées peuvent dater.',
          code: 0,
        ),
        'deadline-exceeded' => const ApiException(
          message: 'La base met trop de temps à répondre',
          code: 0,
        ),
        _ => ApiException(message: e.message ?? 'Erreur base', code: 500),
      };
    }
    return ApiException(message: e.toString(), code: 500);
  }
}

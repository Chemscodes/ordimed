import 'package:cloud_firestore/cloud_firestore.dart';

/// Suppression douce.
///
/// Un document « supprime » n'est plus efface : il recoit un champ
/// `deletedAt`. Les listes le masquent, mais le dossier medical, les
/// versements et l'historique restent intacts et restaurables.
///
/// Pourquoi filtrer cote client et non dans la requete Firestore :
/// `where('deletedAt', isNull: true)` ne remonte que les documents ou le
/// champ existe *et* vaut null. Tous les patients crees avant cette
/// fonctionnalite n'ont pas ce champ du tout — ils disparaitraient donc
/// des listes. Le filtre en memoire couvre les deux cas.
bool isDeleted(Map<String, dynamic>? data) {
  if (data == null) return false;
  return data['deletedAt'] != null;
}

/// Variante pour un document Firestore brut.
bool isDeletedDoc(DocumentSnapshot doc) {
  final data = doc.data();
  if (data is Map<String, dynamic>) return isDeleted(data);
  return false;
}

/// Champs a ecrire pour marquer un document comme supprime.
Map<String, dynamic> deletionMark({
  required String byProfileId,
  String byName = '',
}) {
  return {
    'deletedAt': FieldValue.serverTimestamp(),
    'deletedBy': byProfileId,
    if (byName.trim().isNotEmpty) 'deletedByName': byName.trim(),
  };
}

/// Champs a ecrire pour restaurer un document supprime.
Map<String, dynamic> restorationMark() {
  return {
    'deletedAt': FieldValue.delete(),
    'deletedBy': FieldValue.delete(),
    'deletedByName': FieldValue.delete(),
  };
}

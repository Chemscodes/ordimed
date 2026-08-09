/// Suppression douce.
///
/// Un document « supprime » n'est plus efface : il recoit un champ
/// `deletedAt`. Les listes le masquent, mais le dossier medical, les
/// versements et l'historique restent intacts et restaurables.
///
/// Le filtre reste explicite, cote serveur comme ici : un index partiel sur
/// `deletedAt: null` ne remonterait que les documents ou le champ existe
/// *et* vaut null. Tous les patients crees avant cette fonctionnalite n'ont
/// pas ce champ du tout — ils disparaitraient des listes.
bool isDeleted(Map<String, dynamic>? data) {
  if (data == null) return false;
  return data['deletedAt'] != null;
}

/// Champs a ecrire pour marquer un document comme supprime.
Map<String, dynamic> deletionMark({
  required String byProfileId,
  String byName = '',
}) {
  // L'horodatage est pose par le serveur : l'heure d'un poste mal regle
  // ferait apparaitre des suppressions dans le futur.
  return {
    'deletedBy': byProfileId,
    if (byName.trim().isNotEmpty) 'deletedByName': byName.trim(),
  };
}

/// Champs a ecrire pour restaurer un document supprime.
///
/// FieldValue.delete() n'a pas d'equivalent ici : la route de restauration
/// remet `deletedAt` a null, ce qui suffit — `isDeleted` teste la presence
/// d'une valeur, pas celle du champ.
Map<String, dynamic> restorationMark() {
  return {
    'deletedAt': null,
    'deletedBy': null,
    'deletedByName': null,
  };
}

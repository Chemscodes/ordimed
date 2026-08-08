import 'coerce.dart';

/// Un versement.
class Versement {
  final double montant;
  final DateTime? date;
  final String auteurProfileId;

  /// Identifiant du document dans la sous-collection.
  ///
  /// Vide pour les versements hérités du tableau : ils n'en ont jamais eu,
  /// et c'est précisément ce qui sert à les reconnaître.
  final String id;

  const Versement({
    required this.montant,
    this.date,
    this.auteurProfileId = '',
    this.id = '',
  });

  bool get estHerite => id.isEmpty;

  factory Versement.fromMap(Map<String, dynamic> data, {String id = ''}) =>
      Versement(
        montant: asDouble(data['montant']),
        date: asDateOrNull(data['createdAt']) ?? asDateOrNull(data['date']),
        auteurProfileId: asText(data['auteurProfileId']),
        id: id,
      );

  Map<String, dynamic> toMap() => {
    'montant': montant,
    if (date != null) 'createdAt': date,
    if (auteurProfileId.isNotEmpty) 'auteurProfileId': auteurProfileId,
  };
}

/// Le tableau `versements` du document patient, borné.
///
/// Un document Firestore plafonne à 1 Mo. `arrayUnion` faisait grossir le
/// tableau sans limite : vers quelques milliers de versements le dossier
/// devenait illisible, et l'échec aurait été silencieux — l'écriture rejetée,
/// le patient reparti, l'argent nulle part.
///
/// Le tableau ne disparaît pas pour autant : le graphique du tableau de bord
/// agrège les versements de tous les patients depuis leurs seuls documents.
/// Passer en sous-collection seule imposerait une requête par patient.
///
/// Il garde donc les [maximum] plus récents — largement de quoi couvrir la
/// fenêtre que le graphique regarde — pendant que la sous-collection garde
/// tout.
const int maxVersementsEnCache = 50;

/// Ajoute un versement au tableau et le ramène à [maximum] entrées.
///
/// Les plus récents sont conservés : ce sont ceux qu'on consulte, et ceux
/// que le graphique agrège.
List<Map<String, dynamic>> versementsBornes(
  dynamic existants,
  Map<String, dynamic> nouveau, {
  int maximum = maxVersementsEnCache,
}) {
  final liste = <Map<String, dynamic>>[
    if (existants is Iterable)
      for (final e in existants)
        if (e is Map) Map<String, dynamic>.from(e),
    nouveau,
  ];

  // Du plus récent au plus ancien. Une entrée sans date est traitée comme
  // la plus ancienne : elle est forcément antérieure au champ `createdAt`,
  // qui existe depuis toujours dans le code d'ajout.
  liste.sort((a, b) {
    final da = asDateOrNull(a['createdAt']);
    final db = asDateOrNull(b['createdAt']);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });

  if (liste.length <= maximum) return liste;
  return liste.sublist(0, maximum);
}

/// Fusionne le tableau hérité et la sous-collection.
///
/// Pendant la transition, un même versement existe des deux côtés. Le
/// compter deux fois gonflerait le total affiché au patient — d'où le
/// rapprochement sur le montant et la date à la seconde.
List<Versement> fusionnerVersements({
  required Iterable<Versement> sousCollection,
  required dynamic tableauHerite,
}) {
  final resultat = <Versement>[...sousCollection];

  String cle(Versement v) =>
      '${v.montant}@${v.date?.toIso8601String() ?? 'sans-date'}';

  final connus = resultat.map(cle).toSet();

  if (tableauHerite is Iterable) {
    for (final e in tableauHerite) {
      if (e is! Map) continue;
      final v = Versement.fromMap(Map<String, dynamic>.from(e));
      if (connus.add(cle(v))) resultat.add(v);
    }
  }

  resultat.sort((a, b) {
    final da = a.date, db = b.date;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return resultat;
}

/// Somme des versements.
double totalDe(Iterable<Versement> versements) =>
    versements.fold<double>(0, (s, v) => s + v.montant);

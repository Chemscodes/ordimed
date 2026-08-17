import 'coerce.dart';

/// Ce qu'un document médical est.
///
/// Le type est écrit en clair dans les documents (`Ordonnance medecin`,
/// `Demande de bilan`…) et comparé littéralement par plusieurs écrans. On le
/// lit ici de façon tolérante — la casse et les accents varient selon
/// l'écran qui a écrit.
enum TypeDocument {
  consultation('Consultation'),
  ordonnance('Ordonnance'),
  bilan('Demande de bilan'),
  formulaire('Formulaire médecin'),
  dossierInitial('Dossier initial'),
  note('Note');

  final String libelle;

  const TypeDocument(this.libelle);

  static TypeDocument depuis(dynamic brut) {
    final t = asText(brut).toLowerCase();
    if (t.contains('ordonnance')) return TypeDocument.ordonnance;
    if (t.contains('bilan')) return TypeDocument.bilan;
    if (t.contains('consultation')) return TypeDocument.consultation;
    if (t.contains('initial')) return TypeDocument.dossierInitial;
    // « Formulaire medecin » — testé après les autres, parce que « medecin »
    // apparaît aussi dans « Ordonnance medecin ».
    if (t.contains('formulaire') || t.contains('medecin')) {
      return TypeDocument.formulaire;
    }
    return TypeDocument.note;
  }
}

/// Une visite : tout ce qui a été produit pendant la même consultation.
///
/// Le dossier patient groupait ses documents **par type** — toutes les
/// ordonnances ensemble, tous les bilans ensemble, tous les formulaires
/// ensemble. Chercher « qu'ai-je fait le 3 mars ? » demandait de parcourir
/// quatre listes et de recouper les dates de tête.
///
/// Un dossier médical se lit par visite : ce jour-là, j'ai vu le patient, j'ai
/// noté ceci, prescrit cela, demandé ce bilan.
class Visite {
  /// Ce qui identifie la visite : un `visiteId` ou, à défaut, le jour.
  final String cle;

  final DateTime? date;

  /// Rang chronologique, 1 pour la plus ancienne.
  ///
  /// Calculé et non lu en base : `seanceNumero` existe sous cinq
  /// orthographes, est parfois absent, et parfois faux. Un rang calculé est
  /// toujours cohérent avec ce que le dossier contient.
  final int numero;

  final List<Map<String, dynamic>> documents;

  const Visite({
    required this.cle,
    required this.date,
    required this.numero,
    required this.documents,
  });

  List<Map<String, dynamic>> _du(TypeDocument t) => documents
      .where((d) => TypeDocument.depuis(d['type']) == t)
      .toList(growable: false);

  /// La consultation de la visite, s'il y en a une.
  ///
  /// Il ne devrait y en avoir qu'une. S'il y en a plusieurs — un examen
  /// enregistré, puis corrigé et réenregistré — on rend **la plus récente** :
  /// c'est elle qui porte la correction. Les documents d'une visite étant
  /// triés du plus ancien au plus récent, c'est la dernière.
  Map<String, dynamic>? get consultation {
    final liste = _du(TypeDocument.consultation);
    return liste.isEmpty ? null : liste.last;
  }

  List<Map<String, dynamic>> get ordonnances => _du(TypeDocument.ordonnance);
  List<Map<String, dynamic>> get bilans => _du(TypeDocument.bilan);
  List<Map<String, dynamic>> get formulaires => _du(TypeDocument.formulaire);
  List<Map<String, dynamic>> get notes => _du(TypeDocument.note);
  List<Map<String, dynamic>> get dossierInitial =>
      _du(TypeDocument.dossierInitial);

  /// Résumé d'une ligne : ce que la visite a produit.
  ///
  /// Sert à lire une journée sans la déplier.
  List<String> get resume {
    final parts = <String>[];
    if (consultation != null) parts.add('Consultation');
    if (ordonnances.isNotEmpty) {
      parts.add(
        ordonnances.length == 1 ? 'Ordonnance' : '${ordonnances.length} ordonnances',
      );
    }
    if (bilans.isNotEmpty) {
      parts.add(bilans.length == 1 ? 'Bilan' : '${bilans.length} bilans');
    }
    if (formulaires.isNotEmpty) {
      parts.add(
        formulaires.length == 1
            ? 'Formulaire'
            : '${formulaires.length} formulaires',
      );
    }
    if (notes.isNotEmpty) {
      parts.add(notes.length == 1 ? 'Note' : '${notes.length} notes');
    }
    if (dossierInitial.isNotEmpty) parts.add('Ouverture du dossier');
    return parts;
  }

  /// Vrai quand la visite n'a pas de date exploitable.
  bool get sansDate => date == null;
}

/// Identifie la visite d'un document : le jour de sa création.
///
/// `visiteId` est **volontairement ignoré ici**, alors qu'il est écrit sur les
/// documents des consultations récentes. Le préférer au jour introduirait une
/// régression : la consultation le porterait, mais l'ordonnance rédigée
/// ensuite depuis le dossier patient ne l'aurait pas — et les deux tomberaient
/// dans des groupes différents. L'identifiant séparerait ce que le jour
/// joignait correctement.
///
/// Grouper par jour peut fusionner deux visites d'un même patient le même
/// jour. C'est rare dans un cabinet, et la fusion est moins grave que la
/// coupure : séparer les documents d'une seule visite les rend impossibles à
/// recouper. Surtout, le jour fonctionne sur **tout l'historique existant**,
/// qui n'a aucun `visiteId`.
///
/// `visiteId` reste écrit : il permettra de distinguer deux visites d'un même
/// jour quand tous les documents d'une consultation le porteront.
String cleDeVisite(Map<String, dynamic> document) {
  final d = asDateOrNull(document['createdAt']);
  if (d == null) return '__sans_date__';
  return dayKeyOf(d);
}

/// Groupe des documents en visites, de la plus récente à la plus ancienne.
List<Visite> grouperEnVisites(Iterable<Map<String, dynamic>> documents) {
  final paquets = <String, List<Map<String, dynamic>>>{};
  for (final d in documents) {
    paquets.putIfAbsent(cleDeVisite(d), () => []).add(d);
  }

  /// La date d'une visite : la plus ancienne de ses documents.
  ///
  /// La consultation est écrite avant l'ordonnance qui la suit ; prendre la
  /// plus ancienne donne l'heure d'arrivée plutôt que celle du dernier
  /// papier imprimé.
  DateTime? dateDe(List<Map<String, dynamic>> docs) {
    DateTime? min;
    for (final d in docs) {
      final t = asDateOrNull(d['createdAt']);
      if (t == null) continue;
      if (min == null || t.isBefore(min)) min = t;
    }
    return min;
  }

  final visites = paquets.entries.map((e) {
    final docs = [...e.value]
      // Dans une visite, du plus ancien au plus récent : c'est l'ordre dans
      // lequel le médecin a travaillé.
      ..sort((a, b) {
        final da = asDateOrNull(a['createdAt']);
        final db = asDateOrNull(b['createdAt']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    return Visite(cle: e.key, date: dateDe(docs), numero: 0, documents: docs);
  }).toList();

  // Du plus récent au plus ancien. Les visites sans date passent en dernier :
  // on ne peut pas les situer, mais les perdre serait pire.
  visites.sort((a, b) {
    if (a.date == null && b.date == null) return 0;
    if (a.date == null) return 1;
    if (b.date == null) return -1;
    return b.date!.compareTo(a.date!);
  });

  // Le rang se compte depuis la plus ancienne : la première visite du
  // patient est la visite 1, quelle que soit la position dans la liste.
  final datees = visites.where((v) => v.date != null).length;
  return [
    for (var i = 0; i < visites.length; i++)
      Visite(
        cle: visites[i].cle,
        date: visites[i].date,
        // Les visites sans date ne reçoivent pas de rang : leur donner un
        // numéro inventé mentirait sur la chronologie.
        numero: visites[i].date == null ? 0 : datees - i,
        documents: visites[i].documents,
      ),
  ];
}

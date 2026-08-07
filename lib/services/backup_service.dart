import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Sauvegarde et restauration des données du cabinet.
///
/// C'était le seul risque irréversible du projet. Une suppression malheureuse
/// — un profil effacé, un dossier vidé, un mauvais clic — ne se rattrapait
/// par rien : Firestore n'a pas de corbeille, et les exports planifiés de
/// Google exigent le plan payant.
///
/// Cette sauvegarde-ci ne demande rien de tout ça. Elle lit avec la session
/// déjà ouverte, donc à travers les mêmes règles de sécurité que l'app, et
/// écrit un fichier sur le disque du cabinet. Ce qui est sur le disque
/// survit à tout ce qui peut arriver au projet Firebase.
class BackupService {
  final FirebaseFirestore? _firestore;

  const BackupService({FirebaseFirestore? firestore}) : _firestore = firestore;

  /// Accès paresseux : construire le service ne doit pas exiger que Firebase
  /// soit initialisé. Sans ça, la sérialisation — qui est du pur calcul —
  /// devient intestable hors d'une app démarrée.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Sous-collections d'un profil.
  ///
  /// Firestore ne sait pas lister les sous-collections depuis un client :
  /// seul le SDK Admin en est capable. Il faut donc les nommer. Une
  /// collection oubliée ici est une collection qui n'est pas sauvegardée —
  /// d'où le test qui compare cette liste à ce que le code écrit vraiment.
  static const collectionsProfil = [
    'patients',
    'rendezvous',
    'salle_attente',
    'purchases',
    'daily_stats',
  ];

  /// Sous-collections d'un patient.
  static const collectionsPatient = ['forms'];

  /// Version du format. Un fichier plus récent que le code qui le relit est
  /// refusé plutôt que mal interprété.
  static const versionFormat = 1;

  // -----------------------------------------------------------------
  //  Sérialisation
  // -----------------------------------------------------------------

  /// Convertit une valeur Firestore en JSON, sans perdre son type.
  ///
  /// Un `Timestamp` écrit tel quel deviendrait une chaîne, et reviendrait
  /// en chaîne : les dates du cabinet cesseraient d'être des dates. Les
  /// types non représentables en JSON portent donc une étiquette.
  static dynamic encoder(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Timestamp) {
      return {'__type': 'timestamp', 'value': value.toDate().toIso8601String()};
    }
    if (value is DateTime) {
      return {'__type': 'timestamp', 'value': value.toIso8601String()};
    }
    if (value is GeoPoint) {
      return {
        '__type': 'geopoint',
        'lat': value.latitude,
        'lng': value.longitude,
      };
    }
    if (value is DocumentReference) {
      return {'__type': 'reference', 'path': value.path};
    }
    if (value is Blob) {
      return {'__type': 'blob', 'value': base64Encode(value.bytes)};
    }
    if (value is Iterable) return value.map(encoder).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), encoder(v)));
    }
    // Type inattendu : on garde sa représentation plutôt que de le perdre.
    return value.toString();
  }

  /// Reconstruit une valeur Firestore depuis le JSON.
  dynamic decoder(dynamic value) {
    if (value is List) return value.map(decoder).toList();
    if (value is! Map) return value;

    final type = value['__type'];
    if (type == null) {
      return value.map((k, v) => MapEntry(k.toString(), decoder(v)));
    }
    switch (type) {
      case 'timestamp':
        final d = DateTime.tryParse(value['value']?.toString() ?? '');
        return d == null ? null : Timestamp.fromDate(d);
      case 'geopoint':
        return GeoPoint(
          (value['lat'] as num).toDouble(),
          (value['lng'] as num).toDouble(),
        );
      case 'reference':
        return _db.doc(value['path'].toString());
      case 'blob':
        return Blob(base64Decode(value['value'].toString()));
      default:
        return null;
    }
  }

  // -----------------------------------------------------------------
  //  Export
  // -----------------------------------------------------------------

  /// Lit tout le cabinet et écrit un fichier de sauvegarde.
  ///
  /// [onProgress] reçoit une ligne lisible par étape : une sauvegarde qui
  /// semble figée pendant trente secondes donne envie de fermer la fenêtre.
  Future<BackupResult> exporter({
    required String parentUid,
    String? dossier,
    void Function(String etape)? onProgress,
  }) async {
    final debut = DateTime.now();
    var documents = 0;

    void avance(String message) => onProgress?.call(message);

    avance('Lecture du compte…');
    final racine = await _db.collection('users').doc(parentUid).get();
    documents++;

    final comptes = <String, dynamic>{};
    final profils = await _db
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .get();

    for (final profil in profils.docs) {
      avance('Profil ${profil.id}…');
      final contenu = <String, dynamic>{
        'donnees': encoder(profil.data()),
        'collections': <String, dynamic>{},
      };
      documents++;

      for (final nom in collectionsProfil) {
        final docs = await profil.reference.collection(nom).get();
        if (docs.docs.isEmpty) continue;

        final items = <String, dynamic>{};
        for (final d in docs.docs) {
          documents++;
          final item = <String, dynamic>{'donnees': encoder(d.data())};

          // Les documents des patients pendent sous le patient : les
          // oublier reviendrait à sauvegarder des dossiers vides.
          if (nom == 'patients') {
            final sous = <String, dynamic>{};
            for (final sousNom in collectionsPatient) {
              final f = await d.reference.collection(sousNom).get();
              if (f.docs.isEmpty) continue;
              documents += f.docs.length;
              sous[sousNom] = {
                for (final x in f.docs) x.id: encoder(x.data()),
              };
            }
            if (sous.isNotEmpty) item['collections'] = sous;
          }
          items[d.id] = item;
        }
        (contenu['collections'] as Map)[nom] = items;
      }
      comptes[profil.id] = contenu;
    }

    final contenu = {
      'version': versionFormat,
      'genereLe': DateTime.now().toIso8601String(),
      'parentUid': parentUid,
      'documents': documents,
      'racine': encoder(racine.data() ?? {}),
      'comptes': comptes,
    };

    avance('Écriture du fichier…');
    final cible = Directory(dossier ?? dossierParDefaut());
    if (!cible.existsSync()) cible.createSync(recursive: true);

    final fichier = File('${cible.path}${Platform.pathSeparator}${nomFichier()}');
    // `writeAsString` remplace le contenu d'un coup : un fichier de
    // sauvegarde à moitié écrit serait pire qu'aucun fichier.
    await fichier.writeAsString(
      const JsonEncoder.withIndent('  ').convert(contenu),
      flush: true,
    );

    return BackupResult(
      chemin: fichier.path,
      documents: documents,
      profils: profils.docs.length,
      octets: await fichier.length(),
      duree: DateTime.now().difference(debut),
    );
  }

  /// Dossier de sauvegarde par défaut.
  ///
  /// Le dossier Documents de l'utilisateur, pas celui de l'app : une
  /// sauvegarde rangée à côté de l'exécutable disparaît avec lui, et c'est
  /// exactement le scénario contre lequel elle protège.
  static String dossierParDefaut() {
    final base =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return '$base${Platform.pathSeparator}Documents'
        '${Platform.pathSeparator}Ordimed'
        '${Platform.pathSeparator}sauvegardes';
  }

  /// Nom horodaté, triable à l'œil comme au tri alphabétique.
  static String nomFichier({DateTime? maintenant}) {
    final d = maintenant ?? DateTime.now();
    String p(int v, [int n = 2]) => v.toString().padLeft(n, '0');
    return 'ordimed-${d.year}-${p(d.month)}-${p(d.day)}'
        '-${p(d.hour)}${p(d.minute)}.json';
  }

  /// Sauvegardes déjà présentes, de la plus récente à la plus ancienne.
  static List<File> sauvegardesExistantes({String? dossier}) {
    final rep = Directory(dossier ?? dossierParDefaut());
    if (!rep.existsSync()) return const [];
    final fichiers =
        rep
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    return fichiers;
  }

  // -----------------------------------------------------------------
  //  Restauration
  // -----------------------------------------------------------------

  /// Réécrit le contenu d'une sauvegarde dans Firestore.
  ///
  /// La restauration **fusionne** : elle réécrit ce que le fichier contient
  /// et ne supprime rien. Un fichier ancien ne doit pas effacer le travail
  /// fait depuis — récupérer trois dossiers perdus ne justifie pas d'en
  /// perdre trente autres.
  Future<RestoreReport> restaurer({
    required String parentUid,
    required File fichier,
    void Function(String etape)? onProgress,
  }) async {
    onProgress?.call('Lecture du fichier…');
    final brut = jsonDecode(await fichier.readAsString());
    if (brut is! Map) {
      throw const FormatException('Fichier de sauvegarde illisible');
    }

    final version = (brut['version'] as num?)?.toInt() ?? 0;
    if (version > versionFormat) {
      throw FormatException(
        'Sauvegarde en version $version, cette app lit jusqu\'à '
        '$versionFormat. Mets Ordimed à jour avant de restaurer.',
      );
    }

    final origine = brut['parentUid']?.toString();
    if (origine != null && origine != parentUid) {
      throw const FormatException(
        'Cette sauvegarde appartient à un autre cabinet.',
      );
    }

    final ecrivain = _Ecrivain(_db);
    final base = _db.collection('users').doc(parentUid);

    final racine = brut['racine'];
    if (racine is Map) {
      ecrivain.ajouter(base, decoder(racine) as Map<String, dynamic>);
    }

    final comptes = brut['comptes'];
    if (comptes is Map) {
      for (final entree in comptes.entries) {
        final profilId = entree.key.toString();
        onProgress?.call('Profil $profilId…');
        final profil = entree.value;
        if (profil is! Map) continue;

        final refProfil = base.collection('comptes').doc(profilId);
        final donnees = profil['donnees'];
        if (donnees is Map) {
          ecrivain.ajouter(refProfil, decoder(donnees) as Map<String, dynamic>);
        }

        final collections = profil['collections'];
        if (collections is! Map) continue;

        for (final col in collections.entries) {
          final items = col.value;
          if (items is! Map) continue;

          for (final item in items.entries) {
            final ref = refProfil
                .collection(col.key.toString())
                .doc(item.key.toString());
            final valeur = item.value;

            if (valeur is Map && valeur.containsKey('donnees')) {
              ecrivain.ajouter(
                ref,
                decoder(valeur['donnees']) as Map<String, dynamic>,
              );
              final sous = valeur['collections'];
              if (sous is Map) {
                for (final s in sous.entries) {
                  final docs = s.value;
                  if (docs is! Map) continue;
                  for (final d in docs.entries) {
                    ecrivain.ajouter(
                      ref.collection(s.key.toString()).doc(d.key.toString()),
                      decoder(d.value) as Map<String, dynamic>,
                    );
                  }
                }
              }
            } else if (valeur is Map) {
              ecrivain.ajouter(ref, decoder(valeur) as Map<String, dynamic>);
            }
            await ecrivain.viderSiPlein(onProgress);
          }
        }
      }
    }

    await ecrivain.vider();
    return RestoreReport(documents: ecrivain.total, fichier: fichier.path);
  }
}

/// Accumule les écritures et les envoie par lots.
///
/// Un batch Firestore plafonne à 500 opérations. Sans découpage, restaurer
/// un cabinet un peu vivant échouerait d'un bloc, et le message d'erreur ne
/// dirait pas pourquoi.
class _Ecrivain {
  static const _maxParLot = 400;

  final FirebaseFirestore _db;
  WriteBatch? _lot;
  int _enAttente = 0;
  int total = 0;

  _Ecrivain(this._db);

  void ajouter(DocumentReference ref, Map<String, dynamic> donnees) {
    _lot ??= _db.batch();
    _lot!.set(ref, donnees, SetOptions(merge: true));
    _enAttente++;
    total++;
  }

  Future<void> viderSiPlein([void Function(String)? onProgress]) async {
    if (_enAttente < _maxParLot) return;
    onProgress?.call('$total documents restaurés…');
    await vider();
  }

  Future<void> vider() async {
    final lot = _lot;
    if (lot == null || _enAttente == 0) return;
    await lot.commit();
    _lot = null;
    _enAttente = 0;
  }
}

class BackupResult {
  final String chemin;
  final int documents;
  final int profils;
  final int octets;
  final Duration duree;

  const BackupResult({
    required this.chemin,
    required this.documents,
    required this.profils,
    required this.octets,
    required this.duree,
  });

  String get taille {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).toStringAsFixed(0)} Ko';
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

class RestoreReport {
  final int documents;
  final String fichier;

  const RestoreReport({required this.documents, required this.fichier});
}

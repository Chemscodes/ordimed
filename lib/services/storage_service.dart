import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase/firebase_refs.dart';

/// Une pièce jointe telle qu'affichée dans un dossier patient.
class PieceJointe {
  /// Nom lisible, tel que choisi par la personne qui a déposé le fichier.
  final String nomAffiche;

  /// Nom réel de l'objet dans Storage (préfixé d'un horodatage pour éviter
  /// les collisions) — c'est celui qu'il faut passer à [StorageService.supprimer].
  final String nomStockage;

  final String url;
  final int taille;
  final DateTime ajouteLe;

  const PieceJointe({
    required this.nomAffiche,
    required this.nomStockage,
    required this.url,
    required this.taille,
    required this.ajouteLe,
  });
}

/// Pièces jointes d'un dossier patient (résultats de labo, radios scannées).
///
/// Firebase Storage uniquement. L'app peut basculer entre Firebase et un
/// backend Node/Mongo (`BackendConfig`), mais les pièces jointes n'existent
/// que côté Firebase — construire un serveur de fichiers côté Node était
/// hors du périmètre demandé. Sous le backend Mongo, cette fonctionnalité
/// ne fonctionne pas.
class StorageService {
  StorageService._internal();

  static final StorageService _instance = StorageService._internal();

  factory StorageService() => _instance;

  /// Même logique de propriété que Firestore (`cabinets/{uid}/...`) —
  /// voir `storage.rules`.
  Reference _dossier(String patientId) => FirebaseStorage.instance.ref(
    'cabinets/${FirebaseRefs.cabinetId}/patients/$patientId/documents',
  );

  /// Dépose un fichier choisi via `FilePicker.platform.pickFiles(withData: true)`.
  Future<void> deposer({
    required String patientId,
    required PlatformFile fichier,
  }) async {
    final bytes = fichier.bytes;
    if (bytes == null) {
      throw StateError('Fichier illisible');
    }
    final nomStockage = '${DateTime.now().millisecondsSinceEpoch}_${fichier.name}';
    await _dossier(patientId)
        .child(nomStockage)
        .putData(bytes, SettableMetadata(customMetadata: {'nomOriginal': fichier.name}));
  }

  /// Liste les pièces jointes d'un patient, les plus récentes d'abord.
  Future<List<PieceJointe>> lister(String patientId) async {
    final resultat = await _dossier(patientId).listAll();
    final pieces = await Future.wait(
      resultat.items.map((ref) async {
        final meta = await ref.getMetadata();
        return PieceJointe(
          nomAffiche: meta.customMetadata?['nomOriginal'] ?? ref.name,
          nomStockage: ref.name,
          url: await ref.getDownloadURL(),
          taille: meta.size ?? 0,
          ajouteLe: meta.timeCreated ?? DateTime.now(),
        );
      }),
    );
    pieces.sort((a, b) => b.ajouteLe.compareTo(a.ajouteLe));
    return pieces;
  }

  Future<void> supprimer({
    required String patientId,
    required String nomStockage,
  }) => _dossier(patientId).child(nomStockage).delete();
}

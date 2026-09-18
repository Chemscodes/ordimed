import 'backend_config.dart';
import 'cabinet_backend.dart';
import 'firebase/firebase_cabinet_backend.dart';
import 'mongo/mongo_cabinet_backend.dart';

/// Le point d'entrée des écrans vers les données du cabinet.
///
/// Ne contient plus aucune logique : elle choisit, entre Firestore et le
/// backend Node, celui que [BackendConfig] désigne. Les deux respectent
/// `CabinetBackend` et rendent les mêmes clés, si bien que les écrans
/// ignorent lequel répond.
///
/// Le nom est conservé parce que quinze fichiers écrivent
/// `ApiService.instance.…`. Le renommer en même temps qu'on change ce qu'il
/// y a derrière mélangerait deux modifications dans le même diff.
class ApiService {
  ApiService._();

  /// L'implémentation active.
  ///
  /// Résolu à chaque accès et non mis en cache : [BackendConfig.definir]
  /// change la valeur, et un champ figé au premier appel ferait écrire un
  /// écran dans l'ancienne base après la bascule.
  static CabinetBackend get instance => BackendConfig.surFirebase
      ? FirebaseCabinetBackend.instance
      : MongoCabinetBackend.instance;
}

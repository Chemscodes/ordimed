import 'auth_backend.dart';
import 'backend_config.dart';
import 'firebase/firebase_auth_backend.dart';
import 'mongo/mongo_auth_backend.dart';

/// L'ouverture de session, quel que soit le backend.
///
/// Comme `ApiService`, elle ne fait que déléguer : Firebase Auth ou le
/// jeton du backend Node, selon [BackendConfig]. Ce que voient `main.dart`
/// et les écrans de connexion ne change pas d'un cas à l'autre — un
/// identifiant de cabinet, et un flux qui prévient quand il bouge.
///
/// L'identité manipulée est celle du **cabinet**, pas de la personne : le
/// profil et son rôle viennent ensuite, par le code PIN.
class AuthService {
  AuthService._internal();

  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthBackend get _impl => BackendConfig.surFirebase
      ? FirebaseAuthBackend.instance
      : MongoAuthBackend.instance;

  String? get cabinetId => _impl.cabinetId;

  /// Remplace `authStateChanges()`. Émet l'état courant à l'abonnement.
  Stream<String?> sessionChanges() => _impl.sessionChanges();

  /// Rouvre la session enregistrée, si elle tient encore.
  ///
  /// Sans ça le médecin ressaisirait son mot de passe à chaque lancement.
  Future<String?> restaurer() => _impl.restaurer();

  Future<String> signIn(String email, String password) =>
      _impl.signIn(email, password);

  Future<String> signUp(String email, String password) =>
      _impl.signUp(email, password);

  Future<void> signOut() => _impl.signOut();
}

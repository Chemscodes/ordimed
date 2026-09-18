/// L'ouverture de session, indépendamment de qui la garde.
///
/// Firebase Auth gère seul la persistance et le renouvellement du jeton ;
/// le backend Node demande de le faire à la main. Les deux se ramènent ici
/// au même contrat, pour que `main.dart` et les écrans de connexion
/// n'aient pas à savoir lequel répond.
///
/// L'identité manipulée est celle du **cabinet**, pas de la personne : le
/// profil et son rôle viennent ensuite, par le code PIN. C'est pour ça que
/// tout ce qui sort d'ici est un identifiant de cabinet.
abstract class AuthBackend {
  /// L'identifiant du cabinet connecté, `null` hors session.
  String? get cabinetId;

  /// Remplace `authStateChanges()`.
  ///
  /// Doit émettre l'état courant à l'abonnement : un `StreamBuilder`
  /// branché après le démarrage resterait sinon bloqué sur son indicateur
  /// de chargement.
  Stream<String?> sessionChanges();

  /// Rouvre la session enregistrée, si elle tient encore.
  ///
  /// Rend `null` quand il n'y en a pas, ou qu'elle n'est plus valable.
  /// Ne doit pas jeter la session pour une simple coupure réseau : le
  /// serveur injoignable au lancement est un incident fréquent en cabinet,
  /// et reconnecter le médecin à chaque fois serait une punition.
  Future<String?> restaurer();

  Future<String> signIn(String email, String password);

  /// Crée le cabinet **et** son médecin principal.
  ///
  /// Les deux vont ensemble : un cabinet sans profil est inutilisable, on
  /// ne peut même pas s'y connecter.
  Future<String> signUp(String email, String password);

  Future<void> signOut();
}

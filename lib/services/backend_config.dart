import 'package:shared_preferences/shared_preferences.dart';

/// Les deux bases possibles pour un cabinet.
///
/// Le choix est celui du déploiement, pas de l'utilisateur : un cabinet qui
/// n'a pas de poste serveur prend [Backend.firebase] et n'a rien à
/// administrer ; un cabinet qui tient à garder ses données chez lui prend
/// [Backend.mongo] et fait tourner le backend Node sur un poste.
enum Backend {
  /// Firestore en direct. Pas de serveur à installer, synchronisation
  /// native, mais la logique métier redescend dans l'app.
  firebase,

  /// Le backend Node + MongoDB. Logique métier côté serveur, transactions
  /// réelles, mais il faut un poste qui l'héberge.
  mongo,
}

/// Le backend actif, et la façon d'en changer.
///
/// La bascule est lue une fois au démarrage puis figée pour la session :
/// les écrans gardent des abonnements ouverts sur la base active, et les
/// rebrancher à chaud demanderait de tous les fermer proprement. Changer de
/// backend passe donc par [definir] puis un redémarrage — ce qui est aussi
/// le moment où l'on veut vérifier que l'autre base répond.
class BackendConfig {
  BackendConfig._();

  static const _cle = 'ordimed.backend';

  /// Permet de figer le backend à la compilation, pour produire un binaire
  /// destiné à un cabinet qui n'aura jamais à choisir.
  static const _impose = String.fromEnvironment('BACKEND', defaultValue: '');

  static Backend _actif = Backend.firebase;

  /// Le backend de cette session.
  static Backend get actif => _actif;

  /// Vrai quand les données viennent de Firestore.
  ///
  /// Les écrans qui doivent s'adapter — le réglage de l'adresse du serveur
  /// n'a aucun sens sur Firebase — lisent ceci plutôt que de comparer
  /// l'énumération eux-mêmes.
  static bool get surFirebase => _actif == Backend.firebase;

  static bool get surMongo => _actif == Backend.mongo;

  /// Relit le choix enregistré. À appeler avant `runApp`.
  static Future<Backend> restaurer() async {
    if (_impose.isNotEmpty) {
      _actif = _depuisNom(_impose);
      return _actif;
    }
    final prefs = await SharedPreferences.getInstance();
    _actif = _depuisNom(prefs.getString(_cle) ?? '');
    return _actif;
  }

  /// Enregistre le backend à utiliser au prochain lancement.
  ///
  /// La valeur courante change aussi, mais les flux déjà ouverts continuent
  /// de lire l'ancienne base : c'est le redémarrage qui fait la bascule.
  static Future<void> definir(Backend backend) async {
    _actif = backend;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, backend.name);
  }

  /// Firebase par défaut : c'est la cible principale, et un cabinet qui
  /// n'a rien configuré n'a pas de serveur Node à joindre.
  static Backend _depuisNom(String nom) =>
      nom == Backend.mongo.name ? Backend.mongo : Backend.firebase;
}

import 'dart:async';

import '../api_client.dart';
import '../auth_backend.dart';
import '../realtime_service.dart';
import 'mongo_cabinet_backend.dart';

/// L'ouverture de session contre le backend Node.
///
/// Firebase Auth gérait seul la persistance et prévenait par
/// `authStateChanges()`. Ici il faut le faire : le jeton est relu au
/// démarrage, et [sessionChanges] joue le rôle du flux d'origine.
class MongoAuthBackend implements AuthBackend {
  MongoAuthBackend._() {
    // Une session expirée côté serveur doit ramener à l'écran de connexion,
    // pas laisser quinze écrans afficher « jeton invalide ».
    _api.sessionPerdue.listen((_) {
      _cabinetId = null;
      _session.add(null);
    });
  }

  static final MongoAuthBackend instance = MongoAuthBackend._();

  final _api = ApiClient.instance;
  final _cab = MongoCabinetBackend.instance;

  final _session = StreamController<String?>.broadcast();

  String? _cabinetId;

  @override
  String? get cabinetId => _cabinetId;

  @override
  Stream<String?> sessionChanges() async* {
    yield _cabinetId;
    yield* _session.stream;
  }

  @override
  Future<String?> restaurer() async {
    await _api.restaurer();
    if (!_api.connecte) return null;

    try {
      // Le jeton est peut-être expiré ou signé d'un autre secret : seule une
      // vraie requête le dit.
      final cabinet = await _cab.cabinet();
      _cabinetId = cabinet['id']?.toString();
      // La connexion Socket.IO est ouverte par [_apresConnexion] lors d'une
      // connexion ; ici aucune n'a lieu, il faut donc l'ouvrir soi-même.
      RealtimeService.instance.connecter();
      _session.add(_cabinetId);
      return _cabinetId;
    } on ApiException catch (e) {
      // Serveur injoignable au lancement : on ne jette pas la session pour
      // autant, mais on ne peut pas entrer non plus.
      if (e.estReseau) return null;
      await _api.deconnecter();
      return null;
    }
  }

  @override
  Future<String> signIn(String email, String password) async {
    final r = Map<String, dynamic>.from(
      await _api.post('/auth/login', {'email': email, 'password': password})
          as Map,
    );
    return _apresConnexion(r);
  }

  /// Le backend crée le cabinet *et* son médecin principal : les deux
  /// allaient ensemble dans `signup_page.dart`, et un cabinet sans profil
  /// est inutilisable.
  @override
  Future<String> signUp(String email, String password) async {
    final r = Map<String, dynamic>.from(
      await _api.post('/auth/register', {'email': email, 'password': password})
          as Map,
    );
    return _apresConnexion(r);
  }

  Future<String> _apresConnexion(Map<String, dynamic> reponse) async {
    await _api.memoriserJeton(reponse['token'].toString());
    // Le temps réel n'a de sens qu'authentifié : le salon est déduit du
    // jeton, pas demandé par le client.
    RealtimeService.instance.connecter();
    _cabinetId = (reponse['cabinet'] as Map)['id'].toString();
    _session.add(_cabinetId);
    return _cabinetId!;
  }

  @override
  Future<void> signOut() async {
    RealtimeService.instance.deconnecter();
    await _api.deconnecter();
    _cabinetId = null;
    _session.add(null);
  }
}

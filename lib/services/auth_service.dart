import 'dart:async';

import 'api_client.dart';
import 'api_service.dart';
import 'realtime_service.dart';

/// L'authentification, désormais contre le backend.
///
/// Firebase Auth gérait seul la persistance de session et prévenait par
/// `authStateChanges()`. Ici il faut le faire : le jeton est relu au
/// démarrage, et [sessionChanges] joue le rôle du flux d'origine pour que
/// `main.dart` garde sa forme.
///
/// La différence à connaître : Firebase renvoyait un `User` ; ici on ne
/// manipule que l'identifiant du cabinet. Le reste de l'app ne s'en servait
/// que pour `user.uid`, donc rien ne se perd.
class AuthService {
  AuthService._internal() {
    // Une session expirée côté serveur doit ramener à l'écran de connexion,
    // pas laisser quinze écrans afficher « jeton invalide ».
    _api.sessionPerdue.listen((_) => _session.add(null));
  }

  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  final _api = ApiClient.instance;
  final _service = ApiService.instance;

  final _session = StreamController<String?>.broadcast();

  String? _cabinetId;

  String? get cabinetId => _cabinetId;

  /// Remplace `authStateChanges()`.
  ///
  /// Émet immédiatement l'état courant : un `StreamBuilder` branché après
  /// le démarrage resterait sinon bloqué sur son indicateur de chargement.
  Stream<String?> sessionChanges() async* {
    yield _cabinetId;
    yield* _session.stream;
  }

  /// Rouvre la session enregistrée, si elle tient encore.
  ///
  /// Sans ça le médecin ressaisirait son mot de passe à chaque lancement —
  /// Firebase le faisait tout seul.
  Future<String?> restaurer() async {
    await _api.restaurer();
    if (!_api.connecte) return null;

    try {
      // Le jeton est peut-être expiré ou signé d'un autre secret : seule une
      // vraie requête le dit.
      final cabinet = await _service.cabinet();
      _cabinetId = cabinet['id']?.toString();
      // La connexion Socket.IO est ouverte par ApiService lors d'une
      // connexion ; ici aucun appel de connexion n'a lieu, il faut donc
      // l'ouvrir soi-meme.
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

  Future<String> signIn(String email, String password) async {
    final r = await _service.connecter(email, password);
    _cabinetId = r['cabinet']['id'].toString();
    _session.add(_cabinetId);
    return _cabinetId!;
  }

  Future<String> signUp(String email, String password) async {
    final r = await _service.inscrire(email, password);
    _cabinetId = r['cabinet']['id'].toString();
    _session.add(_cabinetId);
    return _cabinetId!;
  }

  Future<void> signOut() async {
    await _service.deconnecter();
    _cabinetId = null;
    _session.add(null);
  }
}

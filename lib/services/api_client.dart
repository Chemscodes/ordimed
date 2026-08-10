import 'dart:async';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le client HTTP vers le backend Node.
///
/// Remplace `FirebaseFirestore.instance` et `FirebaseAuth.instance`. Firebase
/// gérait seul le jeton, sa persistance et son renouvellement ; ici c'est
/// notre travail, et c'est tout ce que fait cette classe.
///
/// Elle ne connaît aucune entité du cabinet : `api_service.dart` s'en charge.
/// La séparation compte, parce que la gestion du jeton doit rester au même
/// endroit — un second endroit qui pose l'en-tête `Authorization`, et une
/// session expirée cesse d'être détectée quelque part.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// Adresse par defaut, si le poste n'a jamais ete configure.
  ///
  /// `--dart-define=API_URL=...` permet de la changer a la compilation, mais
  /// ce n'est pas la voie normale : un cabinet a plusieurs postes, et seul
  /// l'un d'eux fait tourner le serveur. Les autres pointent vers son
  /// adresse sur le reseau local.
  static const String urlParDefaut = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:4000',
  );

  static const _cleJeton = 'ordimed.jeton';
  static const _cleServeur = 'ordimed.serveur';

  String _baseUrl = urlParDefaut;

  /// L'adresse du serveur, telle que ce poste la connait.
  ///
  /// Reglable a l'execution : figer l'adresse a la compilation obligerait a
  /// produire un binaire par cabinet, avec son IP en dur.
  String get baseUrl => _baseUrl;

  late final Dio _dio = _construire();

  String? _jeton;

  /// Prévient quand la session tombe.
  ///
  /// L'app ne peut pas se contenter d'un 401 par requête : quinze écrans
  /// écoutent en même temps, ils afficheraient quinze messages. Ce flux
  /// permet à un seul endroit de renvoyer vers la connexion.
  final _sessionPerdue = StreamController<void>.broadcast();

  Stream<void> get sessionPerdue => _sessionPerdue.stream;

  String? get jeton => _jeton;
  bool get connecte => _jeton != null;

  Dio _construire() {
    final dio = Dio(
      BaseOptions(
        // Renseigne a chaque requete par l'intercepteur : le serveur peut
        // changer sans reconstruire le client.
        baseUrl: '$_baseUrl/api',
        // Un cabinet sur ADSL algérienne : large, mais pas infini. Sans
        // délai, une coupure fait tourner le rond indéfiniment.
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        // On lit nous-mêmes les codes d'erreur : Dio ne doit pas lever
        // avant qu'on ait pu extraire le message du backend.
        validateStatus: (code) => code != null && code < 500,
        contentType: 'application/json',
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Suit un changement d'adresse en cours de session.
          options.baseUrl = '$_baseUrl/api';
          if (_jeton != null) {
            options.headers['Authorization'] = 'Bearer $_jeton';
          }
          handler.next(options);
        },
        onResponse: (reponse, handler) {
          if (reponse.statusCode == 401) {
            // Le backend distingue « expiré » de « invalide ». Dans les
            // deux cas la session est finie, mais seul le premier mérite
            // qu'on propose de se reconnecter sans alarmer.
            _oublierJeton();
            _sessionPerdue.add(null);
          }
          handler.next(reponse);
        },
      ),
    );

    return dio;
  }

  /// Recharge le jeton au démarrage.
  ///
  /// Firebase rouvrait la session tout seul. Sans ça, le médecin
  /// ressaisirait son mot de passe à chaque lancement.
  Future<void> restaurer() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_cleServeur) ?? urlParDefaut;
    _jeton = prefs.getString(_cleJeton);
  }

  /// Change le serveur auquel ce poste s'adresse.
  ///
  /// La session est abandonnee : un jeton signe par un serveur n'a aucune
  /// valeur pour un autre, et le garder ferait echouer chaque requete avec
  /// un 401 incomprehensible.
  Future<void> definirServeur(String url) async {
    var propre = url.trim();
    if (propre.isEmpty) propre = urlParDefaut;
    // Une adresse saisie a la main arrive souvent sans schema ni avec une
    // barre finale.
    if (!propre.startsWith('http://') && !propre.startsWith('https://')) {
      propre = 'http://$propre';
    }
    while (propre.endsWith('/')) {
      propre = propre.substring(0, propre.length - 1);
    }

    if (propre == _baseUrl) return;
    _baseUrl = propre;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleServeur, propre);
    await _oublierJeton();
    _sessionPerdue.add(null);
  }

  /// Verifie qu'un serveur repond, sans toucher a la configuration.
  ///
  /// Sert au bouton « Tester » : dire « injoignable » avant d'enregistrer
  /// evite de laisser le poste sur une adresse fausse.
  Future<bool> tester(String url) async {
    var propre = url.trim();
    if (!propre.startsWith('http')) propre = 'http://$propre';
    while (propre.endsWith('/')) {
      propre = propre.substring(0, propre.length - 1);
    }
    try {
      final sonde = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final r = await sonde.get('$propre/health');
      return r.statusCode == 200 && r.data is Map && r.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> memoriserJeton(String jeton) async {
    _jeton = jeton;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleJeton, jeton);
  }

  Future<void> _oublierJeton() async {
    _jeton = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleJeton);
  }

  Future<void> deconnecter() => _oublierJeton();

  // -----------------------------------------------------------------
  //  Verbes
  // -----------------------------------------------------------------

  Future<dynamic> get(String chemin, {Map<String, dynamic>? params}) =>
      _executer(() => _dio.get(chemin, queryParameters: params));

  Future<dynamic> post(String chemin, [Map<String, dynamic>? corps]) =>
      _executer(() => _dio.post(chemin, data: corps));

  Future<dynamic> put(String chemin, [Map<String, dynamic>? corps]) =>
      _executer(() => _dio.put(chemin, data: corps));

  Future<dynamic> delete(String chemin) =>
      _executer(() => _dio.delete(chemin));

  /// Exécute et traduit les échecs en [ApiException].
  ///
  /// Le reste de l'app ne doit jamais voir un `DioException` : elle
  /// afficherait « DioException [connection error] » à un médecin.
  Future<dynamic> _executer(Future<Response> Function() appel) async {
    late final Response reponse;
    try {
      reponse = await appel();
    } on DioException catch (e) {
      throw ApiException.depuisDio(e);
    }

    final code = reponse.statusCode ?? 0;
    if (code >= 200 && code < 300) return reponse.data;

    final donnees = reponse.data;
    final message = donnees is Map && donnees['error'] != null
        ? donnees['error'].toString()
        : 'Erreur $code';

    throw ApiException(
      message: message,
      code: code,
      donnees: donnees is Map ? Map<String, dynamic>.from(donnees) : null,
    );
  }
}

/// Un échec d'appel, dit en français.
class ApiException implements Exception {
  final String message;

  /// Code HTTP. `0` quand la requête n'est jamais partie.
  final int code;

  /// Corps de la réponse, quand le backend en dit plus — le conflit de
  /// créneau renvoie le patient qui occupe la place.
  final Map<String, dynamic>? donnees;

  const ApiException({
    required this.message,
    required this.code,
    this.donnees,
  });

  factory ApiException.depuisDio(DioException e) {
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Le serveur met trop de temps à répondre',
      DioExceptionType.connectionError =>
        'Serveur injoignable. Vérifie que le poste serveur est allumé '
            'et connecté au même réseau.',
      DioExceptionType.cancel => 'Requête annulée',
      _ => 'Connexion au serveur impossible',
    };
    return ApiException(message: message, code: 0);
  }

  /// Vrai quand le problème est le réseau, pas la demande.
  ///
  /// Firestore absorbait les coupures grâce à son cache local. Ici il faut
  /// distinguer « le serveur refuse » de « le serveur ne répond pas » :
  /// seul le second se règle en attendant.
  bool get estReseau => code == 0;

  bool get estAuth => code == 401;
  bool get estConflit => code == 409;
  bool get estIntrouvable => code == 404;

  @override
  String toString() => message;
}

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

  /// Adresse du backend.
  ///
  /// `--dart-define=API_URL=http://192.168.1.20:4000` pour pointer un autre
  /// poste : sur un vrai cabinet, le serveur ne tourne pas sur la machine
  /// de l'assistant.
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:4000',
  );

  static const _cleJeton = 'ordimed.jeton';

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
        baseUrl: '$baseUrl/api',
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
    _jeton = prefs.getString(_cleJeton);
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

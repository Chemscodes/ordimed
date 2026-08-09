import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Suivi des erreurs en production.
///
/// Objectif : savoir ce qui casse chez un cabinet sans attendre son appel.
///
/// Deux destinations, volontairement :
///  - un fichier local, qui fonctionne toujours (hors ligne, non connecte,
///    plantage au demarrage) et que l'on peut demander par e-mail ;
///  - la collection `error_logs` du backend, consultable a
///    distance depuis la console Firebase.
///
/// Confidentialite : le message et la pile sont tronques, et aucune donnee
/// patient n'est jointe volontairement. Un message d'exception peut
/// toutefois contenir une valeur metier — d'ou la troncature stricte et la
/// conservation dans l'espace du cabinet lui-meme, jamais ailleurs.
class ErrorReporter {
  ErrorReporter._internal();
  static final ErrorReporter _instance = ErrorReporter._internal();
  factory ErrorReporter() => _instance;

  static const int _maxMessageChars = 500;
  static const int _maxStackChars = 2000;
  static const int _maxPerSession = 25;
  static const Duration _sameErrorCooldown = Duration(minutes: 5);

  bool _installed = false;
  int _sent = 0;
  final Map<String, DateTime> _lastSeen = {};
  File? _logFile;

  /// Installe les gestionnaires globaux. A appeler une seule fois, apres
  /// l'initialisation de Firebase.
  void install({String appVersion = 'inconnue'}) {
    if (_installed) return;
    _installed = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      unawaited(
        report(
          details.exception,
          details.stack,
          origin: 'flutter',
          appVersion: appVersion,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        report(error, stack, origin: 'platform', appVersion: appVersion),
      );
      return true;
    };
  }

  /// Enregistre une erreur. Ne leve jamais : un echec de journalisation ne
  /// doit pas provoquer une seconde erreur.
  Future<void> report(
    Object error,
    StackTrace? stack, {
    String origin = 'manuel',
    String appVersion = 'inconnue',
    Map<String, dynamic>? context,
  }) async {
    try {
      final message = _truncate(error.toString(), _maxMessageChars);
      final signature = '$origin|${message.hashCode}';

      // Anti-inondation : une boucle de rendu peut lever cent fois par
      // seconde. On ne garde qu'une occurrence par signature et par fenetre.
      final now = DateTime.now();
      final last = _lastSeen[signature];
      if (last != null && now.difference(last) < _sameErrorCooldown) return;
      _lastSeen[signature] = now;

      if (_sent >= _maxPerSession) return;
      _sent++;

      final stackText = _truncate(stack?.toString() ?? '', _maxStackChars);

      await _writeLocal(now, origin, message, stackText);
      await _writeRemote(origin, message, stackText, appVersion, context);
    } catch (_) {
      // Silence volontaire.
    }
  }

  Future<void> _writeLocal(
    DateTime when,
    String origin,
    String message,
    String stackText,
  ) async {
    try {
      final file = _logFile ??= await _openLogFile();
      if (file == null) return;
      final buffer = StringBuffer()
        ..writeln('--- ${when.toIso8601String()} [$origin] ---')
        ..writeln(message);
      if (stackText.isNotEmpty) buffer.writeln(stackText);
      await file.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  Future<File?> _openLogFile() async {
    try {
      final dir = Directory.systemTemp.createTempSync('ordimed_logs_');
      final file = File('${dir.path}${Platform.pathSeparator}ordimed.log');
      debugPrint('Journal des erreurs : ${file.path}');
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRemote(
    String origin,
    String message,
    String stackText,
    String appVersion,
    Map<String, dynamic>? context,
  ) async {
    try {
      // La route accepte les signalements sans jeton : une erreur peut
      // survenir avant toute connexion, et c'est souvent celle-la qui
      // interesse le plus. Firestore, lui, les refusait faute de regle.
      await ApiService.instance
          .signalerErreur({
            'message': message,
            'stack': stackText,
            'origin': origin,
            'appVersion': appVersion,
            'platform': Platform.operatingSystem,
            'osVersion': Platform.operatingSystemVersion,
            if (context != null) 'context': context.toString(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Signaler une erreur ne doit jamais en creer une seconde.
    }
  }

  String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}… (tronque)';
  }
}

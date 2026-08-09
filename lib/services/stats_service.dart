import 'api_service.dart';

/// Les statistiques du cabinet.
///
/// `daily_stats` reste un document agrege par jour, comme dans Firestore :
/// le graphique lit une poignee de documents au lieu de parcourir tous les
/// versements du cabinet.
///
/// Ce qui change : les increments ne partent plus de l'app. Le backend met a
/// jour la statistique **dans la meme transaction** que le versement ou
/// l'achat. Avant, c'etait une seconde ecriture apres coup — si elle
/// echouait, les chiffres du cabinet cessaient de tomber juste sans que
/// personne ne le sache.
class StatsService {
  StatsService._internal();

  static final StatsService _instance = StatsService._internal();

  factory StatsService() => _instance;

  final _api = ApiService.instance;

  DateTime startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static String dayKeyOf(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// La statistique d'un jour. `null` s'il ne s'est rien passe.
  Stream<Map<String, dynamic>?> dailyStatsDoc({
    required String parentUid,
    required String dayKey,
  }) => _api
      .statsFlux(depuis: dayKey)
      .map((liste) {
        for (final s in liste) {
          if (s['dayKey'] == dayKey) return s;
        }
        return null;
      });

  Stream<List<Map<String, dynamic>>> recentDailyStats({
    required String parentUid,
    int limit = 7,
  }) => _api.statsFlux().map(
    (liste) => liste.length <= limit ? liste : liste.sublist(0, limit),
  );

  /// Ces deux methodes n'ont plus rien a faire.
  ///
  /// Le versement et l'achat mettent eux-memes a jour la statistique du
  /// jour, cote serveur et dans la meme transaction. Les appels sont
  /// conserves sans effet pour ne pas toucher aux appelants dans le meme
  /// commit ; ils disparaitront avec eux.
  Future<void> addVersement({
    required String parentUid,
    required double montant,
    String? doctorId,
    String? doctorName,
  }) async {}

  Future<void> addAchat({
    required String parentUid,
    required double montant,
  }) async {}
}

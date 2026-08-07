import 'coerce.dart';
import 'parcours.dart';

/// Horaires du cabinet et découpage de la journée.
///
/// Les rendez-vous se prenaient avec un `showDatePicker` puis un
/// `showTimePicker` : n'importe quelle minute de n'importe quel jour, sans
/// que rien ne regarde ce qui était déjà pris. Deux patients pouvaient être
/// planifiés à 10h00 chez le même médecin, et personne ne l'apprenait avant
/// que les deux se présentent.
class HorairesCabinet {
  /// Minutes depuis minuit. 8h00 = 480.
  final int ouverture;
  final int fermeture;

  /// Pause déjeuner. `null` quand le cabinet ne ferme pas.
  final int? pauseDebut;
  final int? pauseFin;

  /// Durée d'un créneau, en minutes.
  final int duree;

  /// Jours travaillés, au format `DateTime.monday`..`DateTime.sunday`.
  ///
  /// Par défaut samedi à jeudi : la semaine algérienne. Le vendredi est le
  /// jour de repos, pas le dimanche — un défaut copié d'Europe aurait
  /// affiché des créneaux les mauvais jours.
  final Set<int> joursOuvres;

  const HorairesCabinet({
    this.ouverture = 8 * 60,
    this.fermeture = 17 * 60,
    this.pauseDebut = 12 * 60,
    this.pauseFin = 13 * 60,
    this.duree = 20,
    this.joursOuvres = const {
      DateTime.saturday,
      DateTime.sunday,
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
    },
  });

  factory HorairesCabinet.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const HorairesCabinet();
    const defaut = HorairesCabinet();

    final jours = data['joursOuvres'];
    final ouverture = asIntOrNull(data['ouverture']) ?? defaut.ouverture;
    var fermeture = asIntOrNull(data['fermeture']) ?? defaut.fermeture;
    // Une fermeture avant l'ouverture ne produirait aucun créneau, sans
    // qu'on comprenne pourquoi. On préfère revenir au défaut.
    if (fermeture <= ouverture) fermeture = defaut.fermeture;

    final duree = asIntOrNull(data['duree']) ?? defaut.duree;

    return HorairesCabinet(
      ouverture: ouverture,
      fermeture: fermeture,
      pauseDebut: asIntOrNull(data['pauseDebut']),
      pauseFin: asIntOrNull(data['pauseFin']),
      duree: duree < 5 ? defaut.duree : duree,
      joursOuvres: jours is Iterable && jours.isNotEmpty
          ? jours.map(asInt).where((j) => j >= 1 && j <= 7).toSet()
          : defaut.joursOuvres,
    );
  }

  Map<String, dynamic> toMap() => {
    'ouverture': ouverture,
    'fermeture': fermeture,
    'pauseDebut': pauseDebut,
    'pauseFin': pauseFin,
    'duree': duree,
    'joursOuvres': joursOuvres.toList()..sort(),
  };

  bool estOuvertLe(DateTime jour) => joursOuvres.contains(jour.weekday);

  /// Vrai si [minute] tombe dans la pause déjeuner.
  bool estEnPause(int minute, int dureeCreneau) {
    final d = pauseDebut, f = pauseFin;
    if (d == null || f == null || f <= d) return false;
    // Un créneau qui mord sur la pause est exclu, pas seulement celui qui
    // commence dedans : une consultation de 13h qui déborde n'en est pas
    // une qui tient.
    return minute < f && (minute + dureeCreneau) > d;
  }

  /// Tous les créneaux d'une journée, ouverts ou non.
  List<Creneau> creneauxDuJour(DateTime jour, {int? dureeCreneau}) {
    if (!estOuvertLe(jour)) return const [];
    final d = dureeCreneau ?? duree;
    final base = DateTime(jour.year, jour.month, jour.day);

    final creneaux = <Creneau>[];
    for (var m = ouverture; m + d <= fermeture; m += duree) {
      if (estEnPause(m, d)) continue;
      creneaux.add(
        Creneau(debut: base.add(Duration(minutes: m)), duree: d),
      );
    }
    return creneaux;
  }

  static String formatHeure(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Une plage de temps chez un médecin.
class Creneau {
  final DateTime debut;
  final int duree;

  const Creneau({required this.debut, required this.duree});

  DateTime get fin => debut.add(Duration(minutes: duree));

  /// Deux plages se chevauchent si l'une commence avant que l'autre finisse.
  ///
  /// Les bornes ne comptent pas : un rendez-vous de 10h00 à 10h20 et un de
  /// 10h20 à 10h40 se suivent, ils ne se chevauchent pas.
  bool chevauche(Creneau autre) =>
      debut.isBefore(autre.fin) && autre.debut.isBefore(fin);

  String get libelle {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(debut.hour)}:${p(debut.minute)}';
  }

  String get plage {
    String p(int v) => v.toString().padLeft(2, '0');
    return '$libelle – ${p(fin.hour)}:${p(fin.minute)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Creneau && other.debut == debut && other.duree == duree;

  @override
  int get hashCode => Object.hash(debut, duree);
}

/// Un créneau déjà pris.
class Occupation {
  final String rdvId;
  final String patient;
  final Creneau creneau;
  final EtapeParcours etape;

  const Occupation({
    required this.rdvId,
    required this.patient,
    required this.creneau,
    required this.etape,
  });

  /// Un rendez-vous annulé ou manqué ne bloque plus son créneau.
  ///
  /// Sinon une annulation laisserait un trou inutilisable dans la journée,
  /// et l'assistant contournerait l'outil pour recaser le patient.
  bool get bloque => !etape.estManquee;

  /// Relit un document de rendez-vous.
  ///
  /// Renvoie `null` quand la date manque : un rendez-vous sans heure ne
  /// prend aucun créneau, et le supposer à minuit fabriquerait un conflit.
  static Occupation? fromRendezVous(
    String rdvId,
    Map<String, dynamic> data, {
    int dureeParDefaut = 20,
  }) {
    final debut = asDateOrNull(data['datetime']);
    if (debut == null) return null;

    final nom = [
      asText(data['patientNom']),
      asText(data['patientPrenom']),
    ].where((s) => s.isNotEmpty).join(' ');

    return Occupation(
      rdvId: rdvId,
      patient: nom.isEmpty ? 'Patient' : nom,
      creneau: Creneau(
        debut: debut,
        duree: asIntOrNull(data['duree']) ?? dureeParDefaut,
      ),
      etape: EtapeParcours.fromRendezVous(data),
    );
  }
}

/// Ce qu'on peut dire d'un créneau à un instant donné.
enum EtatCreneau {
  libre,
  occupe,
  passe,

  /// Hors des heures d'ouverture, ou pendant la pause.
  ferme,
}

/// Cherche le rendez-vous qui empêche de poser [creneau].
///
/// [ignorer] sert au déplacement d'un rendez-vous : il ne doit pas se
/// détecter lui-même comme un conflit.
Occupation? conflitPour(
  Creneau creneau,
  Iterable<Occupation> occupations, {
  String? ignorer,
}) {
  for (final o in occupations) {
    if (!o.bloque) continue;
    if (ignorer != null && o.rdvId == ignorer) continue;
    if (o.creneau.chevauche(creneau)) return o;
  }
  return null;
}

/// État d'un créneau, tout pris en compte.
EtatCreneau etatDe(
  Creneau creneau,
  Iterable<Occupation> occupations, {
  DateTime? maintenant,
  String? ignorer,
}) {
  final now = maintenant ?? DateTime.now();
  // Le passé d'abord : un créneau de ce matin déjà occupé reste avant tout
  // un créneau qu'on ne peut plus proposer.
  if (creneau.debut.isBefore(now)) return EtatCreneau.passe;
  if (conflitPour(creneau, occupations, ignorer: ignorer) != null) {
    return EtatCreneau.occupe;
  }
  return EtatCreneau.libre;
}

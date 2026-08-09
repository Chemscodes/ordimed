import 'package:flutter/material.dart';

import '../core/creneaux.dart';
import '../core/format.dart' as fmt;
import '../services/api_service.dart';
import '../services/rendezvous_repository.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../ui/info_display.dart';

/// Choix d'un créneau dans la journée d'un médecin.
///
/// Avant : `showDatePicker` puis `showTimePicker`. N'importe quelle minute,
/// sans que rien ne regarde ce qui était déjà pris. Deux patients pouvaient
/// être planifiés à 10h00 chez le même médecin, et personne ne l'apprenait
/// avant que les deux se présentent à l'accueil.
///
/// Ici la journée est montrée telle qu'elle est : ce qui est libre, ce qui
/// est pris et par qui, ce qui est déjà passé. On ne peut pas choisir une
/// heure occupée — pas parce qu'un message le refuse après coup, mais parce
/// qu'elle n'est pas cliquable.
class ChoixCreneauPage extends StatefulWidget {
  final String parentUid;
  final String doctorId;
  final String doctorName;

  /// Nom du patient, affiché en tête : on choisit un créneau *pour
  /// quelqu'un*, et l'oublier fait poser le rendez-vous au mauvais dossier.
  final String patient;

  final DateTime? jourInitial;

  /// Rendez-vous en cours de déplacement, qui ne doit pas se compter
  /// lui-même comme un conflit.
  final String? ignorerRdvId;

  const ChoixCreneauPage({
    super.key,
    required this.parentUid,
    required this.doctorId,
    required this.doctorName,
    required this.patient,
    this.jourInitial,
    this.ignorerRdvId,
  });

  @override
  State<ChoixCreneauPage> createState() => _ChoixCreneauPageState();
}

class _ChoixCreneauPageState extends State<ChoixCreneauPage> {
  late DateTime _jour;
  HorairesCabinet _horaires = const HorairesCabinet();
  bool _chargement = true;

  /// Durée choisie pour ce rendez-vous. Par défaut celle du cabinet.
  int? _duree;

  @override
  void initState() {
    super.initState();
    final base = widget.jourInitial ?? DateTime.now();
    _jour = DateTime(base.year, base.month, base.day);
    _chargerHoraires();
  }

  Future<void> _chargerHoraires() async {
    try {
      final cabinet = await ApiService.instance.cabinet();
      final data = cabinet['horaires'];
      if (mounted) {
        setState(() {
          _horaires = HorairesCabinet.fromMap(
            data is Map ? Map<String, dynamic>.from(data) : null,
          );
          _chargement = false;
        });
      }
    } catch (_) {
      // Des horaires illisibles ne doivent pas empêcher de prendre un
      // rendez-vous : on retombe sur les valeurs par défaut.
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _decalerJour(int jours) {
    setState(() => _jour = _jour.add(Duration(days: jours)));
  }

  Future<void> _choisirDate() async {
    final choix = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (choix != null) {
      setState(() => _jour = DateTime(choix.year, choix.month, choix.day));
    }
  }

  /// Prochain jour ouvré, pour ne pas laisser l'assistant tâtonner.
  DateTime? get _prochainJourOuvert {
    for (var i = 1; i <= 14; i++) {
      final j = _jour.add(Duration(days: i));
      if (_horaires.estOuvertLe(j)) return j;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duree = _duree ?? _horaires.duree;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir un créneau'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: scheme.outline),
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _Entete(
                  patient: widget.patient,
                  medecin: widget.doctorName.isEmpty
                      ? widget.doctorId
                      : widget.doctorName,
                  jour: _jour,
                  duree: duree,
                  dureeCabinet: _horaires.duree,
                  onJourPrecedent: () => _decalerJour(-1),
                  onJourSuivant: () => _decalerJour(1),
                  onChoisirDate: _choisirDate,
                  onDuree: (d) => setState(() => _duree = d),
                ),
                Expanded(child: _grille(duree)),
              ],
            ),
    );
  }

  Widget _grille(int duree) {
    if (!_horaires.estOuvertLe(_jour)) {
      final suivant = _prochainJourOuvert;
      return _Vide(
        titre: 'Le cabinet est fermé ce jour-là',
        detail: suivant == null
            ? null
            : 'Prochain jour ouvert : ${fmt.date(suivant)}',
        action: suivant == null
            ? null
            : FluentButton(
                label: 'Aller au ${fmt.date(suivant)}',
                icon: Icons.arrow_forward,
                onPressed: () => setState(() => _jour = suivant),
              ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RendezVousRepository().journee(
        parentUid: widget.parentUid,
        profileId: widget.doctorId,
        jour: _jour,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _Vide(
            titre: 'Impossible de lire l\'agenda',
            detail: 'Sans l\'agenda, on ne peut pas garantir qu\'un créneau '
                'est libre.',
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final occupations = snap.data!
            .map(
              (d) => Occupation.fromRendezVous(
                (d['id'] ?? '').toString(),
                d,
                dureeParDefaut: _horaires.duree,
              ),
            )
            .whereType<Occupation>()
            .toList();

        final creneaux = _horaires.creneauxDuJour(_jour, dureeCreneau: duree);
        final maintenant = DateTime.now();

        final libres = creneaux
            .where(
              (c) =>
                  etatDe(
                    c,
                    occupations,
                    maintenant: maintenant,
                    ignorer: widget.ignorerRdvId,
                  ) ==
                  EtatCreneau.libre,
            )
            .length;

        if (creneaux.isEmpty) {
          return const _Vide(
            titre: 'Aucun créneau ce jour-là',
            detail: 'La durée choisie ne rentre pas dans les horaires du '
                'cabinet.',
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text(
                    libres == 0
                        ? 'Journée complète'
                        : '$libres créneau${libres > 1 ? 'x' : ''} libre'
                              '${libres > 1 ? 's' : ''} sur ${creneaux.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  const _Legende(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in creneaux)
                      _Creneau(
                        creneau: c,
                        etat: etatDe(
                          c,
                          occupations,
                          maintenant: maintenant,
                          ignorer: widget.ignorerRdvId,
                        ),
                        conflit: conflitPour(
                          c,
                          occupations,
                          ignorer: widget.ignorerRdvId,
                        ),
                        onChoisi: () => Navigator.pop(context, c),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Entete extends StatelessWidget {
  final String patient;
  final String medecin;
  final DateTime jour;
  final int duree;
  final int dureeCabinet;
  final VoidCallback onJourPrecedent;
  final VoidCallback onJourSuivant;
  final VoidCallback onChoisirDate;
  final ValueChanged<int> onDuree;

  const _Entete({
    required this.patient,
    required this.medecin,
    required this.jour,
    required this.duree,
    required this.dureeCabinet,
    required this.onJourPrecedent,
    required this.onJourSuivant,
    required this.onChoisirDate,
    required this.onDuree,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Les durées proposées encadrent celle du cabinet : la plupart des
    // rendez-vous la prennent, quelques-uns demandent le double.
    final durees = {dureeCabinet, dureeCabinet * 2, dureeCabinet * 3}.toList()
      ..sort();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoGrid(
            minColumnWidth: 160,
            items: [
              InfoPair(label: 'Patient', value: patient, emphasis: true),
              InfoPair(
                label: 'Médecin',
                value: medecin,
                icon: Icons.medical_services_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: 'Jour précédent',
                icon: const Icon(Icons.chevron_left),
                onPressed: onJourPrecedent,
              ),
              Expanded(
                child: InkWell(
                  onTap: onChoisirDate,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Text(
                        fmt.capitalize(fmt.relativeDay(jour)),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Jour suivant',
                icon: const Icon(Icons.chevron_right),
                onPressed: onJourSuivant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Durée',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(width: 12),
              for (final d in durees) ...[
                ChoiceChip(
                  label: Text('$d min'),
                  selected: duree == d,
                  onSelected: (_) => onDuree(d),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Creneau extends StatelessWidget {
  final Creneau creneau;
  final EtatCreneau etat;
  final Occupation? conflit;
  final VoidCallback onChoisi;

  const _Creneau({
    required this.creneau,
    required this.etat,
    required this.conflit,
    required this.onChoisi,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final libre = etat == EtatCreneau.libre;

    final couleur = switch (etat) {
      EtatCreneau.libre => scheme.primary,
      EtatCreneau.occupe => scheme.error,
      EtatCreneau.passe => scheme.onSurface.withValues(alpha: 0.3),
      EtatCreneau.ferme => scheme.onSurface.withValues(alpha: 0.3),
    };

    final contenu = Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: libre
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.08),
                scheme.surface,
              )
            : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(
          color: libre
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outline.withValues(alpha: 0.7),
          width: libre ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            creneau.libelle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: couleur,
              decoration: etat == EtatCreneau.passe
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            switch (etat) {
              // Nommer qui occupe le créneau évite l'aller-retour vers la
              // liste des rendez-vous pour comprendre pourquoi c'est rouge.
              EtatCreneau.occupe => conflit?.patient ?? 'Occupé',
              EtatCreneau.passe => 'Passé',
              EtatCreneau.ferme => 'Fermé',
              EtatCreneau.libre => 'Libre',
            },
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: libre ? FontWeight.w600 : FontWeight.w500,
              color: etat == EtatCreneau.occupe
                  ? scheme.error
                  : scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );

    if (!libre) {
      return Tooltip(
        message: etat == EtatCreneau.occupe
            ? '${conflit?.patient} · ${conflit?.etape.libelle}'
            : 'Indisponible',
        child: Opacity(opacity: 0.75, child: contenu),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onChoisi, child: contenu),
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget point(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );

    return Wrap(
      children: [
        point(scheme.primary, 'Libre'),
        point(scheme.error, 'Occupé'),
        point(scheme.onSurface.withValues(alpha: 0.3), 'Passé'),
      ],
    );
  }
}

class _Vide extends StatelessWidget {
  final String titre;
  final String? detail;
  final Widget? action;

  const _Vide({required this.titre, this.detail, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: FluentCard(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 36,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

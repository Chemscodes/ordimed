import 'package:flutter/material.dart';
import '../core/coerce.dart';
import '../core/parcours.dart';
import '../services/api_service.dart';
import '../ui/info_display.dart';
import 'patient_status_indicator.dart';

/// Actions disponibles sur une ligne de [SalleAttenteBoard].
///
/// Chaque callback est optionnel : seul un callback non nul fait apparaitre
/// son bouton. Le widget ne connait aucune regle de role — c'est
/// l'appelant (medecin, assistant, medecin principal) qui decide de ce
/// qu'il fournit, a partir de methodes qui existaient deja dans son propre
/// dashboard.
class SalleAttenteRowActions {
  /// Ligne "en salle d'attente" -> passer en consultation.
  final Future<void> Function(BuildContext context, Map<String, dynamic> entry)?
  onConsulter;

  /// Ligne "en consultation" -> reprendre l'ecran de consultation guidee.
  final Future<void> Function(BuildContext context, Map<String, dynamic> entry)?
  onReprendre;

  /// Ligne "en consultation" -> cloturer directement (sans consultation guidee).
  final Future<void> Function(BuildContext context, Map<String, dynamic> entry)?
  onTerminer;

  /// Enregistrer un versement (geste d'accueil), disponible sur les deux
  /// premieres sections.
  final Future<void> Function(BuildContext context, Map<String, dynamic> entry)?
  onVersement;

  /// Toujours disponible : ouvrir le dossier du patient.
  final void Function(BuildContext context, Map<String, dynamic> entry)
  onOuvrirDossier;

  const SalleAttenteRowActions({
    this.onConsulter,
    this.onReprendre,
    this.onTerminer,
    this.onVersement,
    required this.onOuvrirDossier,
  });
}

/// Salle d'attente du jour, partagee par les 3 tableaux de bord (medecin,
/// assistant, medecin principal).
///
/// Avant ce widget, chaque dashboard reconstruisait sa propre liste avec un
/// regroupement `status`/`closedAt` fait a la main, des couleurs de ligne
/// differentes, et un libelle de bouton different pour le meme geste —
/// « Consulter » cote medecin, « En consultation » cote assistant, rien du
/// tout cote principal. Le regroupement s'appuie desormais sur
/// [EtapeParcours.fromWaiting] (deja le vocabulaire canonique du parcours
/// de visite) et les libelles de bouton viennent de
/// [EtapeParcours.verbeVers] au lieu d'etre recopies a la main.
class SalleAttenteBoard extends StatefulWidget {
  final String profileId;
  final SalleAttenteRowActions actions;

  /// Actions additionnelles dans l'en-tete, a cote de « Voir tout ».
  ///
  /// Sert par exemple au bouton « Reinitialiser journee » de l'assistant,
  /// qui a besoin des listes du jour deja groupees pour savoir s'il y a
  /// quelque chose a cloturer.
  final List<Widget> Function(
    BuildContext context,
    List<Map<String, dynamic>> waiting,
    List<Map<String, dynamic>> inConsultation,
  )?
  headerActionsBuilder;

  const SalleAttenteBoard({
    super.key,
    required this.profileId,
    required this.actions,
    this.headerActionsBuilder,
  });

  @override
  State<SalleAttenteBoard> createState() => _SalleAttenteBoardState();
}

class _SalleAttenteBoardState extends State<SalleAttenteBoard> {
  static const int _pageSize = 120;
  static const int _lookbackDays = 7;
  int _limit = _pageSize;
  bool _showAll = false;

  /// Lignes dont une action est en cours : desactive leurs boutons le temps
  /// de l'appel reseau au lieu de laisser un double-clic partir deux fois.
  final Set<String> _pendingIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final recentCutoff = startOfDay.subtract(
      const Duration(days: _lookbackDays),
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ApiService.instance.salleAttenteFlux(profileId: widget.profileId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erreur de chargement de la salle d\'attente'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Le filtrage par date se fait ici : une contrainte serveur sur
        // `createdAt` exclurait les entrees qui n'ont pas ce champ.
        final docs = _showAll
            ? snapshot.data!
            : snapshot.data!.where((e) {
                final c = asDateOrNull(e['createdAt']);
                return c == null || !c.isBefore(recentCutoff);
              }).toList();

        final waiting = <Map<String, dynamic>>[];
        final inConsultation = <Map<String, dynamic>>[];
        final historyToday = <Map<String, dynamic>>[];

        for (final entry in docs) {
          final etape = EtapeParcours.fromWaiting(entry);
          if (etape.estClose) {
            final closed = asDateOrNull(entry['closedAt']);
            // Sans date de cloture, on prefere montrer l'entree plutot que
            // la faire disparaitre silencieusement.
            final estAujourdhui =
                closed == null ||
                (closed.isAfter(
                      startOfDay.subtract(const Duration(milliseconds: 1)),
                    ) &&
                    closed.isBefore(endOfDay));
            if (estAujourdhui) historyToday.add(entry);
            continue;
          }
          if (etape == EtapeParcours.enCours) {
            inConsultation.add(entry);
          } else {
            waiting.add(entry);
          }
        }

        if (waiting.isEmpty && inConsultation.isEmpty && historyToday.isEmpty) {
          return const Center(child: Text('Aucun patient pour aujourd\'hui'));
        }

        final canLoadMore = docs.length >= _limit;
        final headerActions =
            widget.headerActionsBuilder?.call(context, waiting, inConsultation) ??
            const <Widget>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'En consultation : ${inConsultation.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Salle d\'attente : ${waiting.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _showAll = !_showAll;
                      _limit = _pageSize;
                    }),
                    child: Text(_showAll ? 'Voir recents' : 'Voir tout'),
                  ),
                  ...headerActions,
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  SectionHeader(
                    titre: EtapeParcours.enCours.libelle,
                    compteur: inConsultation.length,
                    icone: EtapeParcours.enCours.icone,
                  ),
                  if (inConsultation.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('Aucun patient en consultation'),
                    )
                  else
                    ...inConsultation.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: _buildRow(context, entry, EtapeParcours.enCours),
                      ),
                    ),
                  SectionHeader(
                    titre: EtapeParcours.arrive.libelle,
                    compteur: waiting.length,
                    icone: EtapeParcours.arrive.icone,
                  ),
                  if (waiting.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('Aucun patient en attente'),
                    )
                  else
                    ...waiting.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: _buildRow(context, entry, EtapeParcours.arrive),
                      ),
                    ),
                  const Divider(),
                  SectionHeader(
                    titre: 'Historique du jour',
                    compteur: historyToday.length,
                    icone: Icons.history,
                  ),
                  if (historyToday.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('Aucun historique'),
                    )
                  else
                    ...historyToday.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: _buildHistoryRow(context, entry),
                      ),
                    ),
                  if (canLoadMore)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _limit += _pageSize),
                          child: const Text('Charger plus'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    Map<String, dynamic> entry,
    EtapeParcours etape,
  ) {
    final id = (entry['id'] ?? '').toString();
    final nom = (entry['patientNom'] ?? 'Patient').toString();
    final prenom = (entry['patientPrenom'] ?? '').toString();
    final doctor = (entry['doctorName'] ?? entry['doctorId'] ?? '').toString();
    final assistant = (entry['assistantName'] ?? entry['assistantId'] ?? '')
        .toString();
    final seancesTotal = asIntOrNull(entry['nombreSeances']);
    final seancesDone = asIntOrNull(entry['seancesEffectuees']);
    final estEnCours = etape == EtapeParcours.enCours;
    final horodatage = estEnCours
        ? asDateOrNull(entry['inConsultationAt'])
        : asDateOrNull(entry['createdAt']);
    final pending = _pendingIds.contains(id);
    final actions = widget.actions;

    return PersonRow(
      nom: nom,
      prenom: prenom,
      etape: etape,
      meta: [
        if (doctor.isNotEmpty) 'Dr $doctor',
        if (assistant.isNotEmpty) assistant,
        if (seancesDone != null || seancesTotal != null)
          'Séance ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
      ],
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SinceBadge(
            label: estEnCours ? 'Depuis' : 'Arrivée',
            value: _heure(horodatage),
          ),
          const SizedBox(height: 6),
          _ResteAPayerLive(patientId: (entry['patientId'] ?? '').toString()),
        ],
      ),
      onTap: () => actions.onOuvrirDossier(context, entry),
      actions: [
        IconButton(
          tooltip: 'Ouvrir le dossier',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: pending ? null : () => actions.onOuvrirDossier(context, entry),
        ),
        if (!estEnCours && actions.onVersement != null)
          _actionButton(
            label: 'Versement',
            outlined: true,
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onVersement!(context, entry)),
          ),
        if (!estEnCours && actions.onConsulter != null)
          _actionButton(
            label: EtapeParcours.arrive.verbeVers(EtapeParcours.enCours),
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onConsulter!(context, entry)),
          ),
        if (estEnCours && actions.onReprendre != null)
          _actionButton(
            label: 'Reprendre',
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onReprendre!(context, entry)),
          ),
        if (estEnCours && actions.onVersement != null)
          _actionButton(
            label: 'Versement',
            outlined: true,
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onVersement!(context, entry)),
          ),
        if (estEnCours && actions.onTerminer != null)
          _actionButton(
            label: EtapeParcours.enCours.verbeVers(EtapeParcours.honore),
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onTerminer!(context, entry)),
          ),
      ],
    );
  }

  Widget _buildHistoryRow(BuildContext context, Map<String, dynamic> entry) {
    final id = (entry['id'] ?? '').toString();
    final nom = (entry['patientNom'] ?? 'Patient').toString();
    final prenom = (entry['patientPrenom'] ?? '').toString();
    final doctor = (entry['doctorName'] ?? entry['doctorId'] ?? '').toString();
    final assistant = (entry['assistantName'] ?? entry['assistantId'] ?? '')
        .toString();
    final closed = asDateOrNull(entry['closedAt']);
    final pending = _pendingIds.contains(id);
    final actions = widget.actions;

    return PersonRow(
      nom: nom,
      prenom: prenom,
      etape: EtapeParcours.fromWaiting(entry),
      meta: [
        if (doctor.isNotEmpty) 'Dr $doctor',
        if (assistant.isNotEmpty) assistant,
      ],
      // Le medecin vient de cloturer (prix inclus) : c'est exactement le
      // moment ou l'assistant encaisse. Sans ce bouton, il fallait rouvrir
      // le dossier a la main pour trouver ou payer.
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SinceBadge(label: 'Reçu', value: _heure(closed)),
          const SizedBox(height: 6),
          _ResteAPayerLive(patientId: (entry['patientId'] ?? '').toString()),
        ],
      ),
      onTap: () => actions.onOuvrirDossier(context, entry),
      actions: [
        if (actions.onVersement != null)
          _actionButton(
            label: 'Versement',
            outlined: true,
            pending: pending,
            onPressed: () =>
                _run(id, () => actions.onVersement!(context, entry)),
          ),
      ],
    );
  }

  String? _heure(DateTime? d) {
    if (d == null) return null;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    bool pending = false,
    bool outlined = false,
  }) {
    final child = pending
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    if (outlined) {
      return OutlinedButton(onPressed: pending ? null : onPressed, child: child);
    }
    return ElevatedButton(onPressed: pending ? null : onPressed, child: child);
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_pendingIds.contains(id)) return;
    setState(() => _pendingIds.add(id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _pendingIds.remove(id));
    }
  }
}

/// Rend visible en salle d'attente ce qu'un patient doit encore — avant,
/// il fallait ouvrir le dossier pour le savoir. Lit le seul document patient
/// en direct (`patientDocFlux`) : si un versement est encaisse pendant que
/// la ligne est affichee, le badge se met a jour tout seul.
///
/// Pas `dossierFlux` : le calcul (`ResteAPayerBadge`) ne lit que `prix` et
/// `versements`/`totalVersements`, des champs du patient — ouvrir en plus
/// les formulaires et versements comme le fait `dossierFlux` ferait trois
/// listeners Firestore par ligne de salle d'attente pour deux qui ne
/// serviraient jamais ici.
class _ResteAPayerLive extends StatelessWidget {
  final String patientId;

  const _ResteAPayerLive({required this.patientId});

  @override
  Widget build(BuildContext context) {
    if (patientId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<Map<String, dynamic>>(
      stream: ApiService.instance.patientDocFlux(patientId),
      builder: (context, snapshot) {
        final patientData = snapshot.data;
        if (patientData == null) return const SizedBox.shrink();
        return ResteAPayerBadge(patientData: patientData);
      },
    );
  }
}

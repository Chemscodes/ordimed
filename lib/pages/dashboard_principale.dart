import '../ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_profile_page.dart';
import 'patientspage.dart';
import 'profile_selector_page.dart';
import 'patient_details_page.dart';
import 'stats_page.dart';
import '../ui/app_shell.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_button.dart';
import '../services/firestore_service.dart';
import '../services/stats_service.dart';
import '../widgets/daily_versements_card.dart';
import '../core/coerce.dart';
import '../core/parcours.dart';
import 'sauvegarde_page.dart';
import '../ui/info_display.dart';

int? _toInt(dynamic v) => asIntOrNull(v);

class DashboardPrincipal extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final Map<String, dynamic> profileData;

  const DashboardPrincipal({
    super.key,
    required this.parentUid,
    required this.profileId,
    required this.profileData,
  });

  @override
  State<DashboardPrincipal> createState() => _DashboardPrincipalState();
}

class _DashboardPrincipalState extends State<DashboardPrincipal> {
  int navIndex = 0; // 0 tableau, 1 patients (sidebar)
  final FirestoreService service = FirestoreService();
  String? _principalName;

  @override
  void initState() {
    super.initState();
    _principalName = (widget.profileData['name'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);

    return AppShell(
      title: _principalName == null || _principalName!.isEmpty
          ? 'Tableau directeur'
          : 'Dr $_principalName',
      currentIndex: navIndex,
      onNav: (i) => setState(() => navIndex = i),
      navItems: const ['Tableau', 'Patients', 'Salle d\'attente'],
      topActions: [
        FluentButton(
          label: 'Retour accueil',
          icon: Icons.home_outlined,
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileSelectorPage(uid: widget.parentUid),
              ),
              (route) => false,
            );
          },
        ),
        const SizedBox(width: 8),
        FluentButton(
          label: 'Ajouter un profil',
          icon: Icons.person_add_alt_1,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddProfilePage(uid: widget.parentUid),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FluentButton(
          label: 'Stats',
          icon: Icons.insights_outlined,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StatsPage(parentUid: widget.parentUid, title: 'Stats du cabinet'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Firestore n'a pas de corbeille : c'etait le seul degat que l'app
        // pouvait causer sans retour possible.
        FluentButton(
          label: 'Sauvegardes',
          icon: Icons.shield_outlined,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SauvegardePage(parentUid: widget.parentUid),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FluentButton(
          label: 'Modifier mon profil',
          icon: Icons.edit,
          onPressed: () => _editPrincipalProfile(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (navIndex == 0) ...[
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 780;
                      final cards = [
                        Expanded(
                          child: FluentCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: const [
                                CircleAvatar(
                                  backgroundColor: Color(0x1F2563EB),
                                  child: Icon(Icons.person_add_alt_1, color: primary),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Profils',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FluentCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: const [
                                CircleAvatar(
                                  backgroundColor: Color(0x1F2563EB),
                                  child: Icon(Icons.analytics_outlined, color: primary),
                                ),
                                SizedBox(width: 12),
                                Text('Reporting'),
                              ],
                            ),
                          ),
                        ),
                      ];
                      if (isNarrow) {
                        return Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 12),
                            cards[2],
                          ],
                        );
                      }
                      return Row(children: cards);
                    },
                  ),
                  const SizedBox(height: 12),
                  DailyVersementsCard(
                    parentUid: widget.parentUid,
                    profileId: widget.profileId,
                  ),
                  const SizedBox(height: 12),
                  _VersementCardsForDay(
                    parentUid: widget.parentUid,
                    principalId: widget.profileId,
                  ),
                  const SizedBox(height: 16),
                  _NetDailyCardPrincipal(parentUid: widget.parentUid),
                  const SizedBox(height: 16),
                  _PurchasesCardPrincipal(parentUid: widget.parentUid),
                  const SizedBox(height: 16),
                  _WeeklyFinanceChartPrincipal(parentUid: widget.parentUid),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ] else if (navIndex == 1) ...[
            const SizedBox(height: 8),
            Expanded(
              child: PatientsPage(
                parentUid: widget.parentUid,
                profileId: widget.profileId,
                canAddDoctorForm: true,
              ),
            ),
          ] else if (navIndex == 2) ...[
            const SizedBox(height: 8),
            Expanded(
              child: _RendezVousTab(
                parentUid: widget.parentUid,
                profileId: widget.profileId,
                principalName: _principalName ?? (widget.profileData['name'] ?? ''),
              ),
            ),
          ] else ...[
            const Expanded(
              child: Center(
                child:
                    Text('Choisis un onglet Patients ou Rendez-vous au-dessus', textAlign: TextAlign.center),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editPrincipalProfile(BuildContext context) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId);

    final snap = await docRef.get();
    final currentName = (snap.data()?['name'] ?? _principalName ?? '').toString();
    final nameCtrl = TextEditingController(text: currentName);

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le profil'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom du medecin principal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (res != true) return;

    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le nom ne peut pas être vide')),
        );
      }
      return;
    }

    await docRef.set({'name': newName}, SetOptions(merge: true));
    if (mounted) {
      setState(() => _principalName = newName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour')),
      );
    }
  }
}


class _RendezVousTab extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final String principalName;

  _RendezVousTab({
    required this.parentUid,
    required this.profileId,
    required this.principalName,
  });

  @override
  State<_RendezVousTab> createState() => _RendezVousTabState();
}

class _RendezVousTabState extends State<_RendezVousTab> {
  static const int _pageSize = 120;
  static const int _lookbackDays = 7;
  int _limit = _pageSize;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedIcon = scheme.onSurface.withOpacity(0.65);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final recentCutoff = startOfDay.subtract(const Duration(days: _lookbackDays));
    Query<Map<String, dynamic>> ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId)
        .collection('salle_attente')
        .orderBy('createdAt', descending: true);
    if (!_showAll) {
      ref = ref.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(recentCutoff));
    }
    ref = ref.limit(_limit);
    final stream = ref.snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erreur de chargement de la salle d\'attente'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final waiting = <QueryDocumentSnapshot>[];
        final inConsultation = <QueryDocumentSnapshot>[];
        final historyToday = <QueryDocumentSnapshot>[];

        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString();
          final closed = data['closedAt'];
          final closedTs = closed is Timestamp ? closed.toDate() : null;
          final isDone = status == 'done' || closedTs != null;
          if (isDone) {
            if (closedTs != null &&
                closedTs.isAfter(startOfDay.subtract(const Duration(milliseconds: 1))) &&
                closedTs.isBefore(endOfDay)) {
              historyToday.add(d);
            }
            continue;
          }
          if (status == 'in_consultation') {
            inConsultation.add(d);
            continue;
          }
          waiting.add(d);
        }

        if (waiting.isEmpty && inConsultation.isEmpty && historyToday.isEmpty) {
          return const Center(child: Text('Aucun patient pour aujourd\'hui'));
        }

        final canLoadMore = docs.length >= _limit;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Les compteurs etaient en texte sombre sur le fond sombre de
            // l'AppShell : quasi illisibles. Ils passent en pastilles.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  _Compteur(
                    label: 'En consultation',
                    valeur: inConsultation.length,
                    etape: EtapeParcours.enCours,
                  ),
                  const SizedBox(width: 10),
                  _Compteur(
                    label: "Salle d'attente",
                    valeur: waiting.length,
                    etape: EtapeParcours.arrive,
                  ),
                  const Spacer(),
                  FluentButton(
                    label: _showAll ? 'Recents' : 'Voir tout',
                    icon: _showAll
                        ? Icons.filter_alt_off_outlined
                        : Icons.filter_alt_outlined,
                    type: FluentButtonType.ghost,
                    compact: true,
                    onPressed: () => setState(() {
                      _showAll = !_showAll;
                      _limit = _pageSize;
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SectionHeader(
                      titre: 'En consultation',
                      compteur: inConsultation.length,
                      icone: Icons.medical_services_outlined,
                    ),
                  ),
                  if (inConsultation.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('Aucun patient en consultation'),
                    )
                  else
                    ...List.generate(inConsultation.length, (index) {
                      final data = inConsultation[index].data() as Map<String, dynamic>;
                      final patient = data['patientNom'] ?? 'Patient';
                      final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                      final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                      final seancesTotal = _toInt(data['nombreSeances']);
                      final seancesDone = _toInt(data['seancesEffectuees']);
                      final started = data['inConsultationAt'] is Timestamp
                          ? (data['inConsultationAt'] as Timestamp).toDate()
                          : null;
                      final startStr = started != null
                          ? '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: 10,
                          left: 12,
                          right: 12,
                        ),
                        child: PersonRow(
                          nom: patient.toString(),
                          prenom: (data['patientPrenom'] ?? '').toString(),
                          etape: EtapeParcours.enCours,
                          meta: [
                            if (doctor.isNotEmpty) 'Dr $doctor',
                            if (assistant.isNotEmpty) assistant,
                            if (seancesDone != null || seancesTotal != null)
                              'Séance ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                          ],
                          trailing: SinceBadge(label: 'Depuis', value: startStr),
                          actions: [
                            IconButton(
                              tooltip: 'Ouvrir le dossier',
                              icon: const Icon(Icons.folder_open_outlined),
                              onPressed: () => _openPatient(context, data),
                            ),
                          ],
                          onTap: () => _openPatient(context, data),
                        ),
                      );
                    }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SectionHeader(
                      titre: "Salle d'attente",
                      compteur: waiting.length,
                      icone: Icons.hourglass_empty,
                    ),
                  ),
                  if (waiting.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('Aucun patient en attente'),
                    )
                  else
                    ListView.builder(
                      itemCount: waiting.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final data = waiting[index].data() as Map<String, dynamic>;
                        final patient = data['patientNom'] ?? 'Patient';
                        final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                        final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                        final seancesTotal = _toInt(data['nombreSeances']);
                        final seancesDone = _toInt(data['seancesEffectuees']);
                        final created = data['createdAt'] is Timestamp
                            ? (data['createdAt'] as Timestamp).toDate()
                            : null;
                        final createdStr = created != null
                            ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: 10,
                            left: 12,
                            right: 12,
                          ),
                          child: PersonRow(
                            nom: patient.toString(),
                            prenom: (data['patientPrenom'] ?? '').toString(),
                            etape: EtapeParcours.arrive,
                            meta: [
                              if (doctor.isNotEmpty) 'Dr $doctor',
                              if (assistant.isNotEmpty) assistant,
                              if (seancesDone != null || seancesTotal != null)
                                'Séance ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                            ],
                            trailing: SinceBadge(
                              label: 'Arrivée',
                              value: createdStr,
                            ),
                            actions: [
                              IconButton(
                                tooltip: 'Ouvrir le dossier',
                                icon: const Icon(Icons.folder_open_outlined),
                                onPressed: () => _openPatient(context, data),
                              ),
                            ],
                            onTap: () => _openPatient(context, data),
                          ),
                        );
                      },
                    ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Historique du jour',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    height: 160,
                    child: historyToday.isEmpty
                        ? const Center(child: Text('Aucun historique'))
                        : ListView.builder(
                            itemCount: historyToday.length,
                            itemBuilder: (context, index) {
                              final data = historyToday[index].data() as Map<String, dynamic>;
                              final patient = data['patientNom'] ?? 'Patient';
                              final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                              final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                              final closed = data['closedAt'] is Timestamp
                                  ? (data['closedAt'] as Timestamp).toDate()
                                  : null;
                              final closedStr = closed != null
                                  ? '${closed.hour.toString().padLeft(2, '0')}:${closed.minute.toString().padLeft(2, '0')}'
                                  : '';
                              return ListTile(
                                leading: Icon(Icons.history, color: mutedIcon),
                                title: Text(patient),
                                subtitle: Text(
                                  [
                                    if (doctor.isNotEmpty) 'Medecin: $doctor',
                                    if (assistant.isNotEmpty) 'Assistant: $assistant',
                                    'Recu: $closedStr',
                                  ].join('\n'),
                                ),
                              );
                            },
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

  void _openPatient(BuildContext context, Map<String, dynamic> data) {
    final patientId = (data['patientId'] ?? '').toString();
    final patientName = (data['patientNom'] ?? '').toString();
    if (patientId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDetailsPage(
          patientId: patientId,
          patientName: patientName.isEmpty ? 'Patient' : patientName,
          parentUid: widget.parentUid,
          ownerProfileId: widget.profileId,
          canAddForm: true,
          canAddDoctorForm: true,
        ),
      ),
    );
  }
}


class _VersementCardsForDay extends StatefulWidget {
  final String parentUid;
  final String principalId;

  const _VersementCardsForDay({
    required this.parentUid,
    required this.principalId,
  });

  @override
  State<_VersementCardsForDay> createState() => _VersementCardsForDayState();
}

class _VersementCardsForDayState extends State<_VersementCardsForDay> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _profilesFuture,
      builder: (context, profilesSnap) {
        final profileNames = <String, String>{};
        if (profilesSnap.hasData) {
          for (final d in profilesSnap.data!.docs) {
            profileNames[d.id] = (d.data()['name'] ?? '').toString();
          }
        }

        // Lecture directe de l'agregat du jour (1 document) au lieu de
        // scanner toute la base de patients du cabinet.
        return StreamBuilder<Map<String, dynamic>?>(
          stream: StatsService().dailyStatsDoc(
            parentUid: widget.parentUid,
            dayKey: _todayKey(),
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const SizedBox(
                height: 72,
                child: Center(child: Text('Erreur chargement versements')),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 72,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final cabinetTotal = _asDouble(data['versementsTotal']);
            final cabinetCount = (data['versementsCount'] as num?)?.toInt() ?? 0;

            final doctors = <String, _DoctorAgg>{};
            final rawByDoctor = data['doctorVersements'];
            if (rawByDoctor is Map) {
              rawByDoctor.forEach((rawKey, value) {
                if (value is! Map) return;
                final key = rawKey.toString();
                final storedName = (value['name'] ?? '').toString().trim();
                final displayName = storedName.isNotEmpty
                    ? storedName
                    : (profileNames[key] ??
                        (key == '_none' ? 'Sans medecin' : key));
                doctors[key] = _DoctorAgg(
                  name: displayName,
                  total: _asDouble(value['total']),
                  count: (value['count'] as num?)?.toInt() ?? 0,
                );
              });
            }

            final principalTotal = doctors[widget.principalId]?.total ?? 0;
            final principalCount = doctors[widget.principalId]?.count ?? 0;
            final others = doctors.entries
                .where((e) => e.key != widget.principalId)
                .toList()
              ..sort((a, b) => b.value.total.compareTo(a.value.total));

            final cards = <Widget>[
              _statCard(
                context: context,
                icon: Icons.apartment,
                label: 'Cabinet (jour)',
                versements: cabinetTotal,
                subtitle: cabinetCount == 1
                    ? '1 versement aujourd\'hui'
                    : '$cabinetCount versements aujourd\'hui',
              ),
              _statCard(
                context: context,
                icon: Icons.person_outline,
                label: 'Moi (jour)',
                versements: principalTotal,
                subtitle: principalCount == 1
                    ? '1 versement aujourd\'hui'
                    : '$principalCount versements aujourd\'hui',
              ),
            ];

            cards.addAll(
              others.map(
                (e) => _statCard(
                  context: context,
                  icon: Icons.medical_services_outlined,
                  label: e.value.name,
                  versements: e.value.total,
                  subtitle: e.value.count == 1
                      ? '1 versement aujourd\'hui'
                      : '${e.value.count} versements aujourd\'hui',
                ),
              ),
            );

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map(
                    (card) => SizedBox(
                      width: 320,
                      child: card,
                    ),
                  )
                  .toList(),
            );
          },
        );
      },
    );
  }

  Widget _statCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required double versements,
    required String subtitle,
  }) {
    final textMuted = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    return FluentCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0x1F2563EB),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: textMuted)),
              ],
            ),
          ),
          Text(
            'DA ${_formatMoney(versements)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  double _asDouble(dynamic value) => asDouble(value);

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatMoney(double value) {
    final isInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(isInt ? 0 : 2);
  }
}

/// Compteur d'etat en pastille, pour l'en-tete de la salle d'attente.
///
/// Les anciens compteurs etaient du texte sombre pose sur le fond sombre de
/// l'AppShell : le contraste etait insuffisant pour les lire.
class _Compteur extends StatelessWidget {
  final String label;
  final int valeur;
  final EtapeParcours etape;

  const _Compteur({
    required this.label,
    required this.valeur,
    required this.etape,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = etape == EtapeParcours.enCours
        ? scheme.secondary
        : scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: couleur.withValues(alpha: 0.45)),
        boxShadow: AppTheme.shadow(context, strength: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(etape.icone, size: 15, color: couleur),
          const SizedBox(width: 8),
          Text(
            '$valeur',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: couleur,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorAgg {
  String name;
  double total;
  int count;
  _DoctorAgg({required this.name, this.total = 0, this.count = 0});
}

class _PurchasesHistoryPrincipal extends StatefulWidget {
  final String parentUid;
  final String dayKey;

  const _PurchasesHistoryPrincipal({
    required this.parentUid,
    required this.dayKey,
  });

  @override
  State<_PurchasesHistoryPrincipal> createState() => _PurchasesHistoryPrincipalState();
}

class _PurchasesHistoryPrincipalState extends State<_PurchasesHistoryPrincipal> {
  static const int _pageSize = 100;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final stream = FirebaseFirestore.instance
        .collectionGroup('purchases')
        .where('parentUid', isEqualTo: widget.parentUid)
        .where('dayKey', isEqualTo: widget.dayKey)
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Erreur de chargement'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun achat aujourd\'hui'));
        }
        return ListView.builder(
          itemCount: docs.length + (docs.length >= _limit ? 1 : 0),
          itemBuilder: (context, i) {
            if (docs.length >= _limit && i >= docs.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _limit += _pageSize),
                    child: const Text('Charger plus'),
                  ),
                ),
              );
            }
            final data = docs[i].data() as Map<String, dynamic>;
            final produit = (data['produit'] ?? 'Produit').toString();
            final fournisseur = (data['fournisseur'] ?? '').toString();
            final montant = (data['montant'] as num?)?.toDouble() ?? 0;
            final created = data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : null;
            final profileId = (data['profileId'] ?? '').toString();
            final dateStr = created != null
                ? '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                : '';
            return FluentCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.green.withOpacity(0.12),
                    child: const Icon(Icons.receipt_long, color: Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(produit,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: textPrimary)),
                        if (fournisseur.isNotEmpty)
                          Text('Fournisseur: $fournisseur',
                              style: TextStyle(color: textMuted, fontSize: 12)),
                        if (profileId.isNotEmpty)
                          Text('Compte: $profileId',
                              style: TextStyle(color: textFaint, fontSize: 12)),
                        if (dateStr.isNotEmpty)
                          Text(dateStr,
                              style: TextStyle(color: textFaint, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('DA ${montant.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _WeeklyFinanceChartPrincipal extends StatelessWidget {
  final String parentUid;

  const _WeeklyFinanceChartPrincipal({required this.parentUid});

  String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    return FutureBuilder<_WeeklyFinanceData>(
      future: _loadData(),
      builder: (context, snap) {
        if (snap.hasError) {
          return FluentCard(
            padding: const EdgeInsets.all(14),
            child: Text('Erreur chargement finances : ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const FluentCard(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data!;
        final safeMax = data.maxValue <= 0 ? 1 : data.maxValue;

        Widget bar(double value, Color color) {
          final h = (value.abs() / safeMax) * 90.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: h.clamp(4, 90),
            width: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          );
        }

        return FluentCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Finances - 7 derniers jours',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Versements: ${data.totalVersements.toStringAsFixed(0)} | Achats: ${data.totalAchats.toStringAsFixed(0)} | Net: ${data.totalNet.toStringAsFixed(0)}',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: data.days.map((d) {
                    final key = _dayKey(d);
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              bar(data.versements[key] ?? 0, const Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              bar(data.achats[key] ?? 0, const Color(0xFFF97316)),
                              const SizedBox(width: 4),
                              bar(data.net[key] ?? 0, const Color(0xFF16A34A)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: const [
                  _LegendDot(color: Color(0xFF2563EB), label: 'Versements'),
                  SizedBox(width: 10),
                  _LegendDot(color: Color(0xFFF97316), label: 'Achats'),
                  SizedBox(width: 10),
                  _LegendDot(color: Color(0xFF16A34A), label: 'Net'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_WeeklyFinanceData> _loadData() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = today.subtract(const Duration(days: 6));
    final days = List.generate(7, (i) => firstDay.add(Duration(days: i)));

    final versementsByDay = <String, double>{for (final d in days) _dayKey(d): 0};
    final achatsByDay = <String, double>{for (final d in days) _dayKey(d): 0};

    // Lecture des agregats journaliers (au plus 7 documents) au lieu de
    // scanner toute la base de patients/achats du cabinet.
    try {
      final statsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('daily_stats')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
          .orderBy('date', descending: false)
          .get();
      for (final doc in statsSnap.docs) {
        final data = doc.data();
        final key = (data['dayKey'] ?? doc.id).toString();
        if (!versementsByDay.containsKey(key)) continue;
        versementsByDay[key] = (data['versementsTotal'] as num?)?.toDouble() ?? 0;
        achatsByDay[key] = (data['achatsTotal'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {
      // En cas d'erreur on renvoie des valeurs a zero plutot que de
      // scanner toute la base (ce qui faisait planter l'application).
    }

    final netByDay = <String, double>{};
    for (final d in days) {
      final key = _dayKey(d);
      netByDay[key] = (versementsByDay[key] ?? 0) - (achatsByDay[key] ?? 0);
    }

    final maxVal = [
      ...versementsByDay.values,
      ...achatsByDay.values,
      ...netByDay.values
    ].fold<double>(0, (p, e) => e.abs() > p ? e.abs() : p);

    return _WeeklyFinanceData(
      days: days,
      versements: versementsByDay,
      achats: achatsByDay,
      net: netByDay,
      maxValue: maxVal,
    );
  }

}

class _WeeklyFinanceData {
  final List<DateTime> days;
  final Map<String, double> versements;
  final Map<String, double> achats;
  final Map<String, double> net;
  final double maxValue;

  double get totalVersements => versements.values.fold<double>(0, (p, e) => p + e);
  double get totalAchats => achats.values.fold<double>(0, (p, e) => p + e);
  double get totalNet => net.values.fold<double>(0, (p, e) => p + e);

  _WeeklyFinanceData({
    required this.days,
    required this.versements,
    required this.achats,
    required this.net,
    required this.maxValue,
  });
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final textMuted = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: textMuted)),
      ],
    );
  }
}

class _NetDailyCardPrincipal extends StatelessWidget {
  final String parentUid;
  const _NetDailyCardPrincipal({required this.parentUid});

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statsStream =
        StatsService().dailyStatsDoc(parentUid: parentUid, dayKey: _todayKey());
    return StreamBuilder<Map<String, dynamic>?>(
      stream: statsStream,
      builder: (context, statsSnap) {
        final data = statsSnap.data;
        if (data != null) {
          final versementsTotal = _asDouble(data['versementsTotal']) ?? 0;
          final versementsCount = (data['versementsCount'] as num?)?.toInt() ?? 0;
          final achatsTotal = _asDouble(data['achatsTotal']) ?? 0;
          final achatsCount = (data['achatsCount'] as num?)?.toInt() ?? 0;
          return _buildNetCard(
            context,
            versementsTotal: versementsTotal,
            versementsCount: versementsCount,
            achatsTotal: achatsTotal,
            achatsCount: achatsCount,
          );
        }
        // Aucun document de stats du jour => aucune operation aujourd'hui.
        return _buildNetCard(
          context,
          versementsTotal: 0,
          versementsCount: 0,
          achatsTotal: 0,
          achatsCount: 0,
        );
      },
    );
  }

  Widget _buildNetCard(
    BuildContext context, {
    required double versementsTotal,
    required int versementsCount,
    required double achatsTotal,
    required int achatsCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final net = versementsTotal - achatsTotal;
    final subtitle =
        '${versementsCount == 1 ? "1 versement" : "$versementsCount versements"} - ${achatsCount == 1 ? "1 achat" : "$achatsCount achats"}';
    return FluentCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.teal.withOpacity(0.12),
            child: const Icon(Icons.summarize_outlined, color: Colors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Net du jour', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: textMuted)),
                Text(
                  'Versements: DA ${_formatMoney(versementsTotal)}   Achats: DA ${_formatMoney(achatsTotal)}',
                  style: TextStyle(color: textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            'DA ${_formatMoney(net)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  double? _asDouble(dynamic value) => asDoubleOrNull(value);

  String _formatMoney(double value) {
    final isInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(isInt ? 0 : 2);
  }
}

class _PurchasesCardPrincipal extends StatelessWidget {
  final String parentUid;
  const _PurchasesCardPrincipal({required this.parentUid});

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textMuted = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    final stream = FirebaseFirestore.instance
        .collectionGroup('purchases')
        .where('parentUid', isEqualTo: parentUid)
        .where('dayKey', isEqualTo: _todayKey())
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        double total = 0;
        int count = 0;
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final data = d.data() as Map<String, dynamic>;
            final created = data['createdAt'];
            DateTime? createdAt;
            if (created is Timestamp) createdAt = created.toDate();
            if (created is DateTime) createdAt = created;
            final isToday = (data['dayKey'] ?? '') == _todayKey() ||
                (createdAt != null &&
                    createdAt.year == DateTime.now().year &&
                    createdAt.month == DateTime.now().month &&
                    createdAt.day == DateTime.now().day);
            if (!isToday) continue;
            final m = data['montant'];
            if (m is num) total += m.toDouble();
            count += 1;
          }
        }
        final card = FluentCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.15),
                child: const Icon(Icons.shopping_bag_outlined, color: Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Achats du cabinet (jour)', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      count == 1 ? '1 achat aujourd\'hui' : '$count achats aujourd\'hui',
                      style: TextStyle(color: textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                'DA ${total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 2)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );

        return InkWell(
          onTap: () => _showHistory(context),
          child: card,
        );
      },
    );
  }

  Future<void> _showHistory(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Historique des achats du cabinet'),
        content: SizedBox(
          width: AppTheme.dialogWidth(context, 520),
          height: 440,
          child: _PurchasesHistoryPrincipal(parentUid: parentUid, dayKey: _todayKey()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }
}

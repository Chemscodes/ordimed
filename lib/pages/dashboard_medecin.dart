import 'package:flutter/material.dart';
import 'profile_selector_page.dart';
import 'consultation_page.dart';
import 'patient_details_page.dart';
import 'stats_page.dart';
import '../ui/app_shell.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_button.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/soft_delete.dart';
import '../services/waiting_service.dart';
import '../widgets/daily_versements_card.dart';
import '../core/coerce.dart';
import '../ui/info_display.dart';

int? _toInt(dynamic v) => asIntOrNull(v);

class DashboardMedecin extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final Map<String, dynamic> profileData;

  const DashboardMedecin({
    Key? key,
    required this.parentUid,
    required this.profileId,
    required this.profileData,
  }) : super(key: key);

  @override
  State<DashboardMedecin> createState() => _DashboardMedecinState();
}

class _DashboardMedecinState extends State<DashboardMedecin> {
  int navIndex = 0; // 0 tableau, 1 patients, 2 rdv
  String? _doctorName;

  @override
  void initState() {
    super.initState();
    _doctorName = (widget.profileData['name'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);
    const secondary = Color(0xFF0EA5E9);

    return AppShell(
      title: (_doctorName == null || _doctorName!.isEmpty) ? 'Tableau Medecin' : 'Dr $_doctorName',
      currentIndex: navIndex,
      onNav: (i) => setState(() => navIndex = i),
      navItems: const ['Tableau', 'Patients', 'Salle d\'attente'],
      topActions: [
        FluentButton(
          label: 'Patients',
          icon: Icons.people_alt,
          onPressed: () => setState(() => navIndex = 1),
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
        FluentButton(
          label: 'Modifier mon profil',
          icon: Icons.edit,
          onPressed: () => _editMyProfile(context),
        ),
        const SizedBox(width: 8),
      ],
      actions: [
        IconButton(
          tooltip: 'Retour accueil',
          icon: const Icon(Icons.home_outlined, color: Colors.white),
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
        IconButton(
          tooltip: 'Deconnexion',
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () async {
            await AuthService().signOut();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            }
          },
        ),
      ],
      child: Column(
        children: [
          if (navIndex == 0) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 760;
                final cards = [
                  Expanded(
                    child: FluentCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: secondary.withOpacity(0.15),
                            child: const Icon(Icons.monitor_heart, color: primary),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Suivi actif', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text('Patients en cours'),
                            ],
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
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: primary.withOpacity(0.15),
                            child: const Icon(Icons.event_available, color: primary),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Rendez-vous', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text('Planning a jour'),
                            ],
                          ),
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
              allowedDoctorIds: {widget.profileId, 'medecin_principal'},
            ),
            const SizedBox(height: 12),
            _WeeklyFinanceChartMedecin(
              parentUid: widget.parentUid,
              profileId: widget.profileId,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: Builder(
              builder: (_) {
                if (navIndex == 1) {
                  return _PatientsTab(
                    parentUid: widget.parentUid,
                    profileId: widget.profileId,
                  );
                }
                if (navIndex == 2) {
                  return _RendezVousTab(
                    parentUid: widget.parentUid,
                    profileId: widget.profileId,
                  );
                }
                return const Center(
                  child: Text('Choisis un onglet Patients ou Rendez-vous au-dessus'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMyProfile(BuildContext context) async {
    final profil = await ApiService.instance
        .profils()
        .then(
          (liste) => liste.firstWhere(
            (p) => p['id'] == widget.profileId,
            orElse: () => <String, dynamic>{},
          ),
        );
    final currentName = (profil['name'] ?? _doctorName ?? '').toString();
    final nameCtrl = TextEditingController(text: currentName);

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier mon profil'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom du Medecin'),
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
          const SnackBar(content: Text('Le nom ne peut pas etre vide')),
        );
      }
      return;
    }

    await ApiService.instance.majProfil(widget.profileId, {'name': newName});
    if (mounted) {
      setState(() => _doctorName = newName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis a jour')),
      );
    }
  }
}

class _WeeklyFinanceChartMedecin extends StatelessWidget {
  final String parentUid;
  final String profileId;

  const _WeeklyFinanceChartMedecin({
    required this.parentUid,
    required this.profileId,
  });

  // asDateOrNull accepte l'ISO du backend comme les Timestamp encore
  // presents dans les donnees importees.
  DateTime _asDate(dynamic value) =>
      asDateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final start = DateTime.now();
    final startOfToday = DateTime(start.year, start.month, start.day);
    final firstDay = startOfToday.subtract(const Duration(days: 6));
    final days = List.generate(7, (i) => firstDay.add(Duration(days: i)));
    final dayKeys = days.map(_dayKey).toList();

    final patientsStream = ApiService.instance.patientsFlux(
      profileId: profileId,
    );

    // Le collectionGroup et son filtre `whereIn` sur sept cles disparaissent :
    // la hierarchie n'existe plus, et le filtrage par jour se fait ici sur
    // une liste deja restreinte au cabinet.
    final purchasesStream = ApiService.instance.achatsFlux();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: patientsStream,
      builder: (context, patientSnap) {
        if (!patientSnap.hasData) {
          return const FluentCard(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Prépare les versements par jour
        final versementsByDay = <String, double>{for (var d in days) _dayKey(d): 0};
        for (final data in patientSnap.data!) {
          final versements = data['versements'];
          if (versements is! List) continue;
          for (final v in versements) {
            if (v is! Map) continue;
            final created = _asDate(v['createdAt']);
            if (created.isBefore(firstDay) || created.isAfter(startOfToday.add(const Duration(days: 1)))) {
              continue;
            }
            final key = _dayKey(created);
            versementsByDay[key] = (versementsByDay[key] ?? 0) + (((v['montant'] as num?)?.toDouble()) ?? 0);
          }
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: purchasesStream,
          builder: (context, purchaseSnap) {
            final achatsByDay = <String, double>{for (var d in days) _dayKey(d): 0};
            if (purchaseSnap.hasData) {
              for (final data in purchaseSnap.data!) {
                // Filtrer sur le médecin actuel
                final owner = (data['profileId'] ?? '').toString();
                if (owner.isNotEmpty && owner != profileId) continue;
                // Le repli sur le chemin du document disparait : le cabinet
                // est garanti par le jeton, plus par la place du document
                // dans une hierarchie.

                final created = _asDate(data['createdAt']);
                final key = _dayKey(created);
                if (!achatsByDay.containsKey(key)) continue;
                achatsByDay[key] = (achatsByDay[key] ?? 0) + (((data['montant'] as num?)?.toDouble()) ?? 0);
              }
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
            final safeMax = maxVal <= 0 ? 1 : maxVal;

            final totalVersements = versementsByDay.values.fold<double>(0, (p, e) => p + e);
            final totalAchats = achatsByDay.values.fold<double>(0, (p, e) => p + e);
            final totalNet = netByDay.values.fold<double>(0, (p, e) => p + e);

            Widget bar(double value, Color color) {
              final h = (value.abs() / safeMax) * 90.0;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: h.clamp(4, 90),
                width: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              );
            }

            return FluentCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Finances - 7 derniers jours',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Versements: ${totalVersements.toStringAsFixed(0)} | Achats: ${totalAchats.toStringAsFixed(0)} | Net: ${totalNet.toStringAsFixed(0)}',
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: days.map((d) {
                        final key = _dayKey(d);
                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  bar(versementsByDay[key] ?? 0, const Color(0xFF2563EB)),
                                  const SizedBox(width: 4),
                                  bar(achatsByDay[key] ?? 0, const Color(0xFFF97316)),
                                  const SizedBox(width: 4),
                                  bar(netByDay[key] ?? 0, const Color(0xFF16A34A)),
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
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
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

class _PatientsTab extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final FirestoreService service = FirestoreService();

  _PatientsTab({
    required this.parentUid,
    required this.profileId,
  });

  @override
  State<_PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<_PatientsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final ScrollController _patientsScrollCtrl = ScrollController();
  static const int _pageSize = 60;
  int _limit = _pageSize;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _patientsScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);
    const secondary = Color(0xFF0EA5E9);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final searchGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [scheme.surface, scheme.surfaceVariant]
          : [Colors.white.withOpacity(0.92), const Color(0xFFF1F5F9).withOpacity(0.9)],
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.service.patientsStream(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        orderByCreated: true,
        limit: _limit,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erreur de chargement des patients'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final patients = snapshot.data!;
        final canLoadMore = patients.length >= _limit;

        if (patients.isEmpty) {
          return const Center(
            child: Text(
              'Aucun patient pour le moment',
              style: TextStyle(fontSize: 16),
            ),
          );
        }

        final filtered = patients.where((p) {
          final data = p;
          if (isDeleted(data)) return false;
          final nom = (data['nom'] ?? '').toString();
          final prenom = (data['prenom'] ?? '').toString();
          final full = '$nom $prenom'.toLowerCase();
          if (_query.isEmpty) return true;
          return full.contains(_query);
        }).toList();

        if (filtered.isEmpty) {
          if (canLoadMore && _query.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Aucun patient trouve dans cette page'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _limit += _pageSize),
                    child: const Text('Charger plus'),
                  ),
                ],
              ),
            );
          }
          return const Center(child: Text('Aucun patient trouve'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: secondary.withOpacity(0.15),
                    child: const Icon(Icons.groups, color: primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suivi actif',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          '${patients.length} patients',
                          style: TextStyle(color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.monitor_heart, color: primary),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                gradient: searchGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(isDark ? 0.12 : 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: primary.withOpacity(0.85), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un patient',
                      hintStyle: TextStyle(color: textFaint),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? scheme.secondary.withOpacity(0.18) : const Color(0xFFE8EEF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(isDark ? 0.12 : 0.65)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.tune, size: 16, color: primary),
                      SizedBox(width: 6),
                      Text('Filtres', style: TextStyle(color: primary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
            Expanded(
              child: Scrollbar(
                controller: _patientsScrollCtrl,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _patientsScrollCtrl,
                  itemCount: filtered.length + (canLoadMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (canLoadMore && index >= filtered.length) {
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
                    final patient = filtered[index];
                    final data = patient;

                    final nom = data['nom'] ?? 'Sans nom';
                    final motif = data['motif'] ?? 'Motif non renseigne';
                    final tel = data['tel'] ?? 'Tel non renseigne';
                    final medecin = data['assignedMedecinName'] ?? data['doctorName'] ?? data['doctorId'] ?? '';

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 220 + (index * 30)),
                      tween: Tween(begin: 18, end: 0),
                      builder: (context, offset, child) {
                        return Opacity(
                          opacity: 1 - (offset / 18).clamp(0, 1),
                          child: Transform.translate(
                            offset: Offset(0, offset),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.22)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: secondary.withOpacity(0.15),
                              child: const Icon(
                                Icons.person_outline,
                                color: primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          nom,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17,
                                            color: textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (motif.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: secondary.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            motif,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tel : $tel',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (medecin.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Medecin : $medecin',
                                      style: TextStyle(
                                        color: textFaint,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.article_outlined),
                                  color: primary,
                                  tooltip: 'Dossier patient',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PatientDetailsPage(
                                          patientId: patient['id'].toString(),
                                          patientName: nom,
                                          parentUid: widget.parentUid,
                                          ownerProfileId: widget.profileId,
                                          canAddForm: true,
                                          canAddDoctorForm: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.phone),
                                  color: Colors.green.shade600,
                                  tooltip: 'Contacter',
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


class _RendezVousTab extends StatefulWidget {
  final String parentUid;
  final String profileId;

  _RendezVousTab({
    required this.parentUid,
    required this.profileId,
  });

  @override
  State<_RendezVousTab> createState() => _RendezVousTabState();
}

class _RendezVousTabState extends State<_RendezVousTab> {
  static const int _pageSize = 120;
  static const int _lookbackDays = 7;
  int _limit = _pageSize;
  bool _showAll = false;
  final WaitingService _waitingService = WaitingService();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedIcon = scheme.onSurface.withOpacity(0.65);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final recentCutoff = startOfDay.subtract(const Duration(days: _lookbackDays));
    final stream = ApiService.instance.salleAttenteFlux(
      profileId: widget.profileId,
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erreur de chargement de la salle d\'attente'));
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

        for (final data in docs) {
          final status = (data['status'] ?? '').toString();
          final closedTs = asDateOrNull(data['closedAt']);
          final isDone = status == 'done' || closedTs != null;
          if (isDone) {
            if (closedTs != null &&
                closedTs.isAfter(startOfDay.subtract(const Duration(milliseconds: 1))) &&
                closedTs.isBefore(endOfDay)) {
              historyToday.add(data);
            }
            continue;
          }
          if (status == 'in_consultation') {
            inConsultation.add(data);
            continue;
          }
          waiting.add(data);
        }

        if (waiting.isEmpty && inConsultation.isEmpty && historyToday.isEmpty) {
          return const Center(child: Text('Aucun patient pour aujourd\'hui'));
        }

        final canLoadMore = docs.length >= _limit;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    'En consultation : ${inConsultation.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Salle d\'attente : ${waiting.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _showAll = !_showAll;
                      _limit = _pageSize;
                    }),
                    child: Text(_showAll ? 'Voir recents' : 'Voir tout'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'En consultation',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (inConsultation.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('Aucun patient en consultation'),
                    )
                  else
                    ...List.generate(inConsultation.length, (index) {
                      final data = inConsultation[index];
                      final patient = data['patientNom'] ?? 'Patient';
                      final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                      final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                      final seancesTotal = _toInt(data['nombreSeances']);
                      final seancesDone = _toInt(data['seancesEffectuees']);
                      final started = asDateOrNull(data['inConsultationAt']);
                      final startStr = started != null
                          ? '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}'
                          : '';
                      return FluentCard(
                        margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                        padding: const EdgeInsets.all(14),
                        child: ListTile(
                          leading: const Icon(Icons.local_hospital, color: Color(0xFF2563EB)),
                          title: Text(patient),
                          subtitle: MetaLine(items: [
if (doctor.isNotEmpty) 'Dr $doctor',
                              if (assistant.isNotEmpty) assistant,
                              if (seancesDone != null || seancesTotal != null)
                                'Séance ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                              'En consultation depuis $startStr',
]),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Ouvrir le dossier',
                                icon: const Icon(Icons.folder_open_outlined),
                                onPressed: () => _openPatient(context, data),
                              ),
                              // La cloture se fait au bout du parcours guide,
                              // apres le recapitulatif : le medecin voit ce
                              // qu'il a fait avant de terminer.
                              FluentButton(
                                label: 'Reprendre',
                                icon: Icons.play_arrow_rounded,
                                compact: true,
                                onPressed: () => _ouvrirConsultation(
                                  context,
                                  inConsultation[index],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'Salle d\'attente',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                        final data = waiting[index];
                        final patient = data['patientNom'] ?? 'Patient';
                        final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                        final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                        final seancesTotal = _toInt(data['nombreSeances']);
                        final seancesDone = _toInt(data['seancesEffectuees']);
                        final created = asDateOrNull(data['createdAt']);
                        final createdStr = created != null
                            ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                            : '';
                        return FluentCard(
                          margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
                          padding: const EdgeInsets.all(14),
                          child: ListTile(
                            leading: const Icon(Icons.meeting_room_outlined, color: Color(0xFF2563EB)),
                            title: Text(patient),
                            subtitle: MetaLine(items: [
if (doctor.isNotEmpty) 'Dr $doctor',
                                if (assistant.isNotEmpty) assistant,
                                if (seancesDone != null || seancesTotal != null)
                                  'Séance ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                                'Arrivée $createdStr',
]),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  tooltip: 'Ouvrir dossier',
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: () => _openPatient(context, data),
                                ),
                                // « En consultation » nommait l'etat d'arrivee,
                                // pas le geste. Un bouton dit ce qu'il fait.
                                FluentButton(
                                  label: 'Consulter',
                                  icon: Icons.play_arrow_rounded,
                                  compact: true,
                                  onPressed: () => _demarrerEtConsulter(
                                    context,
                                    waiting[index],
                                  ),
                                ),
                              ],
                            ),
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
                              final data = historyToday[index];
                              final patient = data['patientNom'] ?? 'Patient';
                              final doctor = (data['doctorName'] ?? data['doctorId'] ?? '').toString();
                              final assistant = (data['assistantName'] ?? data['assistantId'] ?? '').toString();
                              final closed = asDateOrNull(data['closedAt']);
                              final closedStr = closed != null
                                  ? '${closed.hour.toString().padLeft(2, '0')}:${closed.minute.toString().padLeft(2, '0')}'
                                  : '';
                              return ListTile(
                                leading: Icon(Icons.history, color: mutedIcon),
                                title: Text(patient),
                                subtitle: MetaLine(items: [
if (doctor.isNotEmpty) 'Dr $doctor',
                                    if (assistant.isNotEmpty) assistant,
                                    'Reçu $closedStr',
]),
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

  /// Ouvre la consultation guidee pour un patient deja en consultation.
  Future<void> _ouvrirConsultation(
    BuildContext context,
    Map<String, dynamic> doc,
  ) async {
    final data = doc;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultationPage(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingId: doc['id'].toString(),
          waitingData: data,
        ),
      ),
    );
  }

  /// Marque le patient en consultation, puis enchaine sur le parcours.
  ///
  /// Les deux gestes etaient separes : le medecin cliquait « Demarrer », le
  /// patient changeait de liste, et rien ne lui disait quoi faire ensuite.
  Future<void> _demarrerEtConsulter(
    BuildContext context,
    Map<String, dynamic> doc,
  ) async {
    await _startConsultation(context, doc);
    if (!context.mounted) return;
    await _ouvrirConsultation(context, doc);
  }

  Future<void> _startConsultation(
    BuildContext context,
    Map<String, dynamic> doc,
  ) async {
    final data = doc;
    await _waitingService.markInConsultation(
      parentUid: widget.parentUid,
      profileId: widget.profileId,
      waitingId: doc['id'].toString(),
      doctorId: (data['doctorId'] ?? '').toString(),
      assistantId: (data['assistantId'] ?? '').toString(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient en consultation')),
      );
    }
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

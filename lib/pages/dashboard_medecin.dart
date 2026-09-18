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
import '../widgets/consultation_alert_banner.dart';
import '../widgets/kpi_row.dart';
import '../widgets/patient_status_indicator.dart';
import '../widgets/salle_attente_board.dart';

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
    return AppShell(
      title: (_doctorName == null || _doctorName!.isEmpty)
          ? 'Tableau Medecin'
          : 'Dr $_doctorName',
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
              builder: (_) => StatsPage(
                parentUid: widget.parentUid,
                title: 'Stats du cabinet',
              ),
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
          icon: const Icon(Icons.home_outlined),
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
          tooltip: 'Déconnexion',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            await AuthService().signOut();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            }
          },
        ),
      ],
      child: Column(
        children: [
          ConsultationAlertBanner(
            parentUid: widget.parentUid,
            profileId: widget.profileId,
            allowedDoctorIds: {widget.profileId, 'medecin_principal'},
          ),
          if (navIndex == 0) ...[
            const SizedBox(height: 8),
            KpiRow(
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
                  child: Text(
                    'Choisis un onglet Patients ou Rendez-vous au-dessus',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMyProfile(BuildContext context) async {
    final profil = await ApiService.instance.profils().then(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil mis a jour')));
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

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final start = DateTime.now();
    final startOfToday = DateTime(start.year, start.month, start.day);
    final firstDay = startOfToday.subtract(const Duration(days: 6));
    final days = List.generate(7, (i) => firstDay.add(Duration(days: i)));

    // Un seul listener sur sept petits documents `daily_stats`, plutôt que
    // deux listeners sur tout l'historique des patients et des achats du
    // cabinet — même levier que pour le KPI « Recettes du jour ».
    //
    // Les versements se lisent par médecin (`doctorVersements`, déjà écrit
    // par `encaisser`). Les achats, eux, n'ont jamais été attribués à un
    // médecin — ils sont créés par l'assistant qui les enregistre, avec son
    // propre `profileId`, jamais celui du médecin. Le filtre `owner ==
    // profileId` qu'avait ce graphique ne matchait donc jamais rien : la
    // colonne « Achats » était déjà à zéro pour tous les médecins. On
    // affiche le total du cabinet à la place — le seul chiffre qui ait un
    // sens ici — plutôt que de perpétuer un filtre mort.
    final statsStream = ApiService.instance.statsFlux(
      depuis: _dayKey(firstDay),
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: statsStream,
      builder: (context, statsSnap) {
        if (!statsSnap.hasData) {
          return const FluentCard(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final parJour = <String, Map<String, dynamic>>{
          for (final doc in statsSnap.data!) '${doc['dayKey']}': doc,
        };

        final versementsByDay = <String, double>{
          for (var d in days) _dayKey(d): 0,
        };
        final achatsByDay = <String, double>{for (var d in days) _dayKey(d): 0};
        for (final d in days) {
          final key = _dayKey(d);
          final doc = parJour[key];
          if (doc == null) continue;
          final parMedecin = doc['doctorVersements'];
          if (parMedecin is Map) {
            final entree = parMedecin[profileId];
            if (entree is Map) {
              versementsByDay[key] =
                  ((entree['total'] as num?)?.toDouble()) ?? 0;
            }
          }
          achatsByDay[key] = ((doc['achatsTotal'] as num?)?.toDouble()) ?? 0;
        }

        final netByDay = <String, double>{};
        for (final d in days) {
          final key = _dayKey(d);
          netByDay[key] = (versementsByDay[key] ?? 0) - (achatsByDay[key] ?? 0);
        }

        final maxVal = [
          ...versementsByDay.values,
          ...achatsByDay.values,
          ...netByDay.values,
        ].fold<double>(0, (p, e) => e.abs() > p ? e.abs() : p);
        final safeMax = maxVal <= 0 ? 1 : maxVal;

        final totalVersements = versementsByDay.values.fold<double>(
          0,
          (p, e) => p + e,
        );
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
                              bar(
                                versementsByDay[key] ?? 0,
                                const Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 4),
                              bar(
                                achatsByDay[key] ?? 0,
                                const Color(0xFFF97316),
                              ),
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
              ),
            ],
          ),
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

  _PatientsTab({required this.parentUid, required this.profileId});

  @override
  State<_PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<_PatientsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final ScrollController _patientsScrollCtrl = ScrollController();
  static const int _pageSize = 60;
  int _limit = _pageSize;

  /// Sous ce seuil, deux lettres correspondent à trop de patients pour
  /// être utiles — pas de recherche lancée.
  static const int _seuilRecherche = 3;

  /// Une seule lecture par session de recherche — sans ce cache, chaque
  /// caractère tapé rouvrirait une lecture complète des patients scopés.
  /// Pas de liste par défaut ici (contrairement à `PatientsPage`) : c'est
  /// l'outil de travail quotidien du médecin sur son propre roster de
  /// patients réguliers, une fenêtre "récents" serait vide la plupart du
  /// temps.
  Future<List<Map<String, dynamic>>>? _rechercheComplete;

  void _onQueryChanged(String v) {
    final query = v.trim().toLowerCase();
    setState(() {
      _query = query;
      if (query.length < _seuilRecherche) {
        _rechercheComplete = null;
      } else {
        _rechercheComplete ??= ApiService.instance.patients(
          profileId: widget.profileId,
        );
      }
    });
  }

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
          : [
              Colors.white.withOpacity(0.92),
              const Color(0xFFF1F5F9).withOpacity(0.9),
            ],
    );

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
                      'Recherchez un patient par nom',
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
              border: Border.all(
                color: Colors.white.withOpacity(isDark ? 0.12 : 0.55),
              ),
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
                Icon(
                  Icons.search_rounded,
                  color: primary.withOpacity(0.85),
                  size: 20,
                ),
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
                    onChanged: _onQueryChanged,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.secondary.withOpacity(0.18)
                        : const Color(0xFFE8EEF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(isDark ? 0.12 : 0.65),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.tune, size: 16, color: primary),
                      SizedBox(width: 6),
                      Text(
                        'Filtres',
                        style: TextStyle(color: primary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _query.length < _seuilRecherche
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tapez au moins 3 lettres pour rechercher un patient.',
                      style: TextStyle(fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: _rechercheComplete,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Erreur de chargement des patients'),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final tous = snapshot.data!;
                    final patients = tous.length > _limit
                        ? tous.sublist(0, _limit)
                        : tous;
                    final canLoadMore = tous.length > _limit;

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
                      return full.contains(_query);
                    }).toList();

                    if (filtered.isEmpty) {
                      if (canLoadMore) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Aucun patient trouve dans cette page',
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () =>
                                    setState(() => _limit += _pageSize),
                                child: const Text('Charger plus'),
                              ),
                            ],
                          ),
                        );
                      }
                      return const Center(child: Text('Aucun patient trouve'));
                    }

                    return Scrollbar(
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
                                  onPressed: () =>
                                      setState(() => _limit += _pageSize),
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
                          final medecin =
                              data['assignedMedecinName'] ??
                              data['doctorName'] ??
                              data['doctorId'] ??
                              '';

                          return TweenAnimationBuilder<double>(
                            duration: Duration(
                              milliseconds: 220 + (index * 30),
                            ),
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
                              margin: const EdgeInsets.only(
                                bottom: 12,
                                left: 12,
                                right: 12,
                              ),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.22),
                                ),
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
                                    backgroundColor: secondary.withOpacity(
                                      0.15,
                                    ),
                                    child: const Icon(
                                      Icons.person_outline,
                                      color: primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: secondary.withOpacity(
                                                    0.18,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
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
                                        PatientStatusIndicator(
                                          patientData: data,
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
                                        icon: const Icon(
                                          Icons.article_outlined,
                                        ),
                                        color: primary,
                                        tooltip: 'Dossier patient',
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PatientDetailsPage(
                                                    patientId: patient['id']
                                                        .toString(),
                                                    patientName: nom,
                                                    parentUid: widget.parentUid,
                                                    ownerProfileId:
                                                        widget.profileId,
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RendezVousTab extends StatefulWidget {
  final String parentUid;
  final String profileId;

  _RendezVousTab({required this.parentUid, required this.profileId});

  @override
  State<_RendezVousTab> createState() => _RendezVousTabState();
}

class _RendezVousTabState extends State<_RendezVousTab> {
  final WaitingService _waitingService = WaitingService();

  @override
  Widget build(BuildContext context) {
    return SalleAttenteBoard(
      profileId: widget.profileId,
      actions: SalleAttenteRowActions(
        onConsulter: (ctx, entry) => _demarrerEtConsulter(ctx, entry),
        onReprendre: (ctx, entry) => _ouvrirConsultation(ctx, entry),
        onOuvrirDossier: (ctx, entry) => _openPatient(ctx, entry),
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient en consultation')));
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

import '../ui/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accueil_patient_page.dart';
import 'patient_details_page.dart';
import 'profile_selector_page.dart';
import 'stats_page.dart';
import '../services/firestore_service.dart';
import '../core/creneaux.dart';
import '../core/doctor_form_prototype.dart';
import '../core/parcours.dart';
import '../services/api_client.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/rendezvous_repository.dart';
import 'choix_creneau_page.dart';
import '../services/soft_delete.dart';
import '../services/stats_service.dart';
import '../services/waiting_service.dart';
import '../ui/app_shell.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../widgets/kpi_row.dart';
import '../widgets/patient_status_indicator.dart';
import '../widgets/salle_attente_board.dart';
import '../core/coerce.dart';
import '../widgets/patient_filters.dart';

/// Rend le contenu d'un dialogue defilable et borne sa hauteur.
///
/// Un `content: Column(...)` deborde des que la fenetre est courte ou que
/// l'utilisateur agrandit la taille du texte. Cette enveloppe supprime la
/// classe entiere de ces debordements verticaux.
Widget _scrollableDialogContent(BuildContext context, Widget child) {
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: AppTheme.dialogMaxHeight(context)),
    child: SingleChildScrollView(child: child),
  );
}

double _toDouble(dynamic v) => asDouble(v);

class DashboardAssistant extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final Map<String, dynamic> profileData;

  const DashboardAssistant({
    Key? key,
    required this.parentUid,
    required this.profileId,
    required this.profileData,
  }) : super(key: key);

  @override
  State<DashboardAssistant> createState() => _DashboardAssistantState();
}

class _DashboardAssistantState extends State<DashboardAssistant> {
  static const primary = Color(0xFF0F766E);
  static const secondary = Color(0xFFF59E0B);

  int navIndex =
      0; // 0 dashboard, 1 patients, 2 salle d'attente, 3 rdv planifies
  final RendezVousRepository rdvRepo = RendezVousRepository();
  final WaitingService waitingService = WaitingService();

  String? _assistantName;
  List<String> _motifs = const ['perte', 'prise'];
  List<String> _motifsForPatientsTab = const ['perte', 'prise'];
  Map<String, List<String>> _motifPrototypes = {};
  @override
  void initState() {
    super.initState();
    _assistantName = (widget.profileData['name'] ?? '').toString();
    _refreshMotifs();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addAchat(BuildContext context) async {
    final produitCtrl = TextEditingController();
    final fournisseurCtrl = TextEditingController();
    final montantCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouvel achat'),
        content: _scrollableDialogContent(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: produitCtrl,
                decoration: const InputDecoration(labelText: 'Produit'),
              ),
              TextField(
                controller: fournisseurCtrl,
                decoration: const InputDecoration(labelText: 'Fournisseur'),
              ),
              TextField(
                controller: montantCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Prix d\'achat'),
              ),
            ],
          ),
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

    final montant = double.tryParse(montantCtrl.text.replaceAll(',', '.'));
    if (montant == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Montant invalide')));
      }
      return;
    }

    // La statistique du jour est mise a jour par la meme transaction cote
    // serveur : c'etait une seconde ecriture apres coup, qui pouvait
    // echouer seule et fausser les chiffres du cabinet.
    await ApiService.instance.creerAchat({
      'produit': produitCtrl.text.trim(),
      'fournisseur': fournisseurCtrl.text.trim(),
      'montant': montant,
      'profileId': widget.profileId,
      'dayKey': _todayKey(),
      'parentUid': widget.parentUid,
    });
    await StatsService().addAchat(
      parentUid: widget.parentUid,
      montant: montant,
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Achat enregistre')));
    }
  }

  Future<void> _planifierRdv(
    Map<String, dynamic> patient,
    String patientId,
  ) async {
    final doctorId = (patient['doctorId'] ?? '').toString();
    if (doctorId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun Medecin assigne a ce patient')),
        );
      }
      return;
    }

    // Un selecteur de date puis un d'heure laissaient choisir n'importe
    // quelle minute sans regarder ce qui etait deja pris. L'agenda du
    // medecin decide desormais de ce qui est proposable.
    final creneau = await Navigator.push<Creneau>(
      context,
      MaterialPageRoute(
        builder: (_) => ChoixCreneauPage(
          parentUid: widget.parentUid,
          doctorId: doctorId,
          doctorName: (patient['assignedMedecinName'] ?? '').toString(),
          patient: [
            (patient['nom'] ?? '').toString(),
            (patient['prenom'] ?? '').toString(),
          ].where((s) => s.trim().isNotEmpty).join(' '),
        ),
      ),
    );
    if (creneau == null) return;
    final dt = creneau.debut;

    String reminderTemplate = '';
    try {
      final profils = await ApiService.instance.profils();
      final moi = profils.firstWhere(
        (p) => p['id'] == widget.profileId,
        orElse: () => <String, dynamic>{},
      );
      reminderTemplate = (moi['whatsappTemplate'] ?? '').toString().trim();
    } catch (_) {}

    final rdvData = {
      'patientId': patientId,
      'patientNom': patient['nom'] ?? '',
      'patientPrenom': patient['prenom'] ?? '',
      'patientTel': patient['tel'] ?? '',
      'doctorId': doctorId,
      'doctorName': patient['assignedMedecinName'] ?? '',
      'assistantId': widget.profileId,
      'motif': patient['motif'] ?? '',
      'datetime': dt.toIso8601String(),
      // Sans la duree, tout rendez-vous serait suppose durer le temps par
      // defaut : une consultation d'une heure laisserait libres des creneaux
      // qu'elle occupe en realite.
      'duree': creneau.duree,
    };
    if (reminderTemplate.isNotEmpty) {
      rdvData['reminderTemplate'] = reminderTemplate;
    }

    await rdvRepo.planifier(
      parentUid: widget.parentUid,
      doctorId: doctorId,
      assistantId: widget.profileId,
      rdvData: rdvData,
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rendez-vous planifie')));
    }
  }

  /// Supprime les rendez-vous deja passes.
  ///
  /// Chaque suppression effacait trois copies — profil, medecin, medecin
  /// principal — avec un `catchError` sur chacune : une copie manquante ne
  /// devait pas interrompre le nettoyage. Un document unique rend tout cela
  /// sans objet.
  Future<void> _clearPastRdv() async {
    final now = DateTime.now();

    final tous = await ApiService.instance.rendezVous(
      profileId: widget.profileId,
      limit: 1000,
    );
    final passes = tous.where((r) {
      final d = asDateOrNull(r['datetime']);
      return d != null && d.isBefore(now);
    }).toList();

    if (passes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun rendez-vous Passe')),
        );
      }
      return;
    }

    for (final r in passes) {
      try {
        await ApiService.instance.supprimerRendezVous(
          (r['id'] ?? '').toString(),
        );
      } catch (_) {
        // Un echec isole ne doit pas interrompre le nettoyage.
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${passes.length} RDV Passes supprimes')),
      );
    }
  }

  Future<void> _editMyProfile(BuildContext context) async {
    final profil = await ApiService.instance.profils().then(
      (liste) => liste.firstWhere(
        (p) => p['id'] == widget.profileId,
        orElse: () => <String, dynamic>{},
      ),
    );
    final currentName = (profil['name'] ?? _assistantName ?? '').toString();
    final nameCtrl = TextEditingController(text: currentName);

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le profil'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom de l\'assistant'),
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
      setState(() => _assistantName = newName);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil mis a jour')));
    }
  }

  Future<void> _editMotifs(BuildContext context) async {
    final motifs = [..._motifs];
    final ctrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Motifs de consultation'),
          content: _scrollableDialogContent(
            context,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: motifs
                      .map(
                        (m) => Chip(
                          label: Text(m),
                          onDeleted: motifs.length > 1
                              ? () => setState(() => motifs.remove(m))
                              : null,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Ajouter un motif',
                  ),
                  onSubmitted: (v) {
                    final val = v.trim();
                    if (val.isEmpty) return;
                    setState(() {
                      if (!motifs.contains(val)) motifs.add(val);
                      ctrl.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (res != true) return;

    final toSave = [...motifs];
    final pending = ctrl.text.trim();
    if (pending.isNotEmpty && !toSave.contains(pending)) {
      toSave.add(pending);
    }

    final protoMapToSave = _motifPrototypes.map((k, v) => MapEntry(k, v));
    await ApiService.instance.majCabinet({
      'motifsPredefinis': toSave,
      'motifPrototypes': protoMapToSave,
    });

    if (!mounted) return;
    setState(() {
      _motifs = toSave;
      _motifsForPatientsTab = toSave;
    });
    await _refreshMotifs();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motifs mis a jour')));
    }
  }

  Future<void> _refreshMotifs() async {
    try {
      final parentData = await ApiService.instance.cabinet();
      if (!mounted) return;

      List<String> fetchedMotifs = [];
      Map<String, List<String>> fetchedProtos = {};
      final rawMotifs = parentData['motifsPredefinis'];
      if (rawMotifs is List) {
        fetchedMotifs = rawMotifs
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final protoMap = parentData['motifPrototypes'];
      if (protoMap is Map) {
        fetchedProtos = protoMap.map((k, v) {
          List<String> list = [];
          if (v is List) {
            list = v
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
          list = ensureVitals(list);
          return MapEntry(k.toString(), list);
        });
      }

      if (fetchedMotifs.isEmpty || fetchedProtos.isEmpty) {
        // Le repli sur le profil : Firestore gardait les motifs a deux
        // endroits pour les cabinets d'avant leur introduction. Le backend
        // n'en a plus qu'un, mais la lecture reste tolerante.
        final profileData = await ApiService.instance.profils().then(
          (liste) => liste.firstWhere(
            (p) => p['id'] == widget.profileId,
            orElse: () => <String, dynamic>{},
          ),
        );
        if (fetchedMotifs.isEmpty) {
          final profileMotifs = profileData['motifsPredefinis'];
          if (profileMotifs is List) {
            fetchedMotifs = profileMotifs
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        }
        if (fetchedProtos.isEmpty) {
          final profileProtos = profileData['motifPrototypes'];
          if (profileProtos is Map) {
            fetchedProtos = profileProtos.map((k, v) {
              List<String> list = [];
              if (v is List) {
                list = v
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
              }
              list = ensureVitals(list);
              return MapEntry(k.toString(), list);
            });
          }
        }
        // Recopie sur le cabinet ce qui n'existait que sur le profil : les
        // cabinets d'avant l'introduction des motifs les gardaient la.
        if (fetchedMotifs.isNotEmpty || fetchedProtos.isNotEmpty) {
          await ApiService.instance.majCabinet({
            if (fetchedMotifs.isNotEmpty) 'motifsPredefinis': fetchedMotifs,
            if (fetchedProtos.isNotEmpty) 'motifPrototypes': fetchedProtos,
          });
        }
      }

      setState(() {
        if (fetchedMotifs.isNotEmpty) {
          _motifs = fetchedMotifs;
          _motifsForPatientsTab = fetchedMotifs;
        } else {
          _motifs = const ['perte', 'prise'];
          _motifsForPatientsTab = const ['perte', 'prise'];
        }
        if (fetchedProtos.isNotEmpty) {
          _motifPrototypes = fetchedProtos;
        }
      });
    } catch (_) {
      // ignore fetch errors
    }
  }

  Future<void> _editPrototypes(BuildContext context) async {
    final motifsAvail = _motifsForPatientsTab;
    if (motifsAvail.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute d\'abord des motifs')),
        );
      }
      return;
    }
    String selected = motifsAvail.first;
    final ctrl = TextEditingController(
      text: (_motifPrototypes[selected] ?? []).join(', '),
    );
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Prototype par motif'),
          content: _scrollableDialogContent(
            context,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: selected,
                  items: motifsAvail
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      selected = v;
                      ctrl.text = (_motifPrototypes[selected] ?? []).join(', ');
                    });
                  },
                ),
                const SizedBox(height: 8),
                const Text('Champs du formulaire (separes par des virgules)'),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'ex: Champ A, Champ B, Champ C',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (res != true) return;
    var fields = ctrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    fields = ensureVitals(fields);
    _motifPrototypes[selected] = fields;
    await ApiService.instance.majCabinet({'motifPrototypes': _motifPrototypes});
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prototype enregistre')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tabContent;
    if (navIndex == 0) {
      tabContent = Column(
        children: [
          KpiRow(parentUid: widget.parentUid, profileId: widget.profileId),
          const SizedBox(height: 12),
          _NetDailyCardAssistant(parentUid: widget.parentUid),
          const SizedBox(height: 12),
          _PurchasesCard(
            parentUid: widget.parentUid,
            profileId: widget.profileId,
          ),
          const Spacer(),
        ],
      );
    } else if (navIndex == 1) {
      tabContent = _PatientsTab(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        assistantName: _assistantName ?? (widget.profileData['name'] ?? ''),
        onPlanifier: _planifierRdv,
        motifsPredefinis: _motifsForPatientsTab,
        motifsProvider: () => _motifsForPatientsTab,
        motifPrototypes: _motifPrototypes,
      );
    } else if (navIndex == 2) {
      tabContent = _RendezVousTab(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        waitingService: waitingService,
      );
    } else {
      tabContent = _AssistantRdvTab(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        onClearPast: _clearPastRdv,
      );
    }
    return AppShell(
      title: _assistantName == null || _assistantName!.isEmpty
          ? 'Assistant'
          : 'Assistant ${_assistantName!}',
      currentIndex: navIndex,
      onNav: (i) {
        setState(() => navIndex = i);
      },
      navItems: const [
        'Tableau',
        'Patients',
        'Salle d\'attente',
        'Rendez-vous',
      ],
      topActions: [
        FluentButton(
          label: 'Accueillir un patient',
          icon: Icons.person_add_alt_1,
          onPressed: () {
            final motifs = _motifsForPatientsTab.isNotEmpty
                ? _motifsForPatientsTab
                : _motifs;
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccueilPatientPage(
                  parentUid: widget.parentUid,
                  profileId: widget.profileId,
                  waitingService: waitingService,
                  assistantName:
                      _assistantName ?? (widget.profileData['name'] ?? ''),
                  motifsPredefinis: motifs,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        FluentButton(
          label: 'Mes motifs',
          icon: Icons.format_list_bulleted,
          onPressed: () => _editMotifs(context),
        ),
        const SizedBox(width: 8),
        FluentButton(
          label: 'Prototypes motifs',
          icon: Icons.design_services_outlined,
          onPressed: () => _editPrototypes(context),
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
          label: 'Nouvel achat',
          icon: Icons.shopping_cart_checkout_outlined,
          onPressed: () => _addAchat(context),
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
          tooltip: 'Deconnexion',
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
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(navIndex),
                child: tabContent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchasesCard extends StatelessWidget {
  final String parentUid;
  final String profileId;

  const _PurchasesCard({required this.parentUid, required this.profileId});

  String _dayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    // Le total du jour vient de l'agregat `daily_stats`, pas d'un listener
    // sur tout l'historique des achats — meme pattern que
    // `_NetDailyCardAssistant`, qui lit deja ce document pour les memes
    // champs (`achatsTotal`/`achatsCount`).
    final statsStream = StatsService().dailyStatsDoc(
      parentUid: parentUid,
      dayKey: _dayKey(),
    );

    return StreamBuilder<Map<String, dynamic>?>(
      stream: statsStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final total = data == null ? 0.0 : _toDouble(data['achatsTotal']);
        final count = data == null
            ? 0
            : (data['achatsCount'] as num?)?.toInt() ?? 0;
        final card = FluentCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _DashboardAssistantState.secondary.withOpacity(
                  0.15,
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: _DashboardAssistantState.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achats du jour',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      '$count achat(s) aujourd\'hui',
                      style: TextStyle(color: textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                'DA ${total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        );

        return InkWell(onTap: () => _showHistory(context), child: card);
      },
    );
  }

  Future<void> _showHistory(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Historique des achats'),
        content: SizedBox(
          width: AppTheme.dialogWidth(context, 460),
          height: 420,
          child: _PurchasesHistory(
            parentUid: parentUid,
            profileId: null,
            dayKey: _dayKey(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _PurchasesHistory extends StatefulWidget {
  final String parentUid;
  final String? profileId;
  final String? dayKey;

  const _PurchasesHistory({
    required this.parentUid,
    required this.profileId,
    this.dayKey,
  });

  @override
  State<_PurchasesHistory> createState() => _PurchasesHistoryState();
}

class _PurchasesHistoryState extends State<_PurchasesHistory> {
  static const int _pageSize = 100;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    // Une lecture ponctuelle du jour demandé — pas un listener sur tout
    // l'historique des achats du cabinet : ce dialogue s'ouvre à la
    // demande et n'a pas besoin d'être tenu à jour en direct pendant qu'il
    // est fermé.
    final purchasesFuture = ApiService.instance
        .achats(dayKey: widget.dayKey)
        .then(
          (liste) => liste
              .where(
                (a) =>
                    widget.profileId == null ||
                    a['profileId'] == widget.profileId,
              )
              .toList(),
        );

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: purchasesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erreur de chargement des achats'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tous = snapshot.data!;
        // La limite s'applique a l'affichage : dans la requete, elle
        // s'accompagnait d'un tri qui excluait les achats sans `createdAt`.
        final docs = tous.length > _limit ? tous.sublist(0, _limit) : tous;
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun achat'));
        }
        final canLoadMore = tous.length > _limit;
        return ListView.builder(
          itemCount: docs.length + (canLoadMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (canLoadMore && index >= docs.length) {
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
            final data = docs[index];
            final produit = (data['produit'] ?? 'Produit').toString();
            final fournisseur = (data['fournisseur'] ?? '').toString();
            final montant = _toDouble(data['montant']);
            final created = asDateOrNull(data['createdAt']);
            final dateStr = created != null
                ? '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                : '';

            return FluentCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _DashboardAssistantState.primary
                        .withOpacity(0.08),
                    child: const Icon(
                      Icons.receipt_long,
                      color: _DashboardAssistantState.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produit,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        if (fournisseur.isNotEmpty)
                          Text(
                            'Fournisseur: $fournisseur',
                            style: TextStyle(color: textMuted, fontSize: 12),
                          ),
                        if (dateStr.isNotEmpty)
                          Text(
                            dateStr,
                            style: TextStyle(color: textFaint, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'DA ${montant.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NetDailyCardAssistant extends StatelessWidget {
  final String parentUid;

  const _NetDailyCardAssistant({required this.parentUid});

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statsStream = StatsService().dailyStatsDoc(
      parentUid: parentUid,
      dayKey: _todayKey(),
    );
    return StreamBuilder<Map<String, dynamic>?>(
      stream: statsStream,
      builder: (context, statsSnap) {
        final data = statsSnap.data;
        if (data != null) {
          final versementsTotal = _toDouble(data['versementsTotal']);
          final versementsCount =
              (data['versementsCount'] as num?)?.toInt() ?? 0;
          final achatsTotal = _toDouble(data['achatsTotal']);
          final achatsCount = (data['achatsCount'] as num?)?.toInt() ?? 0;
          return _buildNetCard(
            context,
            versementsTotal: versementsTotal,
            versementsCount: versementsCount,
            achatsTotal: achatsTotal,
            achatsCount: achatsCount,
          );
        }
        // Pas de document de stats du jour => aucune operation enregistree.
        // On affiche zero plutot que de scanner toute la base (ce qui
        // faisait planter l'application quand le cabinet grossit).
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
            radius: 20,
            backgroundColor: const Color(0xFF16A34A).withOpacity(0.12),
            child: const Icon(
              Icons.calculate_outlined,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Net du jour',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  String _formatMoney(double value) {
    final isInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(isInt ? 0 : 2);
  }
}

class _PatientsTab extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final String assistantName;
  final Future<void> Function(Map<String, dynamic> patient, String id)
  onPlanifier;
  final List<String> motifsPredefinis;
  final List<String> Function()? motifsProvider;
  final Map<String, List<String>> motifPrototypes;
  final FirestoreService service = FirestoreService();

  static const primary = Color(0xFF0F766E);
  static const secondary = Color(0xFFF59E0B);

  _PatientsTab({
    required this.parentUid,
    required this.profileId,
    required this.assistantName,
    required this.onPlanifier,
    required this.motifsPredefinis,
    this.motifsProvider,
    required this.motifPrototypes,
  });

  @override
  State<_PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<_PatientsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  PatientQuery _pq = const PatientQuery();
  final ScrollController _patientsScrollCtrl = ScrollController();
  final Set<String> _deletingPatientIds = <String>{};
  static const int _pageSize = 60;
  int _limit = _pageSize;

  /// Une seule lecture par session de recherche — sans ce cache, chaque
  /// caractère tapé rouvrirait une lecture complète des patients scopés.
  /// Voir la même logique dans `AccueilPatientPage`/`PatientsPage`.
  Future<List<Map<String, dynamic>>>? _rechercheComplete;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _patientsScrollCtrl.dispose();
    super.dispose();
  }

  /// Sous ce seuil, deux lettres correspondent à trop de patients pour être
  /// utiles — mais un filtre rapide ou un médecin choisi reste immédiat,
  /// lui, il ne dépend pas du texte.
  static const int _seuilRecherche = 3;

  bool _pretPourRecherche(PatientQuery q) =>
      q.texte.length >= _seuilRecherche ||
      q.filtre != PatientFiltre.tous ||
      q.doctorId != null;

  /// Recharge la lecture ponctuelle quand une recherche ou un filtre
  /// devient utilisable, et l'efface quand on revient à "Tous" sans texte.
  void _appliquerQuery(PatientQuery q) {
    setState(() {
      _pq = q;
      if (!_pretPourRecherche(q)) {
        _rechercheComplete = null;
      } else {
        _rechercheComplete ??= ApiService.instance.patients(
          profileId: widget.profileId,
        );
      }
    });
  }

  Future<void> _deletePatient(
    BuildContext context,
    String patientId,
    Map<String, dynamic> patient,
  ) async {
    if (_deletingPatientIds.contains(patientId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer le patient'),
        content: const Text(
          'Le patient disparaitra des listes et de la salle d\'attente.\n\n'
          'Son dossier medical, ses versements et son historique sont '
          'conserves : la suppression peut etre annulee.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingPatientIds.add(patientId));

    try {
      // Trois methodes tenaient ici : marquer les copies du dossier par
      // batch, puis fermer en tache de fond les rendez-vous et les entrees
      // de salle d'attente, puis les rouvrir a l'annulation.
      //
      // Le nettoyage se faisait **apres coup et sans transaction** : un
      // patient supprime pouvait rester dans la file du medecin, qui
      // l'appelait pour rien. Tout part maintenant ensemble, cote serveur.
      await ApiService.instance.supprimerPatient(patientId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Patient retire — dossier conserve'),
            action: SnackBarAction(
              label: 'Annuler',
              onPressed: () => ApiService.instance.restaurerPatient(patientId),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Echec de la suppression')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingPatientIds.remove(patientId));
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = _PatientsTab.primary;
    const secondary = _PatientsTab.secondary;
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
                child: const Icon(Icons.assignment_ind, color: primary),
              ),
              const SizedBox(width: 12),
              const Text(
                'Patients crees',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
                    onChanged: (v) => _appliquerQuery(
                      _pq.copyWith(texte: v.trim().toLowerCase()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Barre de filtres reelle. L'ancienne pastille « Filtres » etait
        // purement decorative : elle n'ouvrait rien et ne filtrait rien.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: PatientFilterBar(
            query: _pq,
            onChanged: (q) {
              if (q.texte != _searchCtrl.text.trim().toLowerCase()) {
                _searchCtrl.text = q.texte;
              }
              _appliquerQuery(q);
            },
          ),
        ),
        Expanded(
          child: !_pretPourRecherche(_pq)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tapez un nom ou choisissez un filtre pour retrouver un patient.',
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

                    // Un seul point de decision pour la recherche, les filtres
                    // rapides, le medecin et la suppression douce.
                    final filtered = _pq.filtrer(patients);

                    if (filtered.isEmpty) {
                      if (canLoadMore && _pq.actif) {
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

                          final nom = (data['nom'] ?? 'Sans nom').toString();
                          final motif = (data['motif'] ?? 'Motif non renseigne')
                              .toString();
                          final medecin =
                              (data['assignedMedecinName'] ??
                                      data['doctorName'] ??
                                      data['doctorId'] ??
                                      'Non assigne')
                                  .toString();

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
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withOpacity(0.16),
                                    Colors.white.withOpacity(0.06),
                                  ],
                                ),
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
                                  Container(
                                    width: 4,
                                    height: 46,
                                    margin: const EdgeInsets.only(top: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [secondary, primary],
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
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
                                          'Medecin : $medecin',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
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
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.event_available),
                                        color: secondary,
                                        onPressed: () => widget.onPlanifier(
                                          data,
                                          patient['id'].toString(),
                                        ),
                                        tooltip: 'Planifier un rendez-vous',
                                      ),
                                      if (_deletingPatientIds.contains(
                                        patient['id'].toString(),
                                      ))
                                        const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          color: scheme.error,
                                          onPressed: () => _deletePatient(
                                            context,
                                            patient['id'].toString(),
                                            data,
                                          ),
                                          tooltip: 'Supprimer patient',
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

class _AssistantRdvTab extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final Future<void> Function() onClearPast;

  const _AssistantRdvTab({
    required this.parentUid,
    required this.profileId,
    required this.onClearPast,
  });

  @override
  State<_AssistantRdvTab> createState() => _AssistantRdvTabState();
}

class _AssistantRdvTabState extends State<_AssistantRdvTab> {
  static const int _pageSize = 50;
  static const int _recentDays = 60;
  int _limit = _pageSize;
  bool _showAll = false;
  String _whatsappTemplate = '';

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadWhatsappTemplate();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _isReminderWindow(DateTime dt, DateTime now) {
    final minutes = dt.difference(now).inMinutes;
    return minutes >= 0 && minutes <= 60;
  }

  /// Rendez-vous en cours de mise en salle, pour ne pas placer deux fois.
  final Set<String> _enCoursArrivee = <String>{};

  /// Le patient n'est pas venu.
  ///
  /// Une etape a part entiere, pas une absence de donnee : un rendez-vous
  /// non honore laisse un creneau vide, et savoir qui ne vient pas est une
  /// information de gestion que le cabinet n'avait aucun moyen de retenir.
  Future<void> _noterAbsent(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> rdv,
  ) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Noter le patient absent ?'),
        content: Text(
          '${rdv['patientNom'] ?? 'Ce patient'} sera marque absent pour ce '
          'rendez-vous. Le creneau reste dans l\'historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Noter absent'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    if (!context.mounted) return;
    await _changerEtapeRdv(context, rdvId, rdv, EtapeParcours.absent);
  }

  /// Fait avancer un rendez-vous d'une etape.
  Future<void> _changerEtapeRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> rdv,
    EtapeParcours etape,
  ) async {
    try {
      await RendezVousRepository().changerEtape(
        parentUid: widget.parentUid,
        rdvId: rdvId,
        doctorId: (rdv['doctorId'] ?? '').toString(),
        assistantId: (rdv['assistantId'] ?? widget.profileId).toString(),
        etape: etape,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Echec de l\'enregistrement')),
      );
    }
  }

  /// Le patient se presente a l'accueil.
  ///
  /// C'etait le trou du parcours : l'assistant voyait le rendez-vous ici et
  /// devait aller ressaisir le patient dans la salle d'attente, alors que le
  /// rendez-vous portait deja son nom, son medecin et son motif.
  Future<void> _marquerArrive(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> rdv,
  ) async {
    if (_enCoursArrivee.contains(rdvId)) return;
    setState(() => _enCoursArrivee.add(rdvId));
    try {
      final place = await RendezVousRepository().marquerArrive(
        parentUid: widget.parentUid,
        rdvId: rdvId,
        rdv: rdv,
        profileId: widget.profileId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            place
                ? 'Patient place en salle d\'attente'
                : 'Ce patient est deja dans la file',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Echec de la mise en salle')),
      );
    } finally {
      if (mounted) setState(() => _enCoursArrivee.remove(rdvId));
    }
  }

  String _formatWhatsappNumber(String raw) {
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  String _defaultWhatsappTemplate() {
    return 'Bonjour {patient}, rappel: votre rendez-vous est le {date} a {heure}. '
        'Merci de repondre si vous ne pouvez pas venir.';
  }

  String _applyTemplate(String template, Map<String, String> values) {
    var result = template;
    values.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  Future<void> _loadWhatsappTemplate() async {
    try {
      final profils = await ApiService.instance.profils();
      final moi = profils.firstWhere(
        (p) => p['id'] == widget.profileId,
        orElse: () => <String, dynamic>{},
      );
      final template = (moi['whatsappTemplate'] ?? '').toString();
      if (mounted) {
        setState(() => _whatsappTemplate = template);
      }
    } catch (_) {
      // keep default
    }
  }

  Future<void> _saveWhatsappTemplate(String template) async {
    // L'horodatage de mise a jour est pose par le serveur.
    await ApiService.instance.majProfil(widget.profileId, {
      'whatsappTemplate': template,
    });
    if (mounted) {
      setState(() => _whatsappTemplate = template);
    }
  }

  Future<void> _editWhatsappTemplate(BuildContext context) async {
    final controller = TextEditingController(
      text: _whatsappTemplate.trim().isEmpty
          ? _defaultWhatsappTemplate()
          : _whatsappTemplate.trim(),
    );
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Message WhatsApp'),
        content: _scrollableDialogContent(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText:
                      'Utilise {patient}, {date}, {heure}, {medecin}, {motif}',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Variables: {patient} {prenom} {nom} {date} {heure} {medecin} {motif}',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (res != true) return;
    final value = controller.text.trim();
    await _saveWhatsappTemplate(value);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message WhatsApp enregistre')),
      );
    }
  }

  String _buildWhatsappMessage(Map<String, dynamic> data, DateTime dt) {
    final nom = (data['patientNom'] ?? '').toString().trim();
    final prenom = (data['patientPrenom'] ?? '').toString().trim();
    final patientName = [
      if (prenom.isNotEmpty) prenom,
      if (nom.isNotEmpty) nom,
    ].join(' ').trim();
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final doctor = (data['doctorName'] ?? data['doctorId'] ?? '')
        .toString()
        .trim();
    final motif = (data['motif'] ?? '').toString().trim();
    final templateFromRdv = (data['reminderTemplate'] ?? '').toString().trim();
    final template = templateFromRdv.isNotEmpty
        ? templateFromRdv
        : (_whatsappTemplate.trim().isEmpty
              ? _defaultWhatsappTemplate()
              : _whatsappTemplate.trim());
    final values = <String, String>{
      'patient': patientName.isNotEmpty ? patientName : 'patient',
      'prenom': prenom,
      'nom': nom,
      'date': dateStr,
      'heure': timeStr,
      'medecin': doctor,
      'motif': motif,
    };
    return _applyTemplate(template, values);
  }

  /// Note qu'un rappel est parti.
  ///
  /// L'horodatage est pose par le serveur : l'heure d'un poste mal regle
  /// ferait apparaitre des rappels envoyes dans le futur, et la fenetre
  /// « disponible 1h avant » cesserait de tomber juste.
  Future<void> _markReminderSent(
    String rdvId,
    Map<String, dynamic> data,
  ) async {
    await ApiService.instance.majRendezVous(rdvId, {'reminderSentAt': true});
  }

  /// Met le numero en cache sur le rendez-vous.
  ///
  /// Le fan-out ecrivait la meme valeur sur la copie du profil et sur celle
  /// du medecin. Un seul document desormais.
  Future<void> _cachePatientTel(
    String rdvId,
    String tel,
    Map<String, dynamic> data,
  ) async {
    try {
      await ApiService.instance.majRendezVous(rdvId, {'patientTel': tel});
    } catch (_) {
      // Un cache qui echoue n'empeche pas d'envoyer le rappel.
    }
  }

  Future<void> _sendWhatsappReminder(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
    DateTime dt,
  ) async {
    final hasCustomTemplate =
        (data['reminderTemplate'] ?? '').toString().trim().isNotEmpty ||
        _whatsappTemplate.trim().isNotEmpty;
    if (!hasCustomTemplate) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez enregistrer un message WhatsApp'),
          ),
        );
      }
      return;
    }
    String rawTel = (data['patientTel'] ?? data['tel'] ?? '').toString().trim();
    if (rawTel.isEmpty) {
      final patientId = (data['patientId'] ?? '').toString();
      if (patientId.isNotEmpty) {
        final dossier = await ApiService.instance.patient(patientId);
        rawTel = (dossier['tel'] ?? '').toString().trim();
        if (rawTel.isNotEmpty) {
          await _cachePatientTel(rdvId, rawTel, data);
        }
      }
    }
    final tel = _formatWhatsappNumber(rawTel);
    if (tel.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Numero WhatsApp manquant')),
        );
      }
      return;
    }
    final message = _buildWhatsappMessage(data, dt);
    final webUrl = Uri.parse(
      'https://web.whatsapp.com/send?phone=$tel&text=${Uri.encodeComponent(message)}',
    );
    try {
      final ok = await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Impossible d'ouvrir WhatsApp")),
          );
        }
        return;
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur ouverture WhatsApp')),
        );
      }
      return;
    }

    await _markReminderSent(rdvId, data);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp ouvert pour le rappel')),
      );
    }
  }

  /// Deplace un rendez-vous.
  ///
  /// Le serveur revalide le creneau : deux postes peuvent poser la meme
  /// heure a la meme seconde, et le controle cote Flutter ne le voit pas.
  /// Un conflit revient en 409.
  Future<void> _updateRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
    DateTime newDateTime,
    String motif, [
    int? duree,
  ]) async {
    try {
      await ApiService.instance.majRendezVous(rdvId, {
        'datetime': newDateTime.toIso8601String(),
        'motif': motif,
        if (duree != null) 'duree': duree,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Rendez-vous mis a jour')));
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.estConflit
                ? 'Ce creneau vient d’etre pris'
                : 'Echec de la mise a jour',
          ),
        ),
      );
    }
  }

  Future<void> _editRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
  ) async {
    final currentDt = asDateOrNull(data['datetime']) ?? DateTime.now();
    DateTime selectedDate = DateTime(
      currentDt.year,
      currentDt.month,
      currentDt.day,
    );
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(currentDt);
    int? dureeChoisie = (data['duree'] as num?)?.toInt();
    final motifCtrl = TextEditingController(
      text: (data['motif'] ?? '').toString(),
    );

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final dateLabel =
              '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}';
          final timeLabel =
              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
          return AlertDialog(
            title: const Text('Modifier rendez-vous'),
            content: _scrollableDialogContent(
              context,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: motifCtrl,
                    decoration: const InputDecoration(labelText: 'Motif'),
                  ),
                  const SizedBox(height: 12),
                  // Deplacer un rendez-vous passait par les memes selecteurs
                  // libres que la prise : on pouvait le poser sur un creneau
                  // deja occupe et contourner toute la detection de conflit.
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text('$dateLabel a $timeLabel'),
                    onPressed: () async {
                      final creneau = await Navigator.push<Creneau>(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => ChoixCreneauPage(
                            parentUid: widget.parentUid,
                            doctorId: (data['doctorId'] ?? '').toString(),
                            doctorName: (data['doctorName'] ?? '').toString(),
                            patient: (data['patientNom'] ?? 'Patient')
                                .toString(),
                            jourInitial: selectedDate,
                            // Un rendez-vous deplace ne doit pas se voir
                            // lui-meme comme l'obstacle a son deplacement.
                            ignorerRdvId: rdvId,
                          ),
                        ),
                      );
                      if (creneau == null) return;
                      setState(() {
                        selectedDate = DateTime(
                          creneau.debut.year,
                          creneau.debut.month,
                          creneau.debut.day,
                        );
                        selectedTime = TimeOfDay.fromDateTime(creneau.debut);
                        dureeChoisie = creneau.duree;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );

    if (res != true) return;

    final newDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    final motif = motifCtrl.text.trim();
    await _updateRdv(context, rdvId, data, newDateTime, motif, dureeChoisie);
  }

  Future<void> _deleteRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer rendez-vous'),
        content: const Text('Voulez-vous supprimer ce rendez-vous ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Un seul document : le batch effacait la copie du profil, celle du
    // medecin, et celle du medecin principal.
    await ApiService.instance.supprimerRendezVous(rdvId);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rendez-vous supprime')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final now = DateTime.now();
    final minDate = now.subtract(const Duration(days: _recentDays));
    // Le filtre de date passe en memoire : une contrainte serveur sur
    // `datetime` ecarterait les rendez-vous qui n'en portent pas.
    final query = ApiService.instance
        .rendezVousFlux(profileId: widget.profileId)
        .map(
          (liste) => _showAll
              ? liste
              : liste.where((r) {
                  final d = asDateOrNull(r['datetime']);
                  return d == null || !d.isBefore(minDate);
                }).toList(),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              const Text(
                'Rendez-vous planifies',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAll = !_showAll;
                    _limit = _pageSize;
                  });
                },
                icon: Icon(
                  _showAll ? Icons.filter_alt_off : Icons.filter_alt_outlined,
                ),
                label: Text(_showAll ? 'Recents $_recentDays j' : 'Voir tout'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _editWhatsappTemplate(context),
                icon: const Icon(Icons.message_outlined),
                label: const Text('Message WhatsApp'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => widget.onClearPast(),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer les RDV Passes'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: query,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                  child: Text('Erreur de chargement des RDV'),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final tous = snap.data!;
              // La limite s'applique a l'affichage : dans la requete, elle
              // s'accompagnait d'un tri qui ecartait les rendez-vous sans
              // date.
              final allDocs = tous.length > _limit
                  ? tous.sublist(0, _limit)
                  : tous;
              final canLoadMore = tous.length > _limit;
              // Masque les rendez-vous des patients retires.
              final docs = allDocs.where((d) => !isDeleted(d)).toList();
              if (docs.isEmpty) {
                return const Center(child: Text('Aucun Rendez-vous planifie'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length + (canLoadMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (canLoadMore && i >= docs.length) {
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
                  final doc = docs[i];
                  final d = doc;
                  final rdvId = doc['id'].toString();
                  final dt = asDateOrNull(d['datetime']);
                  final isPast = dt != null && dt.isBefore(now);
                  final reminderSent = d['reminderSentAt'] != null;
                  final rawTel = (d['patientTel'] ?? d['tel'] ?? '').toString();
                  final hasTel = rawTel.trim().isNotEmpty;
                  final withinWindow = dt != null && _isReminderWindow(dt, now);
                  final minutesTo = dt != null
                      ? dt.difference(now).inMinutes
                      : null;
                  final canSendReminder =
                      dt != null &&
                      !isPast &&
                      !reminderSent &&
                      hasTel &&
                      withinWindow;
                  String reminderTooltip;
                  String? reminderInfo;
                  if (!hasTel) {
                    reminderTooltip = 'Tel manquant';
                    reminderInfo = 'Numero WhatsApp manquant';
                  } else if (dt == null) {
                    reminderTooltip = 'Date non definie';
                    reminderInfo = 'Date du rendez-vous non definie';
                  } else if (isPast) {
                    reminderTooltip = 'Rendez-vous passe';
                    reminderInfo = 'Rendez-vous deja passe';
                  } else if (reminderSent) {
                    reminderTooltip = 'Rappel deja envoye';
                    reminderInfo = 'Rappel deja envoye';
                  } else if (!withinWindow) {
                    reminderTooltip = minutesTo != null && minutesTo > 0
                        ? 'Disponible dans $minutesTo min'
                        : 'Disponible 1h avant';
                    reminderInfo = reminderTooltip;
                  } else {
                    reminderTooltip = 'Envoyer WhatsApp';
                  }
                  final patient = (d['patientNom'] ?? 'Patient').toString();
                  final doctor = (d['doctorName'] ?? d['doctorId'] ?? '')
                      .toString();
                  final motif = (d['motif'] ?? '').toString();
                  final etape = EtapeParcours.fromRendezVous(d);
                  final formatted = dt != null
                      ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                      : 'Date a definir';

                  return FluentCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _DashboardAssistantState.primary
                              .withOpacity(0.12),
                          child: const Icon(
                            Icons.event_available,
                            color: _DashboardAssistantState.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patient,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Medecin : $doctor',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              if (motif.toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Motif : $motif',
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Ou en est ce rendez-vous. Il n'y avait qu'un
                            // « Passe » deduit de l'heure : un rendez-vous
                            // honore, un patient absent et un patient encore
                            // en salle s'affichaient tous pareil.
                            EtapeChip(etape: etape, compact: true),
                            // « Passe » ne se justifie que si l'heure est
                            // depassee ET que personne n'a rien fait.
                            if (isPast && etape.estOuverte) ...[
                              const SizedBox(height: 4),
                              const Chip(
                                label: Text('En retard'),
                                backgroundColor: Color(0xFFFFE4E6),
                              ),
                            ],
                            if (reminderSent) ...[
                              const SizedBox(height: 4),
                              const Chip(
                                label: Text('Rappel envoye'),
                                backgroundColor: Color(0xFFE0F2FE),
                              ),
                            ],
                            const SizedBox(height: 6),
                            // L'action du jour, mise en avant : c'est celle
                            // que l'assistant fait des dizaines de fois.
                            if (etape == EtapeParcours.planifie ||
                                etape == EtapeParcours.confirme)
                              FluentButton(
                                label: _enCoursArrivee.contains(rdvId)
                                    ? 'Placement...'
                                    : 'Patient arrive',
                                icon: Icons.login_rounded,
                                compact: true,
                                onPressed: _enCoursArrivee.contains(rdvId)
                                    ? null
                                    : () => _marquerArrive(context, rdvId, d),
                              ),
                            if (etape == EtapeParcours.arrive ||
                                etape == EtapeParcours.enCours)
                              Text(
                                'En salle',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: etape.couleur(scheme),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              children: [
                                // L'etape « confirme » existait dans le
                                // modele sans qu'aucun bouton ne la pose :
                                // le code la lisait, la vraie vie ne
                                // l'atteignait jamais.
                                if (etape == EtapeParcours.planifie)
                                  IconButton(
                                    tooltip: 'Confirmer le rendez-vous',
                                    icon: Icon(
                                      Icons.event_available_outlined,
                                      size: 18,
                                      color: EtapeParcours.confirme.couleur(
                                        scheme,
                                      ),
                                    ),
                                    onPressed: () => _changerEtapeRdv(
                                      context,
                                      rdvId,
                                      d,
                                      EtapeParcours.confirme,
                                    ),
                                  ),
                                if (etape.suivantes.contains(
                                  EtapeParcours.absent,
                                ))
                                  IconButton(
                                    tooltip: 'Noter absent',
                                    icon: Icon(
                                      Icons.person_off_outlined,
                                      size: 18,
                                      color: EtapeParcours.absent.couleur(
                                        scheme,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _noterAbsent(context, rdvId, d),
                                  ),
                                IconButton(
                                  tooltip: reminderTooltip,
                                  icon: Icon(
                                    Icons.message,
                                    size: 18,
                                    color: canSendReminder
                                        ? const Color(0xFF16A34A)
                                        : textFaint,
                                  ),
                                  onPressed: () {
                                    if (canSendReminder) {
                                      _sendWhatsappReminder(
                                        context,
                                        rdvId,
                                        d,
                                        dt!,
                                      );
                                      return;
                                    }
                                    if (reminderInfo != null) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(reminderInfo)),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _editRdv(context, rdvId, d),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                  onPressed: () =>
                                      _deleteRdv(context, rdvId, d),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
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
  final WaitingService waitingService;

  const _RendezVousTab({
    required this.parentUid,
    required this.profileId,
    required this.waitingService,
  });

  @override
  State<_RendezVousTab> createState() => _RendezVousTabState();
}

class _RendezVousTabState extends State<_RendezVousTab> {
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SalleAttenteBoard(
      profileId: widget.profileId,
      headerActionsBuilder: (context, waiting, inConsultation) {
        final openEntries = [...waiting, ...inConsultation];
        if (openEntries.isEmpty) return const [];
        return [
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: () => _cloturerJournee(context, openEntries),
            icon: const Icon(Icons.lock_clock),
            label: const Text('Reinitialiser journee'),
          ),
        ];
      },
      actions: SalleAttenteRowActions(
        onConsulter: (ctx, entry) => _startConsultation(ctx, entry),
        // Clôturer une consultation fixe le prix en même temps (c'est le
        // médecin qui fait les deux à la fois, depuis son écran de
        // consultation guidée) — l'assistant n'a plus de bouton "Terminer"
        // qui clôturerait sans jamais demander de prix.
        onVersement: (ctx, entry) => _ouvrirPaiement(ctx, entry),
        onOuvrirDossier: (ctx, entry) => _openPatient(ctx, entry),
      ),
    );
  }

  Future<void> _cloturerJournee(
    BuildContext context,
    List<Map<String, dynamic>> openEntries,
  ) async {
    if (openEntries.isEmpty) return;
    final futures = <Future>[];
    for (final d in openEntries) {
      final data = d;
      futures.add(
        widget.waitingService.closeEntryForAll(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingId: d['id'].toString(),
          doctorId: (data['doctorId'] ?? '').toString(),
          assistantId: (data['assistantId'] ?? '').toString(),
          patientId: (data['patientId'] ?? '').toString(),
        ),
      );
    }
    await Future.wait(futures);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Journee reinitialisee')));
    }
  }

  Future<void> _startConsultation(
    BuildContext context,
    Map<String, dynamic> doc,
  ) async {
    final data = doc;
    await widget.waitingService.markInConsultation(
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

  /// Ouvre le paiement dans le parcours d'accueil guide, directement a
  /// l'etape Paiement : un seul composant de paiement dans toute l'app,
  /// au lieu du dialog "Versement" et de la snackbar de recu d'avant.
  Future<void> _ouvrirPaiement(
    BuildContext context,
    Map<String, dynamic> entry,
  ) async {
    final patientId = (entry['patientId'] ?? '').toString();
    if (patientId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient introuvable')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccueilPatientPage(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingService: widget.waitingService,
          etapeInitiale: 2,
          patientId: patientId,
        ),
      ),
    );
  }
}

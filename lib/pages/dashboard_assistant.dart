import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'add_patient_form.dart';
import 'patient_details_page.dart';
import 'profile_selector_page.dart';
import 'stats_page.dart';
import '../services/firestore_service.dart';
import '../services/rendezvous_repository.dart';
import '../services/stats_service.dart';
import '../services/waiting_service.dart';
import '../ui/app_shell.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../widgets/daily_versements_card.dart';

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) {
    final raw = v.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }
  return null;
}

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
        content: Column(
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

    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId)
        .collection('purchases')
        .doc();

    await doc.set({
      'produit': produitCtrl.text.trim(),
      'fournisseur': fournisseurCtrl.text.trim(),
      'montant': montant,
      'createdAt': Timestamp.now(),
      'dayKey': _todayKey(),
      'parentUid': widget.parentUid,
      'profileId': widget.profileId,
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

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime == null) return;

    final dt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    String reminderTemplate = '';
    try {
      final templateSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes')
          .doc(widget.profileId)
          .get();
      reminderTemplate = (templateSnap.data()?['whatsappTemplate'] ?? '')
          .toString()
          .trim();
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
      'datetime': Timestamp.fromDate(dt),
      'createdAt': FieldValue.serverTimestamp(),
      'parentUid': widget.parentUid,
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

  Future<void> _clearPastRdv() async {
    final now = DateTime.now();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final snap = await base
        .doc(widget.profileId)
        .collection('rendezvous')
        .where('datetime', isLessThan: Timestamp.fromDate(now))
        .get();
    if (snap.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun rendez-vous Passe')),
        );
      }
      return;
    }
    for (final d in snap.docs) {
      final data = d.data();
      final doctorId = (data['doctorId'] ?? '').toString();
      final rdvId = d.id;
      final deletes = <Future>[];
      deletes.add(d.reference.delete());
      if (doctorId.isNotEmpty) {
        deletes.add(
          base
              .doc(doctorId)
              .collection('rendezvous')
              .doc(rdvId)
              .delete()
              .catchError((_) {}),
        );
      }
      deletes.add(
        base
            .doc('medecin_principal')
            .collection('rendezvous')
            .doc(rdvId)
            .delete()
            .catchError((_) {}),
      );
      await Future.wait(deletes);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${snap.docs.length} RDV Passes supprimes')),
      );
    }
  }

  Future<void> _editMyProfile(BuildContext context) async {
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId);

    final snap = await docRef.get();
    final currentName = (snap.data()?['name'] ?? _assistantName ?? '')
        .toString();
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

    await docRef.set({'name': newName}, SetOptions(merge: true));
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
          content: Column(
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
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .set({
          'motifsPredefinis': toSave,
          'motifPrototypes': protoMapToSave,
        }, SetOptions(merge: true));

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
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid);
      final parentSnap = await userRef.get();
      if (!mounted) return;

      List<String> fetchedMotifs = [];
      Map<String, List<String>> fetchedProtos = {};

      final parentData = parentSnap.data() ?? {};
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
          _ensureVitals(list);
          return MapEntry(k.toString(), list);
        });
      }

      if (fetchedMotifs.isEmpty || fetchedProtos.isEmpty) {
        final profileSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.parentUid)
            .collection('comptes')
            .doc(widget.profileId)
            .get();
        final profileData = profileSnap.data() ?? {};
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
              _ensureVitals(list);
              return MapEntry(k.toString(), list);
            });
          }
        }
        if (fetchedMotifs.isNotEmpty || fetchedProtos.isNotEmpty) {
          await userRef.set({
            if (fetchedMotifs.isNotEmpty) 'motifsPredefinis': fetchedMotifs,
            if (fetchedProtos.isNotEmpty) 'motifPrototypes': fetchedProtos,
          }, SetOptions(merge: true));
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
          content: Column(
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
    final fields = ctrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    _ensureVitals(fields);
    _motifPrototypes[selected] = fields;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .set({'motifPrototypes': _motifPrototypes}, SetOptions(merge: true));
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prototype enregistre')));
    }
  }

  void _ensureVitals(List<String> list) {
    bool has(String name) =>
        list.any((e) => e.toLowerCase() == name.toLowerCase());
    void addIfMissing(String name) {
      if (!has(name)) list.insert(0, name);
    }

    addIfMissing('IMC');
    addIfMissing('Taille');
    addIfMissing('Poids');
  }

  @override
  Widget build(BuildContext context) {
    Widget tabContent;
    if (navIndex == 0) {
      tabContent = Column(
        children: [
          DailyVersementsCard(
            parentUid: widget.parentUid,
            profileId: widget.profileId,
          ),
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
          label: 'Nouveau patient',
          icon: Icons.person_add_alt_1,
          onPressed: () {
            final motifs = _motifsForPatientsTab.isNotEmpty
                ? _motifsForPatientsTab
                : _motifs;
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddPatientForm(
                  parentUid: widget.parentUid,
                  assistantProfileId: widget.profileId,
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
            await FirebaseAuth.instance.signOut();
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

  bool _createdToday(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return d.year == DateTime.now().year &&
          d.month == DateTime.now().month &&
          d.day == DateTime.now().day;
    }
    if (value is DateTime) {
      return value.year == DateTime.now().year &&
          value.month == DateTime.now().month &&
          value.day == DateTime.now().day;
    }
    return false;
  }

  bool _docBelongsToParent(DocumentSnapshot doc) {
    final pathParts = doc.reference.path.split('/');
    if (pathParts.length > 2 && pathParts[0] == 'users') {
      if (pathParts[1] == parentUid) return true;
    }
    final data = doc.data() as Map<String, dynamic>?;
    if (data != null && (data['parentUid'] ?? '') == parentUid) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final stream = FirebaseFirestore.instance
        .collectionGroup('purchases')
        .where('parentUid', isEqualTo: parentUid)
        .where('dayKey', isEqualTo: _dayKey())
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        double total = 0;
        int count = 0;
        if (snapshot.hasData) {
          for (final d in snapshot.data!.docs) {
            if (!_docBelongsToParent(d)) continue;
            final data = d.data() as Map<String, dynamic>;
            final day = (data['dayKey'] ?? '').toString();
            final created = data['createdAt'];
            final isToday = day == _dayKey() || _createdToday(created);
            if (!isToday) continue;
            total += _toDouble(data['montant']);
            count += 1;
          }
        }
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
          width: 460,
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
    Query purchasesQuery;
    if (widget.profileId == null) {
      purchasesQuery = FirebaseFirestore.instance
          .collectionGroup('purchases')
          .where('parentUid', isEqualTo: widget.parentUid);
    } else {
      purchasesQuery = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes')
          .doc(widget.profileId)
          .collection('purchases');
    }
    if (widget.dayKey != null) {
      purchasesQuery = purchasesQuery.where('dayKey', isEqualTo: widget.dayKey);
    }
    purchasesQuery = purchasesQuery
        .orderBy('createdAt', descending: true)
        .limit(_limit);

    return StreamBuilder<QuerySnapshot>(
      stream: purchasesQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Erreur de chargement des achats'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun achat'));
        }
        final canLoadMore = docs.length >= _limit;
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
            final data = docs[index].data() as Map<String, dynamic>;
            final produit = (data['produit'] ?? 'Produit').toString();
            final fournisseur = (data['fournisseur'] ?? '').toString();
            final montant = _toDouble(data['montant']);
            final created = data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : null;
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: statsStream,
      builder: (context, statsSnap) {
        final data = statsSnap.data?.data();
        if (data != null && statsSnap.data!.exists) {
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
  String _query = '';
  final WaitingService _waitingService = WaitingService();
  final ScrollController _patientsScrollCtrl = ScrollController();
  final Set<String> _deletingPatientIds = <String>{};
  final Set<String> _addingWaitingPatientIds = <String>{};
  static const int _pageSize = 60;
  int _limit = _pageSize;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _patientsScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _ajouterEnSalleAttente(
    BuildContext context,
    Map<String, dynamic> patient,
    String patientId,
  ) async {
    if (_addingWaitingPatientIds.contains(patientId)) return;
    final doctorId = (patient['doctorId'] ?? '').toString();
    if (doctorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun Medecin assigne a ce patient')),
      );
      return;
    }
    setState(() => _addingWaitingPatientIds.add(patientId));
    try {
      final seancesTotal = int.tryParse(
        (patient['nombreSeances'] ?? '').toString(),
      );
      final seancesDone =
          int.tryParse((patient['seancesEffectuees'] ?? '0').toString()) ?? 0;
      final added = await _waitingService.addToWaiting(
        parentUid: widget.parentUid,
        assistantId: widget.profileId,
        assistantName: widget.assistantName,
        doctorId: doctorId,
        doctorName: (patient['assignedMedecinName'] ?? '').toString(),
        patientId: patientId,
        patientNom: patient['nom'] ?? '',
        patientPrenom: patient['prenom'] ?? '',
        nombreSeances: seancesTotal,
        seancesEffectuees: seancesDone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Patient ajoute en salle d\'attente'
                : 'Patient deja en salle d\'attente',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de l\'ajout en salle d\'attente'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _addingWaitingPatientIds.remove(patientId));
      }
    }
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
        title: const Text('Supprimer patient'),
        content: const Text(
          'Voulez-vous supprimer ce patient et ses donnees associees ?',
        ),
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

    setState(() => _deletingPatientIds.add(patientId));

    try {
      final doctorId = (patient['doctorId'] ?? '').toString();
      final assistantId = (patient['assistantId'] ?? '').toString();
      final profileIds = <String>{
        widget.profileId,
        'medecin_principal',
        if (doctorId.isNotEmpty) doctorId,
        if (assistantId.isNotEmpty) assistantId,
      };

      final base = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes');

      // Suppression immediate des docs patient pour que la liste se mette a jour vite.
      final batch = FirebaseFirestore.instance.batch();
      for (final profileId in profileIds) {
        batch.delete(base.doc(profileId).collection('patients').doc(patientId));
      }
      await batch.commit().timeout(const Duration(seconds: 15));

      // Nettoyage secondaire en arriere-plan.
      unawaited(
        _cleanupPatientRelatedDocs(
          patientId: patientId,
          profileIds: profileIds,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient supprime (nettoyage en cours)'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la suppression du patient'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingPatientIds.remove(patientId));
      }
    }
  }

  Future<void> _cleanupPatientRelatedDocs({
    required String patientId,
    required Set<String> profileIds,
  }) async {
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');

    for (final profileId in profileIds) {
      final profileRef = base.doc(profileId);
      final patientRef = profileRef.collection('patients').doc(patientId);

      try {
        final formsSnap = await patientRef.collection('forms').get();
        if (formsSnap.docs.isNotEmpty) {
          await Future.wait(
            formsSnap.docs.map((d) => d.reference.delete().catchError((_) {})),
          );
        }
      } catch (_) {}

      try {
        final rdvSnap = await profileRef
            .collection('rendezvous')
            .where('patientId', isEqualTo: patientId)
            .get();
        if (rdvSnap.docs.isNotEmpty) {
          await Future.wait(
            rdvSnap.docs.map((d) => d.reference.delete().catchError((_) {})),
          );
        }
      } catch (_) {}

      try {
        final waitingSnap = await profileRef
            .collection('salle_attente')
            .where('patientId', isEqualTo: patientId)
            .get();
        if (waitingSnap.docs.isNotEmpty) {
          await Future.wait(
            waitingSnap.docs.map(
              (d) => d.reference.delete().catchError((_) {}),
            ),
          );
        }
      } catch (_) {}
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

    final stream = widget.service.patientsStream(
      parentUid: widget.parentUid,
      profileId: widget.profileId,
      orderByCreated: true,
      limit: _limit,
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
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
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
                      Icon(Icons.tune, size: 16, color: _PatientsTab.primary),
                      SizedBox(width: 6),
                      Text(
                        'Filtres',
                        style: TextStyle(
                          color: _PatientsTab.primary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Erreur de chargement des patients'),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final patients = snapshot.data!.docs;
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
                final data = p.data() as Map<String, dynamic>;
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
                    final data = patient.data() as Map<String, dynamic>;

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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: secondary.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                  icon: const Icon(Icons.article_outlined),
                                  color: primary,
                                  tooltip: 'Dossier patient',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PatientDetailsPage(
                                          patientId: patient.id,
                                          patientName: nom,
                                          parentUid: widget.parentUid,
                                          ownerProfileId: widget.profileId,
                                          canAddForm: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.meeting_room_outlined),
                                  color: Colors.orange.shade700,
                                  onPressed:
                                      _addingWaitingPatientIds.contains(
                                        patient.id,
                                      )
                                      ? null
                                      : () => _ajouterEnSalleAttente(
                                          context,
                                          data,
                                          patient.id,
                                        ),
                                  tooltip: 'Mettre en salle d\'attente',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.event_available),
                                  color: secondary,
                                  onPressed: () =>
                                      widget.onPlanifier(data, patient.id),
                                  tooltip: 'Planifier un rendez-vous',
                                ),
                                if (_deletingPatientIds.contains(patient.id))
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
                                    icon: const Icon(Icons.delete_outline),
                                    color: scheme.error,
                                    onPressed: () => _deletePatient(
                                      context,
                                      patient.id,
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
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes')
          .doc(widget.profileId);
      final snap = await ref.get();
      final template = (snap.data()?['whatsappTemplate'] ?? '').toString();
      if (mounted) {
        setState(() => _whatsappTemplate = template);
      }
    } catch (_) {
      // keep default
    }
  }

  Future<void> _saveWhatsappTemplate(String template) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId);
    await ref.set({
      'whatsappTemplate': template,
      'whatsappTemplateUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
        content: Column(
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

  Future<void> _markReminderSent(
    String rdvId,
    Map<String, dynamic> data,
  ) async {
    final doctorId = (data['doctorId'] ?? '').toString();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final update = {
      'reminderSentAt': FieldValue.serverTimestamp(),
      'reminderChannel': 'whatsapp',
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      base.doc(widget.profileId).collection('rendezvous').doc(rdvId),
      update,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty) {
      batch.set(
        base.doc(doctorId).collection('rendezvous').doc(rdvId),
        update,
        SetOptions(merge: true),
      );
    }
    batch.set(
      base.doc('medecin_principal').collection('rendezvous').doc(rdvId),
      update,
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> _cachePatientTel(
    String rdvId,
    String tel,
    Map<String, dynamic> data,
  ) async {
    final doctorId = (data['doctorId'] ?? '').toString();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final update = {
      'patientTel': tel,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      base.doc(widget.profileId).collection('rendezvous').doc(rdvId),
      update,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty) {
      batch.set(
        base.doc(doctorId).collection('rendezvous').doc(rdvId),
        update,
        SetOptions(merge: true),
      );
    }
    batch.set(
      base.doc('medecin_principal').collection('rendezvous').doc(rdvId),
      update,
      SetOptions(merge: true),
    );
    await batch.commit();
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
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.parentUid)
            .collection('comptes')
            .doc(widget.profileId)
            .collection('patients')
            .doc(patientId);
        final snap = await ref.get();
        rawTel = (snap.data()?['tel'] ?? '').toString().trim();
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

  Future<void> _updateRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
    DateTime newDateTime,
    String motif,
  ) async {
    final doctorId = (data['doctorId'] ?? '').toString();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final updateData = {
      'datetime': Timestamp.fromDate(newDateTime),
      'motif': motif,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      base.doc(widget.profileId).collection('rendezvous').doc(rdvId),
      updateData,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty) {
      batch.set(
        base.doc(doctorId).collection('rendezvous').doc(rdvId),
        updateData,
        SetOptions(merge: true),
      );
    }
    batch.set(
      base.doc('medecin_principal').collection('rendezvous').doc(rdvId),
      updateData,
      SetOptions(merge: true),
    );
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rendez-vous mis a jour')));
    }
  }

  Future<void> _editRdv(
    BuildContext context,
    String rdvId,
    Map<String, dynamic> data,
  ) async {
    final currentDt = data['datetime'] is Timestamp
        ? (data['datetime'] as Timestamp).toDate()
        : DateTime.now();
    DateTime selectedDate = DateTime(
      currentDt.year,
      currentDt.month,
      currentDt.day,
    );
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(currentDt);
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: motifCtrl,
                  decoration: const InputDecoration(labelText: 'Motif'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(dateLabel),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 5),
                            ),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(timeLabel),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() => selectedTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
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
    await _updateRdv(context, rdvId, data, newDateTime, motif);
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

    final doctorId = (data['doctorId'] ?? '').toString();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(
      base.doc(widget.profileId).collection('rendezvous').doc(rdvId),
    );
    if (doctorId.isNotEmpty) {
      batch.delete(base.doc(doctorId).collection('rendezvous').doc(rdvId));
    }
    batch.delete(
      base.doc('medecin_principal').collection('rendezvous').doc(rdvId),
    );
    await batch.commit();

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
    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId)
        .collection('rendezvous')
        .orderBy('datetime', descending: false);
    if (!_showAll) {
      query = query.where(
        'datetime',
        isGreaterThanOrEqualTo: Timestamp.fromDate(minDate),
      );
    }
    query = query.limit(_limit);

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
          child: StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                  child: Text('Erreur de chargement des RDV'),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Aucun Rendez-vous planifie'));
              }
              final canLoadMore = docs.length >= _limit;
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
                  final d = doc.data() as Map<String, dynamic>;
                  final rdvId = doc.id;
                  final dt = d['datetime'] is Timestamp
                      ? (d['datetime'] as Timestamp).toDate()
                      : null;
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
                            if (isPast)
                              const Chip(
                                label: Text('Passe'),
                                backgroundColor: Color(0xFFFFE4E6),
                              ),
                            if (reminderSent) ...[
                              const SizedBox(height: 4),
                              const Chip(
                                label: Text('Rappel envoye'),
                                backgroundColor: Color(0xFFE0F2FE),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              children: [
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
  static const int _pageSize = 120;
  static const int _lookbackDays = 7;
  int _limit = _pageSize;
  bool _showAll = false;
  final Set<String> _closingWaitingIds = <String>{};

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedIcon = scheme.onSurface.withOpacity(0.65);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final recentCutoff = startOfDay.subtract(
      const Duration(days: _lookbackDays),
    );
    Query<Map<String, dynamic>> ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes')
        .doc(widget.profileId)
        .collection('salle_attente')
        .orderBy('createdAt', descending: true);
    if (!_showAll) {
      ref = ref.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(recentCutoff),
      );
    }
    ref = ref.limit(_limit);
    final stream = ref.snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erreur de chargement de la salle d\'attente'),
          );
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
                closedTs.isAfter(
                  startOfDay.subtract(const Duration(milliseconds: 1)),
                ) &&
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

        final openEntries = [...waiting, ...inConsultation];
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
                  if (openEntries.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => _cloturerJournee(context, openEntries),
                      icon: const Icon(Icons.lock_clock),
                      label: const Text('Reinitialiser journee'),
                    ),
                  ],
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('Aucun patient en consultation'),
                    )
                  else
                    ...List.generate(inConsultation.length, (index) {
                      final data =
                          inConsultation[index].data() as Map<String, dynamic>;
                      final patient = (data['patientNom'] ?? 'Patient')
                          .toString();
                      final doctor =
                          (data['doctorName'] ?? data['doctorId'] ?? '')
                              .toString();
                      final assistant =
                          (data['assistantName'] ?? data['assistantId'] ?? '')
                              .toString();
                      final seancesTotal = _toInt(data['nombreSeances']);
                      final seancesDone = _toInt(data['seancesEffectuees']);
                      final started = data['inConsultationAt'] is Timestamp
                          ? (data['inConsultationAt'] as Timestamp).toDate()
                          : null;
                      final startStr = started != null
                          ? '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}'
                          : '';
                      return FluentCard(
                        margin: const EdgeInsets.only(
                          bottom: 12,
                          left: 12,
                          right: 12,
                        ),
                        padding: const EdgeInsets.all(14),
                        child: ListTile(
                          leading: const Icon(
                            Icons.local_hospital,
                            color: _DashboardAssistantState.primary,
                          ),
                          title: Text(patient),
                          subtitle: Text(
                            [
                              if (doctor.isNotEmpty) 'Medecin: $doctor',
                              if (assistant.isNotEmpty) 'Assistant: $assistant',
                              if (seancesDone != null || seancesTotal != null)
                                'Seances: ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                              'En consultation depuis $startStr',
                            ].join('\n'),
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _addVersement(
                                  context,
                                  inConsultation[index],
                                ),
                                child: const Text('Versement'),
                              ),
                              ElevatedButton(
                                onPressed:
                                    _closingWaitingIds.contains(
                                      inConsultation[index].id,
                                    )
                                    ? null
                                    : () => _cloturerPatient(
                                        context,
                                        inConsultation[index],
                                      ),
                                child:
                                    _closingWaitingIds.contains(
                                      inConsultation[index].id,
                                    )
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Terminer...'),
                                        ],
                                      )
                                    : const Text('Terminer'),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('Aucun patient en attente'),
                    )
                  else
                    ListView.builder(
                      itemCount: waiting.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final data =
                            waiting[index].data() as Map<String, dynamic>;
                        final patient = (data['patientNom'] ?? 'Patient')
                            .toString();
                        final doctor =
                            (data['doctorName'] ?? data['doctorId'] ?? '')
                                .toString();
                        final assistant =
                            (data['assistantName'] ?? data['assistantId'] ?? '')
                                .toString();
                        final seancesTotal = _toInt(data['nombreSeances']);
                        final seancesDone = _toInt(data['seancesEffectuees']);
                        final created = data['createdAt'] is Timestamp
                            ? (data['createdAt'] as Timestamp).toDate()
                            : null;
                        final createdStr = created != null
                            ? '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                            : '';
                        return FluentCard(
                          margin: const EdgeInsets.only(
                            bottom: 12,
                            left: 12,
                            right: 12,
                          ),
                          padding: const EdgeInsets.all(14),
                          child: ListTile(
                            leading: const Icon(
                              Icons.meeting_room_outlined,
                              color: _DashboardAssistantState.primary,
                            ),
                            title: Text(patient),
                            subtitle: Text(
                              [
                                if (doctor.isNotEmpty) 'Medecin: $doctor',
                                if (assistant.isNotEmpty)
                                  'Assistant: $assistant',
                                if (seancesDone != null || seancesTotal != null)
                                  'Seances: ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
                                'Arrivee: $createdStr',
                              ].join('\n'),
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _addVersement(context, waiting[index]),
                                  child: const Text('Versement'),
                                ),
                                OutlinedButton(
                                  onPressed: () => _startConsultation(
                                    context,
                                    waiting[index],
                                  ),
                                  child: const Text('En consultation'),
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
                              final data =
                                  historyToday[index].data()
                                      as Map<String, dynamic>;
                              final patient = (data['patientNom'] ?? 'Patient')
                                  .toString();
                              final doctor =
                                  (data['doctorName'] ?? data['doctorId'] ?? '')
                                      .toString();
                              final assistant =
                                  (data['assistantName'] ??
                                          data['assistantId'] ??
                                          '')
                                      .toString();
                              final seancesTotal = _toInt(
                                data['nombreSeances'],
                              );
                              final seancesDone = _toInt(
                                data['seancesEffectuees'],
                              );
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
                                    if (assistant.isNotEmpty)
                                      'Assistant: $assistant',
                                    if (seancesDone != null ||
                                        seancesTotal != null)
                                      'Seances: ${seancesDone ?? 0}/${seancesTotal ?? '-'}',
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

  Future<void> _cloturerJournee(
    BuildContext context,
    List<QueryDocumentSnapshot> openEntries,
  ) async {
    if (openEntries.isEmpty) return;
    final futures = <Future>[];
    for (final d in openEntries) {
      final data = d.data() as Map<String, dynamic>;
      futures.add(
        widget.waitingService.closeEntryForAll(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingId: d.id,
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
    QueryDocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    await widget.waitingService.markInConsultation(
      parentUid: widget.parentUid,
      profileId: widget.profileId,
      waitingId: doc.id,
      doctorId: (data['doctorId'] ?? '').toString(),
      assistantId: (data['assistantId'] ?? '').toString(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient en consultation')));
    }
  }

  Future<void> _addVersement(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final patientId = (data['patientId'] ?? '').toString();
    if (patientId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Patient introuvable')));
      }
      return;
    }

    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final patientRef = base
        .doc(widget.profileId)
        .collection('patients')
        .doc(patientId);
    final patientSnap = await patientRef.get();
    final patientData = patientSnap.data();
    if (patientData == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier patient non trouve')),
        );
      }
      return;
    }

    final prix = double.tryParse((patientData['prix'] ?? '').toString());
    final currentTotal =
        double.tryParse((patientData['totalVersements'] ?? '0').toString()) ??
        0;

    final montantCtrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ajouter un versement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prix != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Prix total: ${prix.toStringAsFixed(2)} DA',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            Text('Deja paye: ${currentTotal.toStringAsFixed(2)} DA'),
            const SizedBox(height: 8),
            TextField(
              controller: montantCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant',
                prefixText: 'DA ',
              ),
            ),
          ],
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

    final montantText = montantCtrl.text.replaceAll(',', '.').trim();
    final montant = double.tryParse(montantText);
    if (montant == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Montant invalide')));
      }
      return;
    }

    final newTotal = currentTotal + montant;
    final newEntry = {
      'montant': montant,
      'createdAt': Timestamp.now(),
      'dayKey': _todayKey(),
      'auteurProfileId': widget.profileId,
    };

    try {
      final doctorId = (patientData['doctorId'] ?? '').toString();
      final doctorRef = doctorId.isNotEmpty
          ? base.doc(doctorId).collection('patients').doc(patientId)
          : null;

      final batch = FirebaseFirestore.instance.batch();
      batch.set(patientRef, {
        'totalVersements': newTotal,
        'versements': FieldValue.arrayUnion([newEntry]),
        'parentUid': widget.parentUid,
      }, SetOptions(merge: true));
      if (doctorRef != null) {
        batch.set(doctorRef, {
          'totalVersements': newTotal,
          'versements': FieldValue.arrayUnion([newEntry]),
          'parentUid': widget.parentUid,
        }, SetOptions(merge: true));
      }
      await batch.commit();
      await StatsService().addVersement(
        parentUid: widget.parentUid,
        montant: montant,
        doctorId: doctorId,
        doctorName: (patientData['assignedMedecinName'] ??
                patientData['doctorName'] ??
                '')
            .toString(),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Versement ajoute')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'ajout du versement')),
        );
      }
    }
  }

  Future<void> _cloturerPatient(
    BuildContext context,
    QueryDocumentSnapshot doc,
  ) async {
    if (_closingWaitingIds.contains(doc.id)) return;
    setState(() => _closingWaitingIds.add(doc.id));
    final data = doc.data() as Map<String, dynamic>;
    try {
      await _incrementSeancePatient(data);
      final updatedDone =
          ((data['seancesEffectuees'] as num?)?.toInt() ?? 0) + 1;
      await widget.waitingService.closeEntryForAll(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        waitingId: doc.id,
        doctorId: (data['doctorId'] ?? '').toString(),
        assistantId: (data['assistantId'] ?? '').toString(),
        patientId: (data['patientId'] ?? '').toString(),
        seancesEffectuees: updatedDone,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Patient marque recu')));
      }
    } finally {
      if (mounted) {
        setState(() => _closingWaitingIds.remove(doc.id));
      }
    }
  }

  Future<void> _incrementSeancePatient(Map<String, dynamic> data) async {
    final patientId = (data['patientId'] ?? '').toString();
    if (patientId.isEmpty) return;
    final doctorId = (data['doctorId'] ?? '').toString();
    final assistantId = (data['assistantId'] ?? '').toString();
    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentUid)
        .collection('comptes');
    final updates = {'seancesEffectuees': FieldValue.increment(1)};
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      base.doc(widget.profileId).collection('patients').doc(patientId),
      updates,
      SetOptions(merge: true),
    );
    if (doctorId.isNotEmpty && doctorId != widget.profileId) {
      batch.set(
        base.doc(doctorId).collection('patients').doc(patientId),
        updates,
        SetOptions(merge: true),
      );
    }
    if (assistantId.isNotEmpty &&
        assistantId != widget.profileId &&
        assistantId != doctorId) {
      batch.set(
        base.doc(assistantId).collection('patients').doc(patientId),
        updates,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

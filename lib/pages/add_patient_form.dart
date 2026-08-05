import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'medecins_cards.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_button.dart';
import '../services/waiting_service.dart';

class AddPatientForm extends StatefulWidget {
  final String parentUid;
  final String assistantProfileId;
  final String assistantName;
  final List<String> motifsPredefinis;

  AddPatientForm({
    required this.parentUid,
    required this.assistantProfileId,
    this.assistantName = '',
    this.motifsPredefinis = const [],
  });

  @override
  _AddPatientFormState createState() => _AddPatientFormState();
}

class _AddPatientFormState extends State<AddPatientForm> {
  final nom = TextEditingController();
  final prenom = TextEditingController();
  final age = TextEditingController();
  final tel = TextEditingController();
  final email = TextEditingController();
  final formulaireInitial = TextEditingController();
  String origine = '';
  final Set<String> motifs = {};
  final TextEditingController motifAutre = TextEditingController();
  late List<String> motifsOptions;
  bool _isSaving = false;

  String? selectedDoctorId;
  Map<String, dynamic>? selectedDoctorData;

  String generateId() => FirebaseFirestore.instance.collection('tmp').doc().id;

  @override
  void initState() {
    super.initState();
    motifsOptions = widget.motifsPredefinis.isNotEmpty
        ? [...widget.motifsPredefinis]
        : ['perte', 'prise'];
    _loadMotifsFromProfile();
  }

  Future<void> saveForm() async {
    if (_isSaving) return;
    if (selectedDoctorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Choisis un medecin (touche une carte)')),
      );
      return;
    }
    if (motifs.isEmpty && motifAutre.text.trim().isNotEmpty) {
      motifs.add('autre:${motifAutre.text.trim()}');
    }
    if (nom.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nom requis')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final patientId = generateId();
      final data = {
        'nom': nom.text.trim(),
        'prenom': prenom.text.trim(),
        'age': age.text.trim(),
        'tel': tel.text.trim(),
        'email': email.text.trim(),
        'origine': origine,
        'motifs': motifs.toList(),
        'motif': motifs.isEmpty ? '' : motifs.join(', '),
        'doctorId': selectedDoctorId,
        'assistantId': widget.assistantProfileId,
        'assistantName': widget.assistantName,
        'assignedMedecinName': selectedDoctorData?['name'] ?? '',
        'createdByAssistantProfileId': widget.assistantProfileId,
        'parentUid': widget.parentUid,
        'profileId': widget.assistantProfileId,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final doctorRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes')
          .doc(selectedDoctorId)
          .collection('patients')
          .doc(patientId);
      final assistantRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes')
          .doc(widget.assistantProfileId)
          .collection('patients')
          .doc(patientId);

      // Creation du patient sur le medecin et l'assistant
      await Future.wait([doctorRef.set(data), assistantRef.set(data)]);

      // Ajout en salle d'attente (assistant + medecin + principal)
      try {
        final addedToWaiting = await WaitingService().addToWaiting(
          parentUid: widget.parentUid,
          assistantId: widget.assistantProfileId,
          assistantName: widget.assistantName,
          doctorId: selectedDoctorId!,
          doctorName: data['assignedMedecinName'] ?? '',
          patientId: patientId,
          patientNom: data['nom'] ?? '',
          patientPrenom: data['prenom'] ?? '',
        );
        if (mounted && !addedToWaiting) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Patient deja en salle d\'attente')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Patient cree, mais echec ajout salle d\'attente'),
            ),
          );
        }
      }

      // Enregistrer un formulaire initial (visible medecin et assistant)
      final formContent = formulaireInitial.text.trim().isEmpty
          ? "Dossier initial cree par l'assistant"
          : formulaireInitial.text.trim();
      final initialForm = {
        'type': 'Dossier initial',
        'contenu': formContent,
        'createdAt': FieldValue.serverTimestamp(),
        'auteurProfileId': widget.assistantProfileId,
      };

      await Future.wait([
        doctorRef.collection('forms').add(initialForm),
        assistantRef.collection('forms').add(initialForm),
      ]);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Patient cree et enregistre')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'enregistrement")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    nom.dispose();
    prenom.dispose();
    age.dispose();
    tel.dispose();
    email.dispose();
    formulaireInitial.dispose();
    motifAutre.dispose();
    super.dispose();
  }

  Future<void> _loadMotifsFromProfile() async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid);
      final parentSnap = await userRef.get();
      final rawParent = parentSnap.data()?['motifsPredefinis'];
      List<String> fetched = [];
      if (rawParent is List) {
        fetched = rawParent
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (fetched.isEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.parentUid)
            .collection('comptes')
            .doc(widget.assistantProfileId)
            .get();
        final raw = snap.data()?['motifsPredefinis'];
        if (raw is List) {
          fetched = raw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (fetched.isNotEmpty) {
          await userRef.set({
            'motifsPredefinis': fetched,
          }, SetOptions(merge: true));
        }
      }
      if (fetched.isNotEmpty) {
        setState(() {
          motifsOptions = fetched;
        });
      }
    } catch (_) {
      // ignore load failure, keep defaults
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        title: const Text('Ajouter patient'),
        flexibleSpace: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Coordonnees patient',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nom,
                    decoration: const InputDecoration(labelText: 'Nom'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: prenom,
                    decoration: const InputDecoration(labelText: 'Prenom'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: age,
                    decoration: const InputDecoration(labelText: 'Age'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tel,
                    decoration: const InputDecoration(labelText: 'Telephone'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FluentCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Orientation et motif',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  const Text('Comment nous avez-vous connu ?'),
                  RadioListTile(
                    title: const Text('Reseaux sociaux'),
                    value: 'reseaux',
                    dense: true,
                    groupValue: origine,
                    onChanged: (v) => setState(() => origine = v as String),
                  ),
                  RadioListTile(
                    title: const Text('Famille / amis (bouche a oreille)'),
                    value: 'famille_amis_bouche_a_oreille',
                    dense: true,
                    groupValue: origine,
                    onChanged: (v) => setState(() => origine = v as String),
                  ),
                  RadioListTile(
                    title: const Text(
                      'Proximite geographique / passage devant la clinique',
                    ),
                    value: 'proximite_geographique_passage',
                    dense: true,
                    groupValue: origine,
                    onChanged: (v) => setState(() => origine = v as String),
                  ),
                  RadioListTile(
                    title: const Text('Site internet'),
                    value: 'internet',
                    dense: true,
                    groupValue: origine,
                    onChanged: (v) => setState(() => origine = v as String),
                  ),
                  const SizedBox(height: 8),
                  const Text('Motif de consultation'),
                  ...motifsOptions.map(
                    (opt) => CheckboxListTile(
                      title: Text(opt),
                      value: motifs.contains(opt),
                      dense: true,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            motifs.add(opt);
                          } else {
                            motifs.remove(opt);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: motifAutre,
                    decoration: const InputDecoration(
                      labelText: 'Autre motif (optionnel)',
                      hintText: 'Saisir un motif supplementaire',
                    ),
                    onChanged: (v) {
                      setState(() {
                        motifs.removeWhere((m) => m.startsWith('autre:'));
                        if (v.trim().isNotEmpty) {
                          motifs.add('autre:${v.trim()}');
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FluentCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Medecin destinataire',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  MedecinsCards(
                    parentUid: widget.parentUid,
                    onTap: (docId, data) {
                      setState(() {
                        selectedDoctorId = docId;
                        selectedDoctorData = data;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Medecin selectionne: ${data['name'] ?? ''}',
                          ),
                        ),
                      );
                    },
                  ),
                  if (selectedDoctorData != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Medecin selectionne: ${selectedDoctorData!['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            FluentCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Formulaire initial',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: formulaireInitial,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes (visible medecin & assistant)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FluentButton(
                label: 'Enregistrer',
                icon: Icons.save_outlined,
                onPressed: _isSaving ? null : saveForm,
                isLoading: _isSaving,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

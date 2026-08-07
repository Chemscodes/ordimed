import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'patient_details_page.dart';
import '../core/clinical.dart';
import '../core/coerce.dart';
import '../core/format.dart' as fmt;
import '../core/validate.dart' as v;
import '../services/rendezvous_repository.dart';
import '../services/waiting_service.dart';
import '../ui/app_field.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../ui/info_display.dart';
import '../widgets/computed_fields.dart';
import '../widgets/historique_seances.dart';

/// Consultation guidée.
///
/// Le médecin avait deux boutons — « Ouvrir dossier » et « Terminer » — et
/// rien entre les deux. Il tombait sur le dossier patient et devait se
/// souvenir seul de ce qu'il restait à faire.
///
/// Cet écran déroule la consultation : qui est le patient, ce qu'on mesure,
/// ce qu'on conclut, ce qu'on clôture. À chaque étape il voit ce qui est
/// fait et ce qui reste — il ne doit jamais se demander s'il a oublié
/// quelque chose.
class ConsultationPage extends StatefulWidget {
  final String parentUid;
  final String profileId;

  /// Entrée de salle d'attente à clôturer en fin de parcours.
  ///
  /// Nul quand la consultation est lancée depuis le dossier patient : le
  /// patient n'est alors passé par aucune file, il n'y a rien à en sortir.
  final String? waitingId;

  /// Porte patientId, noms et identifiants de profils.
  final Map<String, dynamic> waitingData;

  const ConsultationPage({
    super.key,
    required this.parentUid,
    required this.profileId,
    required this.waitingId,
    required this.waitingData,
  });

  /// Consultation lancée directement depuis un dossier patient.
  ///
  /// La salle d'attente n'est pas le seul chemin vers une consultation : un
  /// patient peut se présenter sans passer par l'assistant. Le dossier porte
  /// déjà les mêmes champs que l'entrée de file, on les réutilise tels quels.
  ConsultationPage.depuisDossier({
    super.key,
    required this.parentUid,
    required this.profileId,
    required String patientId,
    required Map<String, dynamic> patient,
  }) : waitingId = null,
       waitingData = {
         ...patient,
         'patientId': patientId,
         'patientNom': patient['nom'],
         'patientPrenom': patient['prenom'],
       };

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

/// Documents produits pendant la consultation, avec leur type Firestore.
enum _Livrable {
  ordonnance('Ordonnance medecin', 'Ordonnance', Icons.receipt_long_outlined),
  bilan('Demande de bilan', 'Demande de bilan', Icons.biotech_outlined),
  formulaire('Formulaire medecin', 'Formulaire médecin', Icons.assignment_outlined);

  final String typeFirestore;
  final String libelle;
  final IconData icone;

  const _Livrable(this.typeFirestore, this.libelle, this.icone);
}

class _ConsultationPageState extends State<ConsultationPage> {
  final _examenKey = GlobalKey<FormState>();

  final _poidsCtrl = TextEditingController();
  final _tailleCtrl = TextEditingController();
  final _imcCtrl = TextEditingController();
  final _observationsCtrl = TextEditingController();

  int _step = 0;
  bool _cloture = false;
  bool _examenEnregistre = false;

  static const int _dernierStep = 3;
  static const _titres = ['Le patient', 'Examen', 'Conclusion', 'Clôture'];

  String get _patientId => asText(widget.waitingData['patientId']);
  String get _patientNom => asText(widget.waitingData['patientNom']);
  String get _patientPrenom => asText(widget.waitingData['patientPrenom']);

  DocumentReference<Map<String, dynamic>> get _patientRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(widget.parentUid)
      .collection('comptes')
      .doc(widget.profileId)
      .collection('patients')
      .doc(_patientId);

  @override
  void dispose() {
    _poidsCtrl.dispose();
    _tailleCtrl.dispose();
    _imcCtrl.dispose();
    _observationsCtrl.dispose();
    super.dispose();
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  // ---------------------------------------------------------------
  //  Navigation
  // ---------------------------------------------------------------

  Future<void> _suivant() async {
    if (_step == 1) {
      // L'examen est facultatif, mais s'il est rempli il doit être valide :
      // une mesure aberrante enregistrée vaut moins que pas de mesure.
      if (!(_examenKey.currentState?.validate() ?? true)) {
        return _message('Corrigez les mesures signalées');
      }
      await _enregistrerExamen();
    }
    if (_step < _dernierStep) {
      setState(() => _step++);
    } else {
      await _terminer();
    }
  }

  // ---------------------------------------------------------------
  //  Écritures
  // ---------------------------------------------------------------

  /// Enregistre mesures et observations, si quelque chose a été saisi.
  Future<void> _enregistrerExamen() async {
    final poids = asDoubleOrNull(_poidsCtrl.text);
    final taille = asDoubleOrNull(_tailleCtrl.text);
    final notes = _observationsCtrl.text.trim();
    if (poids == null && taille == null && notes.isEmpty) return;

    try {
      final now = FieldValue.serverTimestamp();

      // Les mesures vont sur le dossier patient, pour que la prochaine
      // consultation les retrouve sans fouiller les formulaires.
      final maj = <String, dynamic>{
        if (poids != null) 'poids_actuel': poids,
        if (taille != null) 'taille': taille,
        if (_imcCtrl.text.isNotEmpty) 'imc': _imcCtrl.text,
        'derniereConsultation': now,
      };
      await _patientRef.set(maj, SetOptions(merge: true));

      // Et une trace horodatée dans les documents.
      //
      // Les mesures y sont écrites deux fois, et c'est voulu : en champs
      // typés pour que l'historique les relise sans deviner, et en texte
      // pour les vues qui affichent `contenu` tel quel. Reparser le texte
      // aurait suffi jusqu'au jour où quelqu'un change une virgule.
      await _patientRef.collection('forms').add({
        'type': 'Consultation',
        if (poids != null) 'poids': poids,
        if (taille != null) 'taille': taille,
        if (_imcCtrl.text.isNotEmpty) 'imc': _imcCtrl.text,
        if (notes.isNotEmpty) 'notes': notes,
        'contenu': [
          if (poids != null) 'Poids : ${poids.toStringAsFixed(1)} kg',
          if (taille != null) 'Taille : ${taille.toStringAsFixed(0)} cm',
          if (_imcCtrl.text.isNotEmpty) 'IMC : ${_imcCtrl.text}',
          if (notes.isNotEmpty) '', if (notes.isNotEmpty) notes,
        ].join('\n'),
        'createdAt': now,
        'auteurProfileId': widget.profileId,
        'parentUid': widget.parentUid,
        'patientId': _patientId,
      });

      if (mounted) setState(() => _examenEnregistre = true);
    } catch (_) {
      _message("Échec de l'enregistrement de l'examen");
    }
  }

  /// Clôture : décompte la séance et sort le patient de la file.
  Future<void> _terminer() async {
    if (_cloture) return;
    setState(() => _cloture = true);
    try {
      final doctorId = asText(widget.waitingData['doctorId']);
      final assistantId = asText(widget.waitingData['assistantId']);
      final faites = asInt(widget.waitingData['seancesEffectuees']) + 1;

      // Incrémente la séance sur chaque copie du dossier.
      final base = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentUid)
          .collection('comptes');
      final profils = <String>{
        widget.profileId,
        if (doctorId.isNotEmpty) doctorId,
        if (assistantId.isNotEmpty) assistantId,
      };
      final batch = FirebaseFirestore.instance.batch();
      for (final p in profils) {
        batch.set(
          base.doc(p).collection('patients').doc(_patientId),
          {'seancesEffectuees': FieldValue.increment(1)},
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      // Rien à sortir de la file quand la consultation part du dossier : la
      // séance est décomptée ci-dessus, ce qui suffit à la clôture.
      final waitingId = widget.waitingId;
      if (waitingId != null) {
        await WaitingService().closeEntryForAll(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingId: waitingId,
          doctorId: doctorId,
          assistantId: assistantId,
          patientId: _patientId,
          seancesEffectuees: faites,
        );
      }

      // Referme le rendez-vous d'où vient la visite. Sans ce retour, un
      // rendez-vous honoré restait affiché « à venir » indéfiniment.
      await RendezVousRepository().honorerDepuisVisite(
        parentUid: widget.parentUid,
        rdvId: asTextOrNull(widget.waitingData['rdvId']),
        doctorId: doctorId,
        assistantId: assistantId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      _message('Consultation terminée — $_patientNom $_patientPrenom');
    } catch (_) {
      if (mounted) setState(() => _cloture = false);
      _message('Échec de la clôture');
    }
  }

  Future<void> _ouvrirDossier() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDetailsPage(
          patientId: _patientId,
          patientName: '$_patientNom $_patientPrenom'.trim(),
          parentUid: widget.parentUid,
          ownerProfileId: widget.profileId,
          canAddForm: true,
          canAddDoctorForm: true,
        ),
      ),
    );
    // Au retour, l'étape « Conclusion » se rafraîchit toute seule : elle lit
    // les documents en flux.
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Quitter sans clôturer',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Consultation',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              '$_patientNom $_patientPrenom'.trim(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        flexibleSpace: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient(context),
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            boxShadow: AppTheme.shadow(context),
          ),
        ),
      ),
      body: Column(
        children: [
          _Etapes(step: _step, titres: _titres, onTap: (i) {
            // On peut revenir en arrière librement, mais pas sauter en avant :
            // l'examen doit être passé avant la conclusion.
            if (i <= _step) setState(() => _step = i);
          }),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AnimatedSwitcher(
                    duration: AppTheme.mid,
                    switchInCurve: AppTheme.ease,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: switch (_step) {
                        0 => _etapePatient(),
                        1 => _etapeExamen(),
                        2 => _etapeConclusion(),
                        _ => _etapeCloture(),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          _BarreConsultation(
            step: _step,
            dernier: _dernierStep,
            cloture: _cloture,
            onPrecedent: () => setState(() => _step--),
            onSuivant: _cloture ? null : _suivant,
          ),
        ],
      ),
    );
  }

  // ---- Étape 1 : qui est le patient ----

  Widget _etapePatient() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _patientRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final reglement = Reglement.fromPatient(data);
        final seances = Seances.fromPatient(data);
        final derniere = asDateOrNull(data['derniereConsultation']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InitialsAvatar(
                        nom: _patientNom,
                        prenom: _patientPrenom,
                        size: 52,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_patientNom $_patientPrenom'.trim(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              derniere == null
                                  ? 'Première consultation'
                                  : 'Dernière visite ${fmt.relativeDay(derniere)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  InfoGrid(
                    minColumnWidth: 150,
                    items: [
                      InfoPair(
                        label: 'Motif',
                        value: fmt.capitalize(fmt.humanize(data['motif'])),
                      ),
                      InfoPair(
                        label: 'Âge',
                        value: asIntOrNull(data['age']) == null
                            ? null
                            : '${asInt(data['age'])} ans',
                      ),
                      InfoPair(
                        label: 'Dernier poids',
                        value: asDoubleOrNull(data['poids_actuel']) == null
                            ? null
                            : '${asDouble(data['poids_actuel']).toStringAsFixed(1)} kg',
                      ),
                      InfoPair(
                        label: 'Taille',
                        value: asDoubleOrNull(data['taille']) == null
                            ? null
                            : '${asDouble(data['taille']).toStringAsFixed(0)} cm',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Ce que le médecin doit savoir avant de parler au patient :
            // où en est le forfait, et si le dossier est réglé.
            LayoutBuilder(
              builder: (context, c) {
                final a = SeancesSummary(seances: seances);
                final b = ReglementSummary(reglement: reglement);
                if (c.maxWidth < 520) {
                  return Column(
                    children: [a, const SizedBox(height: 12), b],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // « Qu'est-ce qui s'est passé la dernière fois ? » est la
            // première question du médecin qui s'assoit. Elle n'avait pas
            // de réponse : il fallait fouiller les documents du dossier.
            CarteHistoriqueSeances(
              parentUid: widget.parentUid,
              profileId: widget.profileId,
              patientId: _patientId,
              limite: 3,
              compact: true,
            ),
          ],
        );
      },
    );
  }

  // ---- Étape 2 : examen ----

  Widget _etapeExamen() {
    return FluentCard(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _examenKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TitreConsultation(
              titre: 'Mesures et observations',
              sous: 'Tout est facultatif. Ce qui est saisi est enregistré '
                  'et retrouvé à la prochaine visite.',
              icone: Icons.monitor_heart_outlined,
            ),
            const SizedBox(height: 18),
            AppField.mesure(
              controller: _poidsCtrl,
              label: 'Poids',
              unite: 'kg',
              icon: Icons.monitor_weight_outlined,
              validator: v.poids,
            ),
            const SizedBox(height: 12),
            AppField.mesure(
              controller: _tailleCtrl,
              label: 'Taille',
              unite: 'cm',
              icon: Icons.height,
              validator: v.taille,
            ),
            const SizedBox(height: 12),
            BmiField(
              poidsCtrl: _poidsCtrl,
              tailleCtrl: _tailleCtrl,
              syncTo: _imcCtrl,
            ),
            const SizedBox(height: 14),
            AppField.text(
              controller: _observationsCtrl,
              label: 'Observations du jour',
              hint: 'Constat, évolution, ressenti du patient…',
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Étape 3 : conclusion ----

  Widget _etapeConclusion() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Documents du jour uniquement : ce qui compte est ce qui a été
      // produit pendant CETTE consultation, pas l'historique.
      stream: _patientRef
          .collection('forms')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final aujourdhui = startOfDay(DateTime.now());
        final faitsAujourdhui = <String>{};
        for (final d in snap.data?.docs ?? const []) {
          final data = d.data();
          final cree = asDateOrNull(data['createdAt']);
          if (cree == null || cree.isBefore(aujourdhui)) continue;
          faitsAujourdhui.add(asText(data['type']));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TitreConsultation(
                    titre: 'Documents de la consultation',
                    sous: 'Aucun n\'est obligatoire. L\'écran indique '
                        'simplement ce qui a déjà été rédigé aujourd\'hui.',
                    icone: Icons.description_outlined,
                  ),
                  const SizedBox(height: 16),
                  ..._Livrable.values.map(
                    (l) => _LigneLivrable(
                      livrable: l,
                      fait: faitsAujourdhui.contains(l.typeFirestore),
                      onRediger: _ouvrirDossier,
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

  // ---- Étape 4 : clôture ----

  Widget _etapeCloture() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _patientRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final seances = Seances.fromPatient(data);
        final reglement = Reglement.fromPatient(data);
        final apres = Seances(
          total: seances.total,
          effectuees: seances.effectuees + 1,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FluentCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TitreConsultation(
                    titre: 'Clôturer la consultation',
                    sous: 'La séance sera décomptée et le patient sortira '
                        'de la salle d\'attente.',
                    icone: Icons.task_alt,
                  ),
                  const SizedBox(height: 18),
                  _LigneBilan(
                    icone: Icons.monitor_heart_outlined,
                    label: 'Examen',
                    valeur: _examenEnregistre
                        ? 'Mesures enregistrées'
                        : 'Aucune mesure saisie',
                    fait: _examenEnregistre,
                  ),
                  _LigneBilan(
                    icone: Icons.event_repeat_outlined,
                    label: 'Séances',
                    valeur: apres.sansForfait
                        ? '${apres.effectuees} réalisées'
                        : '${apres.libelle} après clôture',
                    fait: true,
                  ),
                  if (!reglement.sansPrix)
                    _LigneBilan(
                      icone: Icons.account_balance_wallet_outlined,
                      label: 'Règlement',
                      valeur: reglement.solde
                          ? 'Dossier soldé'
                          : '${fmt.money(reglement.reste)} restant dus',
                      fait: reglement.solde,
                      // Un reste à payer n'empêche pas de clôturer : c'est
                      // l'assistant qui encaisse, pas le médecin.
                      alerte: !reglement.solde,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fil des étapes, cliquable vers l'arrière.
class _Etapes extends StatelessWidget {
  final int step;
  final List<String> titres;
  final ValueChanged<int> onTap;

  const _Etapes({required this.step, required this.titres, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: List.generate(titres.length, (i) {
            final passe = i < step;
            final actuel = i == step;
            final couleur = passe
                ? const Color(0xFF16A34A)
                : (actuel ? scheme.primary : scheme.outline);

            return Row(
              children: [
                if (i > 0)
                  Container(
                    width: 26,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: i <= step
                        ? scheme.primary.withValues(alpha: 0.6)
                        : scheme.outline.withValues(alpha: 0.5),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  onTap: i <= step ? () => onTap(i) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                      color: actuel
                          ? Color.alphaBlend(
                              scheme.primary.withValues(alpha: 0.14),
                              scheme.surface,
                            )
                          : Colors.transparent,
                      border: Border.all(
                        color: couleur.withValues(alpha: actuel ? 0.6 : 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          passe ? Icons.check_circle : Icons.circle_outlined,
                          size: 15,
                          color: couleur,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          titres[i],
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: actuel
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: actuel
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _TitreConsultation extends StatelessWidget {
  final String titre;
  final String sous;
  final IconData icone;

  const _TitreConsultation({
    required this.titre,
    required this.sous,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.14),
              scheme.surface,
            ),
          ),
          child: Icon(icone, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titre,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sous,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ligne d'un document : son état du jour et le bouton pour le rédiger.
class _LigneLivrable extends StatelessWidget {
  final _Livrable livrable;
  final bool fait;
  final VoidCallback onRediger;

  const _LigneLivrable({
    required this.livrable,
    required this.fait,
    required this.onRediger,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = fait ? const Color(0xFF16A34A) : scheme.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fait
            ? Color.alphaBlend(
                couleur.withValues(alpha: 0.08),
                scheme.surface,
              )
            : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rField),
        border: Border.all(color: couleur.withValues(alpha: fait ? 0.5 : 0.7)),
      ),
      child: Row(
        children: [
          Icon(
            fait ? Icons.check_circle : livrable.icone,
            size: 20,
            color: fait ? couleur : scheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  livrable.libelle,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  fait ? "Rédigée aujourd'hui" : 'Pas encore rédigée',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: fait ? FontWeight.w600 : FontWeight.w400,
                    fontStyle: fait ? FontStyle.normal : FontStyle.italic,
                    color: fait
                        ? Color.lerp(couleur, scheme.onSurface, 0.25)
                        : scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          FluentButton(
            label: fait ? 'Revoir' : 'Rédiger',
            type: fait ? FluentButtonType.ghost : FluentButtonType.secondary,
            compact: true,
            onPressed: onRediger,
          ),
        ],
      ),
    );
  }
}

/// Ligne du récapitulatif de clôture.
class _LigneBilan extends StatelessWidget {
  final IconData icone;
  final String label;
  final String valeur;
  final bool fait;
  final bool alerte;

  const _LigneBilan({
    required this.icone,
    required this.label,
    required this.valeur,
    required this.fait,
    this.alerte = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = alerte
        ? scheme.secondary
        : (fait ? const Color(0xFF16A34A) : scheme.onSurface.withValues(alpha: 0.45));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              valeur,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: alerte ? couleur : scheme.onSurface,
              ),
            ),
          ),
          if (alerte)
            Tooltip(
              message: "L'encaissement est du ressort de l'assistant",
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barre d'actions de la consultation.
class _BarreConsultation extends StatelessWidget {
  final int step;
  final int dernier;
  final bool cloture;
  final VoidCallback onPrecedent;
  final VoidCallback? onSuivant;

  const _BarreConsultation({
    required this.step,
    required this.dernier,
    required this.cloture,
    required this.onPrecedent,
    required this.onSuivant,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fin = step == dernier;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Row(
            children: [
              if (step > 0)
                FluentButton(
                  label: 'Retour',
                  icon: Icons.arrow_back,
                  type: FluentButtonType.ghost,
                  onPressed: cloture ? null : onPrecedent,
                ),
              const Spacer(),
              FluentButton(
                label: fin ? 'Terminer la consultation' : 'Continuer',
                icon: fin ? Icons.task_alt : Icons.arrow_forward,
                onPressed: onSuivant,
                isLoading: cloture,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

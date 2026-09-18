import 'package:flutter/material.dart';

import 'add_patient_form.dart';
import 'choix_creneau_page.dart';
import '../core/clinical.dart';
import '../core/coerce.dart';
import '../core/creneaux.dart';
import '../services/api_service.dart';
import '../services/recu_service.dart';
import '../services/rendezvous_repository.dart';
import '../services/waiting_service.dart';
import '../ui/app_field.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../ui/info_display.dart';
import '../widgets/computed_fields.dart';

/// Sous ce seuil, la recherche de patient reste sur la liste "patients de
/// la semaine" plutôt que de lancer une recherche sur tout l'historique —
/// deux lettres correspondent à trop de monde pour être utiles.
const int _seuilRecherche = 3;

/// Parcours guidé d'accueil d'un patient, du même geste que le médecin a
/// pour sa consultation (`ConsultationPage`) ou l'assistant pour créer un
/// dossier (`AddPatientForm`) — une étape à la fois, sans changer d'onglet.
///
/// Avant cet écran, traiter un patient déjà connu qui se présente demandait
/// de naviguer entre l'onglet Patients (mise en salle, planification) et
/// l'onglet Salle d'attente (versement, reçu en `SnackBar` transitoire).
/// Ici, les quatre gestes se suivent : Patient → Mise en route → Paiement →
/// Reçu. Aucune logique métier n'est nouvelle — chaque étape appelle
/// exactement les mêmes services (`ApiService`, `WaitingService`,
/// `RendezVousRepository`, `RecuService`) que les anciens points d'entrée
/// dispersés.
class AccueilPatientPage extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final String assistantName;
  final List<String> motifsPredefinis;
  final WaitingService waitingService;

  /// Étape de départ. `0` = accueil complet. `2` = entrée directe au
  /// paiement pour un patient déjà en salle d'attente (voir [patientId]).
  final int etapeInitiale;

  /// Renseigné pour une entrée directe (depuis une ligne de la salle
  /// d'attente) : le dossier complet est rechargé au démarrage.
  final String? patientId;

  const AccueilPatientPage({
    super.key,
    required this.parentUid,
    required this.profileId,
    required this.waitingService,
    this.assistantName = '',
    this.motifsPredefinis = const [],
    this.etapeInitiale = 0,
    this.patientId,
  });

  @override
  State<AccueilPatientPage> createState() => _AccueilPatientPageState();
}

class _AccueilPatientPageState extends State<AccueilPatientPage> {
  static const _titres = ['Patient', 'Mise en route', 'Paiement', 'Reçu'];
  static const _dernierStep = 3;

  late int _step;
  bool _chargementInitial = false;

  // Étape 0 — Patient
  bool? _nouveauPatient;
  final _rechercheCtrl = TextEditingController();
  String _recherche = '';

  /// Une seule lecture pour toute la session de recherche : sans ce cache,
  /// chaque caractère tapé rouvrait un nouveau listener sur toute la
  /// collection patients (le même bug que celui corrigé dans
  /// `PatientsPage`). Les frappes suivantes ne font que refiltrer le même
  /// résultat déjà téléchargé.
  Future<List<Map<String, dynamic>>>? _patientsRecherche;
  String? _patientId;
  Map<String, dynamic>? _patientData;
  bool _patientVenaitDeCreerPatient = false;

  // Étape 1 — Mise en route
  bool _mettreEnSalleChoisi = true;
  bool _miseEnRouteFaite = false;
  String? _miseEnRouteResume;

  // Étape 2 — Paiement
  final _montantCtrl = TextEditingController();
  double? _montantEncaisse;
  double? _nouveauTotalApresVersement;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _step = widget.etapeInitiale;
    _patientId = widget.patientId;
    if (widget.patientId != null) {
      _chargementInitial = true;
      _chargerPatient(widget.patientId!);
    }
  }

  void _onRechercheChanged(String v) {
    setState(() {
      _recherche = v.trim().toLowerCase();
      if (_recherche.length < _seuilRecherche) {
        return;
      }
      _patientsRecherche ??= ApiService.instance.patients(
        profileId: widget.profileId,
      );
    });
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerPatient(String id) async {
    try {
      final data = await ApiService.instance.patient(id);
      if (!mounted) return;
      setState(() {
        _patientData = data;
        _chargementInitial = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _chargementInitial = false);
      _erreur('Dossier patient introuvable');
    }
  }

  void _erreur(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------
  //  Navigation entre étapes
  // ---------------------------------------------------------------

  Future<void> _suivant() async {
    if (_busy) return;
    if (_step == 1 && !_patientVenaitDeCreerPatient) {
      final ok = await _executerMiseEnRoute();
      if (!ok) return;
    }
    if (_step == 2) {
      final ok = await _executerPaiement();
      if (!ok) return;
    }
    if (!mounted) return;
    if (_step < _dernierStep) {
      setState(() => _step++);
    } else {
      Navigator.pop(context);
    }
  }

  void _precedent() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _ouvrirNouveauPatient() async {
    setState(() => _nouveauPatient = true);
    final cree = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPatientForm(
          parentUid: widget.parentUid,
          assistantProfileId: widget.profileId,
          assistantName: widget.assistantName,
          motifsPredefinis: widget.motifsPredefinis,
        ),
      ),
    );
    if (cree == null || !mounted) return;
    setState(() {
      _patientId = (cree['id'] ?? '').toString();
      _patientData = cree;
      _patientVenaitDeCreerPatient = true;
      _miseEnRouteFaite = true;
      _miseEnRouteResume = 'Mis en salle d\'attente';
      _step = 1;
    });
  }

  // ---------------------------------------------------------------
  //  Étape 1 : mise en route
  // ---------------------------------------------------------------

  Future<bool> _executerMiseEnRoute() async {
    final patient = _patientData;
    final patientId = _patientId;
    if (patient == null || patientId == null) return false;
    final doctorId = (patient['doctorId'] ?? '').toString();
    if (doctorId.isEmpty) {
      _erreur('Aucun médecin assigné à ce patient');
      return false;
    }

    setState(() => _busy = true);
    try {
      if (_mettreEnSalleChoisi) {
        final ajoute = await widget.waitingService.addToWaiting(
          parentUid: widget.parentUid,
          assistantId: widget.profileId,
          assistantName: widget.assistantName,
          doctorId: doctorId,
          doctorName: (patient['assignedMedecinName'] ?? '').toString(),
          patientId: patientId,
          patientNom: (patient['nom'] ?? '').toString(),
          patientPrenom: (patient['prenom'] ?? '').toString(),
          nombreSeances: asIntOrNull(patient['nombreSeances']),
          seancesEffectuees: asIntOrNull(patient['seancesEffectuees']) ?? 0,
        );
        _miseEnRouteResume = ajoute
            ? 'Mis en salle d\'attente'
            : 'Déjà en salle d\'attente';
      } else {
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
        if (creneau == null) {
          setState(() => _busy = false);
          return false;
        }
        final rdvData = {
          'patientId': patientId,
          'patientNom': patient['nom'] ?? '',
          'patientPrenom': patient['prenom'] ?? '',
          'patientTel': patient['tel'] ?? '',
          'doctorId': doctorId,
          'doctorName': patient['assignedMedecinName'] ?? '',
          'assistantId': widget.profileId,
          'motif': patient['motif'] ?? '',
          'datetime': creneau.debut.toIso8601String(),
          'duree': creneau.duree,
        };
        await RendezVousRepository().planifier(
          parentUid: widget.parentUid,
          doctorId: doctorId,
          assistantId: widget.profileId,
          rdvData: rdvData,
        );
        final h = creneau.debut;
        _miseEnRouteResume =
            'Rendez-vous planifié à ${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
      }
      if (!mounted) return true;
      setState(() {
        _miseEnRouteFaite = true;
        _busy = false;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _erreur('Erreur lors de la mise en route');
      return false;
    }
  }

  // ---------------------------------------------------------------
  //  Étape 2 : paiement
  // ---------------------------------------------------------------

  Future<bool> _executerPaiement() async {
    final montantText = _montantCtrl.text.replaceAll(',', '.').trim();
    if (montantText.isEmpty) return true; // rien saisi = on passe

    final montant = double.tryParse(montantText);
    if (montant == null || montant <= 0) {
      _erreur('Montant invalide');
      return false;
    }
    final patientId = _patientId;
    final patientData = _patientData;
    if (patientId == null || patientData == null) return false;

    setState(() => _busy = true);
    try {
      await ApiService.instance.encaisser(
        patientId: patientId,
        montant: montant,
        auteurProfileId: widget.profileId,
      );
      final reglement = Reglement.fromPatient(patientData);
      if (!mounted) return true;
      setState(() {
        _montantEncaisse = montant;
        _nouveauTotalApresVersement = reglement.verse + montant;
        _busy = false;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _erreur('Erreur lors de l\'ajout du versement');
      return false;
    }
  }

  // ---------------------------------------------------------------
  //  Étape 3 : reçu
  // ---------------------------------------------------------------

  /// Imprime le reçu d'un versement.
  ///
  /// Identique à l'ancienne `_imprimerRecu` de `dashboard_assistant.dart` :
  /// l'identité du cabinet vient du profil qui encaisse.
  Future<void> _imprimerRecu() async {
    final patientData = _patientData;
    final montant = _montantEncaisse;
    if (patientData == null || montant == null) return;

    setState(() => _busy = true);
    try {
      final p = await ApiService.instance.profils().then(
        (liste) => liste.firstWhere(
          (x) => x['id'] == widget.profileId,
          orElse: () => <String, dynamic>{},
        ),
      );

      final patient = [
        (patientData['nom'] ?? '').toString(),
        (patientData['prenom'] ?? '').toString(),
      ].where((s) => s.trim().isNotEmpty).join(' ');

      final reglement = Reglement.fromPatient({
        ...patientData,
        'totalVersements': _nouveauTotalApresVersement,
      });

      final fichier = await RecuService().imprimer(
        cabinet: [
          (p['nom'] ?? '').toString(),
          (p['prenom'] ?? '').toString(),
        ].where((s) => s.trim().isNotEmpty).join(' '),
        adresse: [
          (p['address'] ?? p['adresse'] ?? '').toString(),
          (p['wilaya'] ?? '').toString(),
        ].where((s) => s.trim().isNotEmpty).join(', '),
        telephone: (p['tel'] ?? p['telephone'] ?? '').toString(),
        patient: patient.isEmpty ? 'Patient' : patient,
        montant: montant,
        date: DateTime.now(),
        reglement: reglement,
        encaissePar: (p['nom'] ?? '').toString(),
        motif: (patientData['motif'] ?? '').toString(),
      );

      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reçu enregistré : ${fichier.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de la génération du reçu')),
      );
    }
  }

  // ---------------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_chargementInitial) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: _step == 0 ? 'Annuler' : 'Étape précédente',
          onPressed: () {
            if (_step > 0) {
              _precedent();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        title: const Text('Accueil patient'),
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
          _Progression(step: _step, titres: _titres),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: AnimatedSwitcher(
                    duration: AppTheme.mid,
                    switchInCurve: AppTheme.ease,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: switch (_step) {
                        0 => _etapePatient(),
                        1 => _etapeMiseEnRoute(),
                        2 => _etapePaiement(),
                        _ => _etapeRecu(),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          _BarreActions(
            step: _step,
            dernier: _dernierStep,
            busy: _busy,
            peutContinuer: _step == 0 ? _patientId != null : true,
            onPrecedent: _precedent,
            onSuivant: _busy ? null : _suivant,
            onPasser: _step == 2 && !_busy
                ? () => setState(() => _step++)
                : null,
          ),
        ],
      ),
    );
  }

  // ---- Étape 0 : patient ----

  Widget _etapePatient() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreEtape(
                titre: 'Qui accueillez-vous ?',
                sous: 'Un nouveau patient, ou quelqu\'un déjà suivi.',
                icone: Icons.person_search_outlined,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    selected: _nouveauPatient == true,
                    avatar: const Icon(Icons.person_add_alt_1, size: 17),
                    label: const Text('Nouveau patient'),
                    onSelected: (_) => _ouvrirNouveauPatient(),
                  ),
                  ChoiceChip(
                    selected: _nouveauPatient == false,
                    avatar: const Icon(Icons.groups_outlined, size: 17),
                    label: const Text('Patient existant'),
                    onSelected: (_) => setState(() {
                      _nouveauPatient = false;
                      _patientId = null;
                      _patientData = null;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_nouveauPatient == false) ...[
          const SizedBox(height: 12),
          FluentCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppField.text(
                  controller: _rechercheCtrl,
                  label: 'Rechercher un patient',
                  hint: 'Nom ou prénom',
                  icon: Icons.search,
                  onChanged: _onRechercheChanged,
                ),
                const SizedBox(height: 12),
                _ResultatsRecherche(
                  profileId: widget.profileId,
                  resultats: _patientsRecherche,
                  recherche: _recherche,
                  selectionneId: _patientId,
                  onSelect: (id, data) => setState(() {
                    _patientId = id;
                    _patientData = data;
                  }),
                ),
              ],
            ),
          ),
        ],
        if (_patientId != null && _patientData != null) ...[
          const SizedBox(height: 12),
          _CartePatient(patientData: _patientData!),
        ],
      ],
    );
  }

  // ---- Étape 1 : mise en route ----

  Widget _etapeMiseEnRoute() {
    if (_patientVenaitDeCreerPatient) {
      return FluentCard(
        padding: const EdgeInsets.all(18),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitreEtape(
              titre: 'Déjà en salle d\'attente',
              sous: 'La création du dossier l\'y a placé automatiquement.',
              icone: Icons.meeting_room_outlined,
              valide: true,
            ),
          ],
        ),
      );
    }

    final patient = _patientData;
    final doctorAssigne = (patient?['doctorId'] ?? '').toString().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreEtape(
                titre: 'Mise en route',
                sous:
                    'Le patient est-il là maintenant, ou vient-il plus tard ?',
                icone: Icons.directions_walk,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    selected: _mettreEnSalleChoisi,
                    avatar: const Icon(Icons.meeting_room_outlined, size: 17),
                    label: const Text('Mettre en salle d\'attente'),
                    onSelected: (_) =>
                        setState(() => _mettreEnSalleChoisi = true),
                  ),
                  ChoiceChip(
                    selected: !_mettreEnSalleChoisi,
                    avatar: const Icon(Icons.event_outlined, size: 17),
                    label: const Text('Planifier un rendez-vous'),
                    onSelected: (_) =>
                        setState(() => _mettreEnSalleChoisi = false),
                  ),
                ],
              ),
              if (!doctorAssigne) ...[
                const SizedBox(height: 12),
                const Text(
                  'Aucun médecin assigné à ce patient : impossible de continuer.',
                  style: TextStyle(color: Color(0xFFD03540)),
                ),
              ],
            ],
          ),
        ),
        if (_miseEnRouteFaite) ...[
          const SizedBox(height: 12),
          FluentCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Text(_miseEnRouteResume ?? ''),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---- Étape 2 : paiement ----

  Widget _etapePaiement() {
    final reglement = Reglement.fromPatient(_patientData);
    final montantSaisi = double.tryParse(
      _montantCtrl.text.replaceAll(',', '.').trim(),
    );
    // Ce que l'assistant encaisse peut etre inferieur au reste du : ca
    // n'est pas une erreur, c'est un versement partiel. Le rendre visible
    // ici — pas seulement dans le dossier apres coup — evite de laisser le
    // patient repartir sans que personne n'ait dit tout haut ce qu'il doit
    // encore.
    final resteApres = (montantSaisi != null && montantSaisi > 0)
        ? ((reglement.reste ?? 0) - montantSaisi)
        : null;

    return FluentCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitreEtape(
            titre: 'Paiement',
            sous: 'Facultatif : passez si le patient règle plus tard.',
            icone: Icons.payments_outlined,
          ),
          const SizedBox(height: 16),
          ReglementSummary(reglement: reglement),
          const SizedBox(height: 14),
          AppField.montant(
            controller: _montantCtrl,
            label: 'Montant encaissé',
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          MontantsSuggeres(
            suggestions: {
              if (reglement.reste != null) 'Solde': reglement.reste!,
              if (reglement.reste != null && reglement.reste! > 1)
                'Moitié': (reglement.reste! / 2).roundToDouble(),
            },
            onChoisi: (m) => setState(() {
              _montantCtrl.text = m.toStringAsFixed(
                m.truncateToDouble() == m ? 0 : 2,
              );
            }),
          ),
          if (resteApres != null && reglement.prix != null) ...[
            const SizedBox(height: 14),
            _ResteApresVersement(montant: resteApres),
          ],
        ],
      ),
    );
  }

  // ---- Étape 3 : reçu ----

  Widget _etapeRecu() {
    final patient = _patientData;
    final nom = [
      (patient?['nom'] ?? '').toString(),
      (patient?['prenom'] ?? '').toString(),
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final montant = _montantEncaisse;

    // Ce qu'il reste a payer une fois ce versement pris en compte (ou
    // inchange si le paiement a ete passe) — c'est le chiffre que
    // l'assistant doit pouvoir annoncer au patient avant qu'il reparte.
    final reglement = Reglement.fromPatient(patient);
    final totalVerseActuel = _nouveauTotalApresVersement ?? reglement.verse;
    final resteFinal = reglement.prix == null
        ? null
        : (reglement.prix! - totalVerseActuel).clamp(0, double.infinity);

    return FluentCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitreEtape(
            titre: 'Reçu',
            sous: 'L\'accueil est terminé.',
            icone: Icons.receipt_long_outlined,
            valide: true,
          ),
          const SizedBox(height: 16),
          InfoGrid(
            items: [
              InfoPair(label: 'Patient', value: nom.isEmpty ? null : nom),
              InfoPair(label: 'Mise en route', value: _miseEnRouteResume),
              InfoPair(
                label: 'Paiement',
                value: montant == null
                    ? null
                    : 'DA ${montant.toStringAsFixed(montant.truncateToDouble() == montant ? 0 : 2)}',
                emphasis: montant != null,
              ),
            ],
          ),
          if (resteFinal != null && resteFinal > 0) ...[
            const SizedBox(height: 14),
            _ResteApresVersement(montant: resteFinal.toDouble()),
          ],
          if (montant != null) ...[
            const SizedBox(height: 16),
            FluentButton(
              label: 'Imprimer le reçu',
              icon: Icons.print_outlined,
              onPressed: _busy ? null : _imprimerRecu,
              isLoading: _busy,
            ),
          ],
        ],
      ),
    );
  }
}

/// Résultats de recherche d'un patient existant, filtrés en mémoire sur
/// nom/prénom — même logique que `PatientsPage`.
///
/// Sans texte tapé, la liste montre les patients de la semaine (même fenêtre
/// que `PatientsPage`, en direct) plutôt qu'un message vide : c'est l'usage
/// courant de l'accueil — retrouver un patient déjà venu récemment — la
/// recherche ponctuelle sur tout l'historique restant pour les cas plus
/// anciens.
class _ResultatsRecherche extends StatelessWidget {
  final String profileId;
  final Future<List<Map<String, dynamic>>>? resultats;
  final String recherche;
  final String? selectionneId;
  final void Function(String id, Map<String, dynamic> data) onSelect;

  const _ResultatsRecherche({
    required this.profileId,
    required this.resultats,
    required this.recherche,
    required this.selectionneId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (recherche.length < _seuilRecherche) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: ApiService.instance.patientsRecentsFlux(
          profileId: profileId,
          depuis: DateTime.now().subtract(const Duration(days: 7)),
        ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.data!.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun patient cette semaine.'),
            );
          }
          return _listeResultats(snap.data!.take(8).toList());
        },
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: resultats,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final resultats = snap.data!
            .where((p) {
              final nom = (p['nom'] ?? '').toString();
              final prenom = (p['prenom'] ?? '').toString();
              return '$nom $prenom'.toLowerCase().contains(recherche);
            })
            .take(8)
            .toList();

        if (resultats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun patient trouvé.'),
          );
        }

        return _listeResultats(resultats);
      },
    );
  }

  Widget _listeResultats(List<Map<String, dynamic>> resultats) {
    return Column(
      children: resultats.map((p) {
        final id = (p['id'] ?? '').toString();
        final nom = (p['nom'] ?? 'Patient').toString();
        final prenom = (p['prenom'] ?? '').toString();
        final selectionne = id == selectionneId;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: Icon(
              selectionne ? Icons.check_circle : Icons.person_outline,
              color: selectionne ? const Color(0xFF16A34A) : null,
            ),
            title: Text('$nom $prenom'),
            subtitle: Text((p['tel'] ?? '').toString()),
            onTap: () => onSelect(id, p),
          ),
        );
      }).toList(),
    );
  }
}

/// Bannière « il restera X DA impayé » — le pendant, côté encaissement, de
/// la bannière allergies du dossier patient : une information à ne pas
/// pouvoir manquer, pas une ligne parmi d'autres.
class _ResteApresVersement extends StatelessWidget {
  final double montant;

  const _ResteApresVersement({required this.montant});

  @override
  Widget build(BuildContext context) {
    final corail = AppTheme.corail(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: corail.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.rButton),
        border: Border.all(color: corail.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: corail, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Restera impayé : DA ${montant.toStringAsFixed(montant.truncateToDouble() == montant ? 0 : 2)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: corail),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartePatient extends StatelessWidget {
  final Map<String, dynamic> patientData;

  const _CartePatient({required this.patientData});

  @override
  Widget build(BuildContext context) {
    final nom = [
      (patientData['nom'] ?? '').toString(),
      (patientData['prenom'] ?? '').toString(),
    ].where((s) => s.trim().isNotEmpty).join(' ');
    final medecin =
        (patientData['assignedMedecinName'] ?? patientData['doctorId'] ?? '')
            .toString();
    final tel = (patientData['tel'] ?? '').toString();

    return FluentCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitreEtape(
            titre: nom.isEmpty ? 'Patient' : nom,
            sous: 'Sélectionné',
            icone: Icons.check_circle_outline,
            valide: true,
          ),
          const SizedBox(height: 12),
          InfoGrid(
            items: [
              InfoPair(
                label: 'Médecin',
                value: medecin.isEmpty ? null : medecin,
              ),
              InfoPair(label: 'Téléphone', value: tel.isEmpty ? null : tel),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barre de progression et nom de l'étape courante.
class _Progression extends StatelessWidget {
  final int step;
  final List<String> titres;

  const _Progression({required this.step, required this.titres});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = titres.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: scheme.surface,
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Étape ${step + 1} sur $total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titres[step],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(total, (i) {
              final atteint = i <= step;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: AppTheme.mid,
                    curve: AppTheme.ease,
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: atteint
                          ? scheme.primary
                          : scheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// En-tête d'étape : titre, sous-titre explicatif, pastille d'icône.
class _TitreEtape extends StatelessWidget {
  final String titre;
  final String sous;
  final IconData icone;
  final bool valide;

  const _TitreEtape({
    required this.titre,
    required this.sous,
    required this.icone,
    this.valide = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = valide ? const Color(0xFF16A34A) : scheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Color.alphaBlend(
              couleur.withValues(alpha: 0.14),
              scheme.surface,
            ),
          ),
          child: Icon(valide ? Icons.check : icone, size: 20, color: couleur),
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
              const SizedBox(height: 2),
              Text(
                sous,
                style: TextStyle(
                  fontSize: 12.5,
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

/// Boutons de navigation, épinglés en bas pour rester accessibles.
class _BarreActions extends StatelessWidget {
  final int step;
  final int dernier;
  final bool busy;
  final bool peutContinuer;
  final VoidCallback onPrecedent;
  final VoidCallback? onSuivant;
  final VoidCallback? onPasser;

  const _BarreActions({
    required this.step,
    required this.dernier,
    required this.busy,
    required this.peutContinuer,
    required this.onPrecedent,
    required this.onSuivant,
    this.onPasser,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dernierEtape = step == dernier;

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
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(
            children: [
              if (step > 0) ...[
                FluentButton(
                  label: 'Retour',
                  icon: Icons.arrow_back,
                  type: FluentButtonType.ghost,
                  onPressed: busy ? null : onPrecedent,
                ),
                const SizedBox(width: 10),
              ],
              if (onPasser != null) ...[
                FluentButton(
                  label: 'Passer cette étape',
                  type: FluentButtonType.ghost,
                  onPressed: onPasser,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FluentButton(
                    label: dernierEtape ? 'Terminer' : 'Continuer',
                    icon: dernierEtape
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward,
                    onPressed: peutContinuer ? onSuivant : null,
                    isLoading: busy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'medecins_cards.dart';
import '../core/format.dart' as fmt;
import '../core/validate.dart' as v;
import '../services/api_service.dart';
import '../ui/app_field.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';

/// Création d'un dossier patient, en trois étapes.
///
/// L'écran présentait auparavant huit champs, quatre boutons radio, une liste
/// de motifs et une grille de médecins sur une seule page, sans validation :
/// on découvrait une erreur après avoir tout saisi.
///
/// Chaque étape valide ce qu'elle contient avant de laisser avancer, et la
/// dernière récapitule ce qui sera enregistré.
class AddPatientForm extends StatefulWidget {
  final String parentUid;
  final String assistantProfileId;
  final String assistantName;
  final List<String> motifsPredefinis;

  const AddPatientForm({
    super.key,
    required this.parentUid,
    required this.assistantProfileId,
    this.assistantName = '',
    this.motifsPredefinis = const [],
  });

  @override
  State<AddPatientForm> createState() => _AddPatientFormState();
}

/// Origines proposées. La clé part en base, le libellé s'affiche.
const List<({String cle, String libelle, IconData icone})> _origines = [
  (cle: 'reseaux', libelle: 'Réseaux sociaux', icone: Icons.share_outlined),
  (
    cle: 'famille_amis_bouche_a_oreille',
    libelle: 'Famille ou amis',
    icone: Icons.groups_outlined,
  ),
  (
    cle: 'proximite_geographique_passage',
    libelle: 'Passage devant le cabinet',
    icone: Icons.place_outlined,
  ),
  (cle: 'internet', libelle: 'Site internet', icone: Icons.language),
];

class _AddPatientFormState extends State<AddPatientForm> {
  // Une clé par étape : on ne valide que ce que l'utilisateur a sous les yeux.
  final _identiteKey = GlobalKey<FormState>();
  final _notesKey = GlobalKey<FormState>();

  final nom = TextEditingController();
  final prenom = TextEditingController();
  final age = TextEditingController();
  final tel = TextEditingController();
  final email = TextEditingController();
  final formulaireInitial = TextEditingController();
  final motifAutre = TextEditingController();

  String origine = '';
  final Set<String> motifs = {};
  late List<String> motifsOptions;

  String? selectedDoctorId;
  Map<String, dynamic>? selectedDoctorData;

  int _step = 0;
  bool _isSaving = false;

  static const int _dernierStep = 2;

  @override
  void initState() {
    super.initState();
    motifsOptions = widget.motifsPredefinis.isNotEmpty
        ? [...widget.motifsPredefinis]
        : ['perte', 'prise'];
    _loadMotifsFromProfile();
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
      // Le repli sur le profil assistant disparait : Firestore gardait les
      // motifs a deux endroits — le cabinet et le profil — et il fallait
      // recopier les seconds sur le premier au premier chargement. Le
      // backend n'en a plus qu'une source.
      final cabinet = await ApiService.instance.cabinet();
      final brut = cabinet['motifsPredefinis'];
      final fetched = brut is List
          ? brut
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : <String>[];
      if (fetched.isNotEmpty && mounted) {
        setState(() => motifsOptions = fetched);
      }
    } catch (_) {
      // Sans motifs predefinis la saisie reste possible : le champ libre
      // suffit. Bloquer la creation d'un dossier pour une liste de
      // suggestions serait disproportionne.
    }
  }

  // ---------------------------------------------------------------
  //  Navigation entre étapes
  // ---------------------------------------------------------------

  /// Ce qui manque à l'étape courante, ou `null` si elle est complète.
  /// Sert à la fois à bloquer et à expliquer pourquoi.
  String? _bloquant(int step) {
    switch (step) {
      case 0:
        return (_identiteKey.currentState?.validate() ?? false)
            ? null
            : 'Corrigez les champs signalés';
      case 1:
        if (motifs.isEmpty) return 'Choisissez au moins un motif';
        if (selectedDoctorId == null) return 'Choisissez un médecin';
        return null;
      default:
        return null;
    }
  }

  void _suivant() {
    final erreur = _bloquant(_step);
    if (erreur != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(erreur)));
      return;
    }
    if (_step < _dernierStep) {
      setState(() => _step++);
    } else {
      saveForm();
    }
  }

  void _precedent() {
    if (_step > 0) setState(() => _step--);
  }

  // ---------------------------------------------------------------
  //  Enregistrement
  // ---------------------------------------------------------------

  Future<void> _erreur(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> saveForm() async {
    if (_isSaving) return;

    // Filet de sécurité : l'assistant empêche déjà d'arriver ici incomplet,
    // mais on ne fait pas confiance à la seule navigation.
    if (!(_identiteKey.currentState?.validate() ?? false)) {
      setState(() => _step = 0);
      return _erreur('Corrigez les champs signalés');
    }
    if (motifs.isEmpty || selectedDoctorId == null) {
      setState(() => _step = 1);
      return _erreur('Motif et médecin sont obligatoires');
    }

    setState(() => _isSaving = true);
    try {
      // L'age part en entier. Les anciens dossiers l'ont en chaine ; le
      // backend accepte les deux et normalise.
      final ageValue = int.tryParse(age.text.trim());

      // Cinq ecritures tenaient ici : le dossier chez le medecin, le meme
      // chez l'assistant, l'entree en salle d'attente, et le formulaire
      // initial sous chacune des deux copies. Firestore ne sachant pas
      // joindre, il fallait tout dupliquer — et un echec partiel laissait le
      // dossier visible d'un cote et absent de l'autre.
      //
      // C'est une requete, et une transaction cote serveur.
      final cree = await ApiService.instance.creerPatient({
        'nom': nom.text.trim(),
        'prenom': prenom.text.trim(),
        if (ageValue != null) 'age': ageValue,
        // Normalise : +213… et 00213… deviennent 0…, pour que la recherche
        // et les rappels WhatsApp retombent sur le meme numero.
        'tel': v.normalizePhone(tel.text),
        'email': email.text.trim(),
        'origine': origine,
        'motifs': motifs.toList(),
        'doctorId': selectedDoctorId,
        'assistantId': widget.assistantProfileId,
        'assistantName': widget.assistantName,
        'assignedMedecinName': selectedDoctorData?['name'] ?? '',
        'createdByAssistantProfileId': widget.assistantProfileId,
        'formulaireInitial': formulaireInitial.text.trim(),
      });
      final patientId = (cree['id'] ?? '').toString();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${nom.text.trim()} ${prenom.text.trim()} ajouté en salle d\'attente',
            ),
          ),
        );
      Navigator.pop(context);
    } catch (_) {
      await _erreur("Erreur lors de l'enregistrement");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
        title: const Text('Nouveau patient'),
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
          _Progression(step: _step, total: _dernierStep + 1),
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
                        0 => _etapeIdentite(),
                        1 => _etapeMotif(scheme),
                        _ => _etapeNotes(scheme),
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
            isSaving: _isSaving,
            onPrecedent: _precedent,
            onSuivant: _isSaving ? null : _suivant,
          ),
        ],
      ),
    );
  }

  // ---- Étape 1 : identité ----

  Widget _etapeIdentite() {
    return Form(
      key: _identiteKey,
      child: FluentCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TitreEtape(
              titre: 'Identité du patient',
              sous: 'Le nom suffit pour commencer. Le reste peut attendre.',
              icone: Icons.badge_outlined,
            ),
            const SizedBox(height: 18),
            AppField.nom(
              controller: nom,
              label: 'Nom',
              icon: Icons.person_outline,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            AppField.nom(
              controller: prenom,
              label: 'Prénom',
              icon: Icons.person_outline,
              obligatoire: false,
            ),
            const SizedBox(height: 12),
            AppField.age(controller: age),
            const SizedBox(height: 12),
            AppField.phone(controller: tel),
            const SizedBox(height: 12),
            AppField.email(controller: email),
          ],
        ),
      ),
    );
  }

  // ---- Étape 2 : motif et médecin ----

  Widget _etapeMotif(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreEtape(
                titre: 'Motif de consultation',
                sous: 'Au moins un motif est nécessaire.',
                icone: Icons.assignment_outlined,
              ),
              const SizedBox(height: 16),
              // Pastilles plutôt que cases à cocher empilées : on voit tous
              // les motifs d'un coup et on en sélectionne plusieurs au tap.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: motifsOptions.map((opt) {
                  final actif = motifs.contains(opt);
                  return FilterChip(
                    selected: actif,
                    label: Text(fmt.capitalize(fmt.humanize(opt))),
                    onSelected: (on) => setState(() {
                      if (on) {
                        motifs.add(opt);
                      } else {
                        motifs.remove(opt);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              AppField.text(
                controller: motifAutre,
                label: 'Autre motif',
                hint: 'Si aucun des choix ci-dessus ne convient',
                icon: Icons.add_comment_outlined,
                onChanged: (val) => setState(() {
                  motifs.removeWhere((m) => m.startsWith('autre:'));
                  if (val.trim().isNotEmpty) motifs.add('autre:${val.trim()}');
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreEtape(
                titre: 'Comment nous a-t-il connus ?',
                sous: 'Facultatif, mais utile pour vos statistiques.',
                icone: Icons.travel_explore_outlined,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _origines.map((o) {
                  final actif = origine == o.cle;
                  return ChoiceChip(
                    selected: actif,
                    avatar: Icon(o.icone, size: 17),
                    label: Text(o.libelle),
                    // Un second tap désélectionne : l'origine est facultative,
                    // et un bouton radio ne se dérange jamais.
                    onSelected: (on) =>
                        setState(() => origine = on ? o.cle : ''),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitreEtape(
                titre: 'Médecin destinataire',
                sous: selectedDoctorData == null
                    ? 'Touchez une carte pour choisir.'
                    : 'Sélectionné : ${selectedDoctorData!['name'] ?? ''}',
                icone: Icons.medical_services_outlined,
                valide: selectedDoctorId != null,
              ),
              const SizedBox(height: 14),
              MedecinsCards(
                parentUid: widget.parentUid,
                onTap: (docId, data) => setState(() {
                  selectedDoctorId = docId;
                  selectedDoctorData = data;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Étape 3 : notes et récapitulatif ----

  Widget _etapeNotes(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentCard(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: _notesKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _TitreEtape(
                  titre: 'Note initiale',
                  sous: 'Visible du médecin comme de l\'assistant.',
                  icone: Icons.edit_note_outlined,
                ),
                const SizedBox(height: 16),
                AppField.text(
                  controller: formulaireInitial,
                  label: 'Observations',
                  hint: 'Laissez vide si rien de particulier',
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Recapitulatif(
          nom: nom.text,
          prenom: prenom.text,
          age: age.text,
          tel: tel.text,
          email: email.text,
          motifs: motifs.toList(),
          origine: origine,
          medecin: (selectedDoctorData?['name'] ?? '').toString(),
          onCorriger: (step) => setState(() => _step = step),
        ),
      ],
    );
  }
}

/// Barre de progression et nom de l'étape courante.
class _Progression extends StatelessWidget {
  final int step;
  final int total;

  const _Progression({required this.step, required this.total});

  static const _noms = ['Identité', 'Motif et médecin', 'Note et validation'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                  _noms[step],
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

/// Récapitulatif de fin : ce qui sera enregistré, avec retour direct à
/// l'étape concernée pour corriger sans tout reprendre.
class _Recapitulatif extends StatelessWidget {
  final String nom;
  final String prenom;
  final String age;
  final String tel;
  final String email;
  final List<String> motifs;
  final String origine;
  final String medecin;
  final ValueChanged<int> onCorriger;

  const _Recapitulatif({
    required this.nom,
    required this.prenom,
    required this.age,
    required this.tel,
    required this.email,
    required this.motifs,
    required this.origine,
    required this.medecin,
    required this.onCorriger,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final libellesMotifs = motifs
        .map((m) => m.startsWith('autre:') ? m.substring(6) : fmt.humanize(m))
        .join(', ');
    final origineLibelle = _origines
        .where((o) => o.cle == origine)
        .map((o) => o.libelle)
        .firstOrNull;

    return FluentCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitreEtape(
            titre: 'Récapitulatif',
            sous: 'Vérifiez avant d\'enregistrer.',
            icone: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 16),
          _Ligne(
            label: 'Patient',
            valeur: '$nom $prenom'.trim(),
            onCorriger: () => onCorriger(0),
          ),
          _Ligne(
            label: 'Âge',
            valeur: age.trim().isEmpty ? null : '$age ans',
            onCorriger: () => onCorriger(0),
          ),
          _Ligne(
            label: 'Téléphone',
            valeur: tel.trim().isEmpty ? null : fmt.phone(v.normalizePhone(tel)),
            onCorriger: () => onCorriger(0),
          ),
          _Ligne(
            label: 'E-mail',
            valeur: email.trim().isEmpty ? null : email.trim(),
            onCorriger: () => onCorriger(0),
          ),
          Divider(color: scheme.outline.withValues(alpha: 0.5), height: 22),
          _Ligne(
            label: 'Motifs',
            valeur: libellesMotifs.isEmpty ? null : fmt.capitalize(libellesMotifs),
            onCorriger: () => onCorriger(1),
          ),
          _Ligne(
            label: 'Origine',
            valeur: origineLibelle,
            onCorriger: () => onCorriger(1),
          ),
          _Ligne(
            label: 'Médecin',
            valeur: medecin.isEmpty ? null : medecin,
            onCorriger: () => onCorriger(1),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final String label;
  final String? valeur;
  final VoidCallback onCorriger;

  const _Ligne({
    required this.label,
    required this.valeur,
    required this.onCorriger,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vide = valeur == null || valeur!.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              vide ? 'Non renseigné' : valeur!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: vide ? FontWeight.w400 : FontWeight.w700,
                fontStyle: vide ? FontStyle.italic : FontStyle.normal,
                color: vide
                    ? scheme.onSurface.withValues(alpha: 0.45)
                    : scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Corriger',
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            icon: const Icon(Icons.edit_outlined),
            onPressed: onCorriger,
          ),
        ],
      ),
    );
  }
}

/// Boutons de navigation, épinglés en bas pour rester accessibles.
class _BarreActions extends StatelessWidget {
  final int step;
  final int dernier;
  final bool isSaving;
  final VoidCallback onPrecedent;
  final VoidCallback? onSuivant;

  const _BarreActions({
    required this.step,
    required this.dernier,
    required this.isSaving,
    required this.onPrecedent,
    required this.onSuivant,
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
                  onPressed: isSaving ? null : onPrecedent,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FluentButton(
                    label: dernierEtape ? 'Enregistrer le patient' : 'Continuer',
                    icon: dernierEtape
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward,
                    onPressed: onSuivant,
                    isLoading: isSaving,
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

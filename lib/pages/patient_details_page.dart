import '../ui/app_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../ui/fluent_button.dart';
import 'consultation_page.dart';
import 'ordonnance_page.dart';
import 'bilan_page.dart';
import '../core/coerce.dart';
import '../core/doctor_form_prototype.dart';
import '../core/versements.dart';
import '../core/visite.dart';
import '../ui/info_display.dart';
import '../ui/liberer.dart';
import '../core/clinical.dart';
import '../core/format.dart' as fmt;
import '../core/validate.dart' as v;
import '../ui/app_field.dart';
import '../widgets/computed_fields.dart';
import '../widgets/historique_seances.dart';
import '../widgets/patient_status_bar.dart';
// import '../widgets/patient_documents_card.dart'; // onglet Pieces jointes desactive

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

class PatientDetailsPage extends StatelessWidget {
  final String patientId;
  final String patientName;
  final String parentUid;
  final String ownerProfileId;
  final bool canAddForm;
  final bool canAddDoctorForm;

  PatientDetailsPage({
    Key? key,
    required this.patientId,
    required this.patientName,
    required this.parentUid,
    required this.ownerProfileId,
    this.canAddForm = true,
    this.canAddDoctorForm = false,
  }) : super(key: key);

  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);

  /// Ouvre la page de rédaction d'ordonnance (appelée depuis le dossier
  /// patient ou depuis la consultation en cours).
  static Future<void> ouvrirOrdonnance(
    BuildContext context, {
    required String ownerProfileId,
    required String patientId,
    required Map<String, dynamic> patientData,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrdonnancePage(
          ownerProfileId: ownerProfileId,
          patientId: patientId,
          patientData: patientData,
        ),
      ),
    );
  }

  /// Ouvre la page de rédaction de demande de bilan (appelée depuis le
  /// dossier patient ou depuis la consultation en cours).
  static Future<void> ouvrirBilan(
    BuildContext context, {
    required String ownerProfileId,
    required String patientId,
    required Map<String, dynamic> patientData,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BilanPage(
          ownerProfileId: ownerProfileId,
          patientId: patientId,
          patientData: patientData,
        ),
      ),
    );
  }

  /// Ouvre le dialogue de formulaire médecin sans naviguer vers le dossier
  /// patient (appelé depuis la consultation en cours).
  static Future<void> ouvrirFormulaireMedecin(
    BuildContext context, {
    required String parentUid,
    required String ownerProfileId,
    required String patientId,
    required Map<String, dynamic> patientData,
  }) {
    final page = PatientDetailsPage(
      patientId: patientId,
      patientName: '',
      parentUid: parentUid,
      ownerProfileId: ownerProfileId,
    );
    return page._addDoctorForm(context, patientData: patientData);
  }

  static const _tabs = <_DossierTab>[
    _DossierTab(Icons.dashboard_outlined, 'Resume'),
    _DossierTab(Icons.history, 'Consultations'),
    _DossierTab(Icons.receipt_long, 'Ordonnances'),
    _DossierTab(Icons.science_outlined, 'Bilans'),
    _DossierTab(Icons.payment, 'Paiements'),
    _DossierTab(Icons.info_outline, 'Infos'),
    // Pieces jointes (Firebase Storage) : desactive en attendant le
    // deploiement de storage.rules — voir _buildTabContent case 6, laisse
    // en commentaire plutot que supprime pour reactiver en un coup.
    // _DossierTab(Icons.attach_file, 'Pieces jointes'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink1 = AppTheme.ink1(context);
    final ink2 = AppTheme.ink2(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0,
        backgroundColor: AppTheme.panel(context),
        titleSpacing: 0,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rButton),
            onTap: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.raised(context),
                borderRadius: BorderRadius.circular(AppTheme.rButton),
                border: Border.all(color: scheme.outline),
              ),
              child: Center(
                child: Icon(Icons.arrow_back, color: ink2, size: 18),
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dossier patient',
              style: TextStyle(
                color: ink2,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              patientName,
              style: TextStyle(
                color: ink1,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outline),
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: FirestoreService().patientDoc(
          parentUid: parentUid,
          profileId: ownerProfileId,
          patientId: patientId,
        ),
        builder: (context, patientSnap) {
          if (!patientSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final patientData = patientSnap.data ?? <String, dynamic>{};
          final doctorId = (patientData['doctorId'] ?? '').toString().trim();
          final assistantId = (patientData['assistantId'] ?? '')
              .toString()
              .trim();
          final doctorName = _doctorNameFromData(patientData);
          final assistantName = _assistantNameFromData(patientData);
          var doctorLabel = doctorName.isNotEmpty ? doctorName : doctorId;
          if (doctorLabel == 'medecin_principal') {
            doctorLabel = 'Medecin principal';
          }
          final assistantLabel = assistantName.isNotEmpty
              ? assistantName
              : assistantId;
          final ownerLabel = _resolveOwnerLabel(
            ownerProfileId,
            doctorId,
            assistantId,
            doctorLabel,
            assistantLabel,
          );
          final prix = _parseDouble(patientData['prix']);
          final versements = _normalizeVersements(patientData['versements']);
          final totalFromList = versements.fold<double>(
            0,
            (sum, v) => sum + ((v['montant'] as double?) ?? 0),
          );
          final totalVersementsRaw = _parseDouble(
            patientData['totalVersements'],
          );
          final totalVersements =
              totalVersementsRaw ??
              (versements.isNotEmpty ? totalFromList : null);
          final seancesTotal = _parseInt(patientData['nombreSeances']);
          final seancesDone = _parseInt(patientData['seancesEffectuees']);

          return Column(
            children: [
              PatientStatusBar(patientId: patientId),
              Expanded(
                child: Row(
                  children: [
                    _buildSidebar(context, scheme),
                    VerticalDivider(width: 1, color: scheme.outline),
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _tabIndex,
                        builder: (context, currentTabIndex, _) {
                          return _buildTabContent(
                            context: context,
                            scheme: scheme,
                            tabIndex: currentTabIndex,
                            patientData: patientData,
                            doctorId: doctorId,
                            assistantId: assistantId,
                            doctorLabel: doctorLabel,
                            assistantLabel: assistantLabel,
                            ownerLabel: ownerLabel,
                            prix: prix,
                            totalVersements: totalVersements,
                            seancesTotal: seancesTotal,
                            seancesDone: seancesDone,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, ColorScheme scheme) {
    final ink1 = AppTheme.ink1(context);
    final ink2 = AppTheme.ink2(context);
    final menthe = AppTheme.menthe(context);

    return SizedBox(
      width: 200,
      child: Column(
        children: [
          if (canAddDoctorForm) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: FluentButton(
                  label: 'Consultation',
                  icon: Icons.play_circle_outline,
                  onPressed: () {
                    final stream = FirestoreService().patientDoc(
                      parentUid: parentUid,
                      profileId: ownerProfileId,
                      patientId: patientId,
                    );
                    stream.first.then((data) {
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConsultationPage.depuisDossier(
                            parentUid: parentUid,
                            profileId: ownerProfileId,
                            patientId: patientId,
                            patient: data ?? {},
                          ),
                        ),
                      );
                    });
                  },
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outline),
          ],
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _tabIndex,
              builder: (context, currentTabIndex, _) {
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _tabs.length,
                  itemBuilder: (context, i) {
                    final tab = _tabs[i];
                    final selected = i == currentTabIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Material(
                        color: selected
                            ? menthe.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTheme.rButton),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.rButton),
                          onTap: () => _tabIndex.value = i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  tab.icon,
                                  size: 20,
                                  color: selected ? menthe : ink2,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tab.label,
                                    style: TextStyle(
                                      color: selected ? ink1 : ink2,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent({
    required BuildContext context,
    required ColorScheme scheme,
    required int tabIndex,
    required Map<String, dynamic> patientData,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
    required double? prix,
    required double? totalVersements,
    required int? seancesTotal,
    required int? seancesDone,
  }) {
    switch (tabIndex) {
      case 0:
        return _buildResumeTab(
          context: context,
          scheme: scheme,
          patientData: patientData,
          doctorLabel: doctorLabel,
          assistantLabel: assistantLabel,
          prix: prix,
          totalVersements: totalVersements,
          seancesTotal: seancesTotal,
          seancesDone: seancesDone,
        );
      case 1:
        return _buildConsultationsTab();
      case 2:
        return _buildDocumentsTab(
          context: context,
          scheme: scheme,
          patientData: patientData,
          filterType: 'ordonnance',
          doctorId: doctorId,
          assistantId: assistantId,
          doctorLabel: doctorLabel,
          assistantLabel: assistantLabel,
          ownerLabel: ownerLabel,
        );
      case 3:
        return _buildDocumentsTab(
          context: context,
          scheme: scheme,
          patientData: patientData,
          filterType: 'bilan',
          doctorId: doctorId,
          assistantId: assistantId,
          doctorLabel: doctorLabel,
          assistantLabel: assistantLabel,
          ownerLabel: ownerLabel,
        );
      case 4:
        return _buildPaiementsTab(
          context: context,
          scheme: scheme,
          patientData: patientData,
          doctorId: doctorId,
          assistantId: assistantId,
          doctorLabel: doctorLabel,
          assistantLabel: assistantLabel,
          ownerLabel: ownerLabel,
          totalVersements: totalVersements,
        );
      case 5:
        return _buildInfosTab(
          context: context,
          scheme: scheme,
          patientData: patientData,
          doctorId: doctorId,
          assistantId: assistantId,
          doctorLabel: doctorLabel,
          assistantLabel: assistantLabel,
          ownerLabel: ownerLabel,
        );
      // case 6 (Pieces jointes) desactive avec l'onglet ci-dessus.
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildResumeTab({
    required BuildContext context,
    required ColorScheme scheme,
    required Map<String, dynamic> patientData,
    required String doctorLabel,
    required String assistantLabel,
    required double? prix,
    required double? totalVersements,
    required int? seancesTotal,
    required int? seancesDone,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _PatientHeader(
            name: patientData['nom'] ?? patientName,
            prenom: patientData['prenom'] ?? '',
            tel: patientData['tel'] ?? '',
            email: patientData['email'] ?? '',
            motif: patientData['motif'] ?? '',
            origine: patientData['origine'] ?? '',
            age: patientData['age']?.toString() ?? '',
            medecin: doctorLabel,
            assistant: assistantLabel,
            prix: prix,
            versementsTotal: totalVersements,
            seancesTotal: seancesTotal,
            seancesDone: seancesDone,
            createdAt: patientData['createdAt'],
          ),
          const SizedBox(height: 12),
          _InfosMedicalesCard(
            sexe: (patientData['sexe'] ?? '').toString(),
            groupeSanguin: (patientData['groupeSanguin'] ?? '').toString(),
            adresse: (patientData['adresse'] ?? '').toString(),
            allergies: (patientData['allergies'] ?? '').toString(),
            contactUrgenceNom: (patientData['contactUrgenceNom'] ?? '')
                .toString(),
            contactUrgenceTel: (patientData['contactUrgenceTel'] ?? '')
                .toString(),
            onModifier: () => _openInfosMedicalesDialog(context, patientData),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreService().patientForms(
              parentUid: parentUid,
              profileId: ownerProfileId,
              patientId: patientId,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final merged = snapshot.data!;

              Map<String, dynamic>? latestMedSections;
              for (final data in merged.reversed) {
                final type = (data['type'] ?? '').toString().toLowerCase();
                if (type.contains('medecin')) {
                  final sec = (data['sections'] as Map?)
                      ?.cast<String, dynamic>();
                  if (sec != null && sec.isNotEmpty) {
                    latestMedSections = sec;
                    break;
                  }
                }
              }

              String fromSections(List<String> keys) {
                if (latestMedSections == null) return '';
                for (final k in keys) {
                  final v =
                      latestMedSections![k] ??
                      latestMedSections![k.toLowerCase()];
                  if (v != null && v.toString().trim().isNotEmpty) {
                    return v.toString();
                  }
                }
                return '';
              }

              String metricPoids =
                  fromSections(['poids_actuel', 'poids', 'Poids']).isNotEmpty
                  ? fromSections(['poids_actuel', 'poids', 'Poids'])
                  : (patientData['poids']?.toString() ?? '-');
              String metricTaille =
                  fromSections(['taille', 'Taille']).isNotEmpty
                  ? fromSections(['taille', 'Taille'])
                  : (patientData['taille']?.toString() ?? '-');
              String metricImc = fromSections(['imc', 'IMC']).isNotEmpty
                  ? fromSections(['imc', 'IMC'])
                  : (patientData['imc']?.toString() ?? '-');

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          label: 'Poids',
                          value: metricPoids,
                          suffix: 'kg',
                        ),
                        _MetricCard(
                          label: 'Taille',
                          value: metricTaille,
                          suffix: 'cm',
                        ),
                        _MetricCard(label: 'IMC', value: metricImc),
                        _MetricCard(
                          label: 'Motif',
                          value: fmt.capitalize(
                            fmt.humanize(patientData['motif']),
                          ),
                          fallback: 'Non renseigne',
                        ),
                        _MetricCard(
                          label: 'Origine',
                          value: fmt.capitalize(
                            fmt.humanize(patientData['origine']),
                          ),
                          fallback: 'Non renseignee',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c) {
                        final reglement = ReglementSummary(
                          reglement: Reglement.fromPatient(patientData),
                        );
                        final seances = SeancesSummary(
                          seances: Seances.fromPatient(patientData),
                        );
                        if (c.maxWidth < 560) {
                          return Column(
                            children: [
                              reglement,
                              const SizedBox(height: 12),
                              seances,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: reglement),
                            const SizedBox(width: 12),
                            Expanded(child: seances),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConsultationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CarteHistoriqueSeances(
        parentUid: parentUid,
        profileId: ownerProfileId,
        patientId: patientId,
        compact: false,
      ),
    );
  }

  Widget _buildDocumentsTab({
    required BuildContext context,
    required ColorScheme scheme,
    required Map<String, dynamic> patientData,
    required String filterType,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
  }) {
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 18,
      color: scheme.onSurface,
    );
    final contentStyle = TextStyle(
      fontSize: 15,
      height: 1.35,
      color: scheme.onSurface,
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService().patientForms(
        parentUid: parentUid,
        profileId: ownerProfileId,
        patientId: patientId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final filtered = all.where((doc) {
          final type = (doc['type'] ?? '').toString().toLowerCase();
          return type.contains(filterType);
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      filterType == 'ordonnance' ? 'Ordonnances' : 'Bilans',
                      style: titleStyle,
                    ),
                  ),
                  FluentButton(
                    label: filterType == 'ordonnance'
                        ? 'Nouvelle ordonnance'
                        : 'Nouveau bilan',
                    icon: Icons.add,
                    onPressed: () {
                      if (filterType == 'ordonnance') {
                        PatientDetailsPage.ouvrirOrdonnance(
                          context,
                          ownerProfileId: ownerProfileId,
                          patientId: patientId,
                          patientData: patientData,
                        );
                      } else {
                        PatientDetailsPage.ouvrirBilan(
                          context,
                          ownerProfileId: ownerProfileId,
                          patientId: patientId,
                          patientData: patientData,
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      filterType == 'ordonnance'
                          ? 'Aucune ordonnance'
                          : 'Aucun bilan',
                      style: TextStyle(color: AppTheme.ink2(context)),
                    ),
                  ),
                )
              else
                _renderFormGroups(
                  filtered,
                  titleStyle,
                  contentStyle,
                  patientData,
                  context: context,
                  ownerProfileId: ownerProfileId,
                  doctorId: doctorId,
                  assistantId: assistantId,
                  doctorLabel: doctorLabel,
                  assistantLabel: assistantLabel,
                  ownerLabel: ownerLabel,
                  onEdit: (doc, data) =>
                      _openEditFormDialog(context, doc, data, patientData),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaiementsTab({
    required BuildContext context,
    required ColorScheme scheme,
    required Map<String, dynamic> patientData,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
    required double? totalVersements,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final reglement = ReglementSummary(
                reglement: Reglement.fromPatient(patientData),
              );
              final seances = SeancesSummary(
                seances: Seances.fromPatient(patientData),
              );
              if (c.maxWidth < 560) {
                return Column(
                  children: [reglement, const SizedBox(height: 12), seances],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: reglement),
                  const SizedBox(width: 12),
                  Expanded(child: seances),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Un flux dédié aux versements de ce patient, pas `dossierFlux` :
          // celui-ci ouvre en plus un listener sur les formulaires du
          // patient, jamais lus ici.
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: ApiService.instance.versementsFlux(patientId: patientId),
            builder: (context, versSnap) {
              final sous = (versSnap.data ?? const [])
                  .map(
                    (d) => Versement.fromMap(
                      Map<String, dynamic>.from(d),
                      id: (d['id'] ?? '').toString(),
                    ),
                  )
                  .toList();
              final tous = fusionnerVersements(
                sousCollection: sous,
                tableauHerite: patientData['versements'],
              );
              return _buildVersementsCard(
                context: context,
                versements: tous
                    .map(
                      (v) => <String, dynamic>{
                        'montant': v.montant,
                        if (v.date != null) 'createdAt': v.date,
                        'auteurProfileId': v.auteurProfileId,
                      },
                    )
                    .toList(),
                totalVersements: totalVersements ?? 0,
                ownerProfileId: ownerProfileId,
                doctorId: doctorId,
                assistantId: assistantId,
                doctorLabel: doctorLabel,
                assistantLabel: assistantLabel,
                ownerLabel: ownerLabel,
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Le prix est un geste du medecin, pris au moment ou il
              // cloture sa consultation (etape "Cloture" de
              // ConsultationPage) — l'assistant encaisse le montant ainsi
              // fixe, il ne le decide pas. Ce bouton (qui permettait de
              // fixer le prix a la main) reste reserve au medecin/principal
              // comme outil de correction ; a l'assistant, seul le resume
              // en lecture seule ci-dessus reste visible.
              if (canAddDoctorForm)
                _pillAction(
                  context,
                  Icons.payment,
                  'Reglement',
                  onPressed: () => _openReglementDialog(context, patientData),
                ),
              _pillAction(
                context,
                Icons.local_hospital,
                'Seance',
                onPressed: () => _openSeanceDialog(context, patientData),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfosTab({
    required BuildContext context,
    required ColorScheme scheme,
    required Map<String, dynamic> patientData,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
  }) {
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 18,
      color: scheme.onSurface,
    );
    final contentStyle = TextStyle(
      fontSize: 15,
      height: 1.35,
      color: scheme.onSurface,
    );

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService().patientForms(
        parentUid: parentUid,
        profileId: ownerProfileId,
        patientId: patientId,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final medForms = all.where((doc) {
          final type = (doc['type'] ?? '').toString().toLowerCase();
          return type.contains('medecin') || type.contains('assistant');
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canAddDoctorForm || canAddForm) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canAddDoctorForm)
                      FluentButton(
                        label: 'Formulaire medecin',
                        icon: Icons.medical_services_outlined,
                        onPressed: () => _addDoctorForm(context),
                      ),
                    if (canAddForm)
                      FluentButton(
                        label: 'Ajouter un formulaire',
                        icon: Icons.note_add,
                        onPressed: () => _addForm(context),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (medForms.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Aucun formulaire medical',
                      style: TextStyle(color: AppTheme.ink2(context)),
                    ),
                  ),
                )
              else
                _renderFormGroups(
                  medForms,
                  titleStyle,
                  contentStyle,
                  patientData,
                  context: context,
                  ownerProfileId: ownerProfileId,
                  doctorId: doctorId,
                  assistantId: assistantId,
                  doctorLabel: doctorLabel,
                  assistantLabel: assistantLabel,
                  ownerLabel: ownerLabel,
                  onEdit: (doc, data) =>
                      _openEditFormDialog(context, doc, data, patientData),
                ),
            ],
          ),
        );
      },
    );
  }

  double? _parseDouble(dynamic value) => asDoubleOrNull(value);

  int? _parseInt(dynamic value) => asIntOrNull(value);

  String _formatMoneyLocal(double value) {
    final isInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(isInt ? 0 : 2);
  }

  List<Map<String, dynamic>> _normalizeVersements(dynamic raw) {
    if (raw is! List) return [];
    final list = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      final montantRaw = data['montant'];
      double? montant;
      if (montantRaw is num) {
        montant = montantRaw.toDouble();
      } else {
        final parsed = double.tryParse(
          montantRaw?.toString().replaceAll(',', '.') ?? '',
        );
        montant = parsed;
      }
      if (montant == null) continue;
      data['montant'] = montant;
      list.add(data);
    }
    list.sort(
      (a, b) => _asDate(b['createdAt']).compareTo(_asDate(a['createdAt'])),
    );
    return list;
  }

  // asDateOrNull accepte l'ISO du backend comme les Timestamp encore
  // presents dans les donnees importees.
  DateTime _asDate(dynamic value) =>
      asDateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _formatDateTime(dynamic value) {
    final date = _asDate(value);
    if (date.millisecondsSinceEpoch == 0) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _resolveVersementAuteurLabel(
    Map<String, dynamic> entry, {
    required String ownerProfileId,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
  }) {
    final stored = (entry['auteurName'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final auteurId = (entry['auteurProfileId'] ?? '').toString().trim();
    if (auteurId.isEmpty) return '';
    if (auteurId == ownerProfileId && ownerLabel.isNotEmpty) return ownerLabel;
    if (auteurId == doctorId && doctorLabel.isNotEmpty) return doctorLabel;
    if (auteurId == assistantId && assistantLabel.isNotEmpty)
      return assistantLabel;
    if (auteurId == 'medecin_principal') return 'Medecin principal';
    return auteurId;
  }

  Widget _buildVersementsCard({
    required BuildContext context,
    required List<Map<String, dynamic>> versements,
    required double totalVersements,
    required String ownerProfileId,
    required String doctorId,
    required String assistantId,
    required String doctorLabel,
    required String assistantLabel,
    required String ownerLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? scheme.surfaceVariant.withOpacity(0.5)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    final shadowColor = Colors.black.withOpacity(isDark ? 0.3 : 0.08);
    final textMuted = scheme.onSurface.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.payments_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Versements',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'DA ${_formatMoneyLocal(totalVersements)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (versements.isEmpty)
            Text('Aucun versement', style: TextStyle(color: textMuted))
          else
            ...List.generate(versements.length, (index) {
              final entry = versements[index];
              final montant = (entry['montant'] as double?) ?? 0;
              final dateLabel = _formatDateTime(entry['createdAt']);
              final auteurLabel = _resolveVersementAuteurLabel(
                entry,
                ownerProfileId: ownerProfileId,
                doctorId: doctorId,
                assistantId: assistantId,
                doctorLabel: doctorLabel,
                assistantLabel: assistantLabel,
                ownerLabel: ownerLabel,
              );
              final details = [
                if (dateLabel.isNotEmpty) dateLabel,
                if (auteurLabel.isNotEmpty) 'Par: $auteurLabel',
              ].join(' | ');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0) Divider(height: 16, color: borderColor),
                  Text(
                    'DA ${_formatMoneyLocal(montant)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  String _doctorNameFromData(Map<String, dynamic> patientData) {
    final name =
        (patientData['assignedMedecinName'] ?? patientData['doctorName'] ?? '')
            .toString()
            .trim();
    return name;
  }

  String _assistantNameFromData(Map<String, dynamic> patientData) {
    final name = (patientData['assistantName'] ?? '').toString().trim();
    return name;
  }

  String _resolveOwnerLabel(
    String ownerProfileId,
    String doctorId,
    String assistantId,
    String doctorLabel,
    String assistantLabel,
  ) {
    if (ownerProfileId == assistantId && assistantLabel.isNotEmpty) {
      return assistantLabel;
    }
    if (ownerProfileId == doctorId && doctorLabel.isNotEmpty) {
      return doctorLabel;
    }
    if (ownerProfileId == 'medecin_principal') {
      return 'Medecin principal';
    }
    return '';
  }

  String _resolveAuteurNameForCurrent(Map<String, dynamic> patientData) {
    final doctorId = (patientData['doctorId'] ?? '').toString().trim();
    final assistantId = (patientData['assistantId'] ?? '').toString().trim();
    final doctorName = _doctorNameFromData(patientData);
    final assistantName = _assistantNameFromData(patientData);
    if (ownerProfileId == assistantId && assistantName.isNotEmpty) {
      return assistantName;
    }
    if (ownerProfileId == doctorId && doctorName.isNotEmpty) {
      return doctorName;
    }
    if (ownerProfileId == 'medecin_principal') {
      return 'Medecin principal';
    }
    return '';
  }

  Widget _pillAction(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = scheme.primary;
    final bg = tint.withOpacity(isDark ? 0.24 : 0.12);
    final border = tint.withOpacity(isDark ? 0.5 : 0.35);

    return ActionChip(
      avatar: Icon(icon, size: 18, color: tint),
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      label: Text(
        label,
        style: TextStyle(color: tint, fontWeight: FontWeight.w600),
      ),
      onPressed:
          onPressed ??
          () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$label non disponible')));
          },
    );
  }

  Future<void> _openReglementDialog(
    BuildContext context,
    Map<String, dynamic> patientData,
  ) async {
    final currentPrix = _parseDouble(patientData['prix']);
    final initialPrix = currentPrix == null
        ? ''
        : currentPrix.toStringAsFixed(
            currentPrix.truncateToDouble() == currentPrix ? 0 : 2,
          );
    final prixCtrl = TextEditingController(text: initialPrix);

    // Le tarif d'une seance, distinct du total du. Le medecin le retrouve
    // prerempli a la cloture d'une consultation ; l'assistant le fixe ici,
    // au moment ou il annonce le prix au patient.
    final tarif = _parseDouble(patientData['prixSeance']);
    final tarifCtrl = TextEditingController(
      text: tarif == null
          ? ''
          : tarif.toStringAsFixed(tarif.truncateToDouble() == tarif ? 0 : 2),
    );

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reglement'),
        content: _scrollableDialogContent(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentPrix != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Total actuel: DA ${initialPrix.isEmpty ? '0' : initialPrix}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              TextField(
                controller: prixCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Total a payer',
                  prefixText: 'DA ',
                  helperText: 'Ce que le patient doit en tout',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tarifCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tarif d’une seance',
                  prefixText: 'DA ',
                  helperText: 'Propose a la cloture, et ajoute au total',
                ),
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

    if (res != true) {
      libererApresFermeture([prixCtrl, tarifCtrl]);
      return;
    }

    final raw = prixCtrl.text.replaceAll(',', '.').trim();
    final montant = double.tryParse(raw);
    // Un tarif vide efface le tarif : c'est un choix explicite, pas un oubli.
    final brutTarif = tarifCtrl.text.replaceAll(',', '.').trim();
    final nouveauTarif = brutTarif.isEmpty ? null : double.tryParse(brutTarif);
    final tarifInvalide = brutTarif.isNotEmpty && nouveauTarif == null;
    libererApresFermeture([prixCtrl, tarifCtrl]);

    if (tarifInvalide) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarif de seance invalide')),
        );
      }
      return;
    }
    if (montant == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Montant invalide')));
      }
      return;
    }

    try {
      await _updatePatientCopies(patientData, {
        'prix': montant,
        'prixSeance': nouveauTarif,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reglement mis a jour')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise a jour')),
        );
      }
    }
  }

  Future<void> _openSeanceDialog(
    BuildContext context,
    Map<String, dynamic> patientData,
  ) async {
    final currentTotal = _parseInt(patientData['nombreSeances']);
    final seancesCtrl = TextEditingController(
      text: currentTotal?.toString() ?? '',
    );

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Seances'),
        content: _scrollableDialogContent(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentTotal != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Total actuel: $currentTotal',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              TextField(
                controller: seancesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nombre de seances',
                ),
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

    if (res != true) {
      libererApresFermeture([seancesCtrl]);
      return;
    }

    final raw = seancesCtrl.text.trim();
    final total = int.tryParse(raw);
    libererApresFermeture([seancesCtrl]);
    if (total == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nombre invalide')));
      }
      return;
    }

    try {
      await _updatePatientCopies(patientData, {'nombreSeances': total});
      try {
        await _updateWaitingSeances(total);
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Seances mises a jour')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise a jour')),
        );
      }
    }
  }

  Future<void> _openInfosMedicalesDialog(
    BuildContext context,
    Map<String, dynamic> patientData,
  ) async {
    const sexes = ['', 'Homme', 'Femme'];
    const groupesSanguins = [
      '',
      'A+',
      'A-',
      'B+',
      'B-',
      'AB+',
      'AB-',
      'O+',
      'O-',
    ];

    var sexe = (patientData['sexe'] ?? '').toString();
    if (!sexes.contains(sexe)) sexe = '';
    var groupeSanguin = (patientData['groupeSanguin'] ?? '').toString();
    if (!groupesSanguins.contains(groupeSanguin)) groupeSanguin = '';

    final adresseCtrl = TextEditingController(
      text: (patientData['adresse'] ?? '').toString(),
    );
    final allergiesCtrl = TextEditingController(
      text: (patientData['allergies'] ?? '').toString(),
    );
    final contactNomCtrl = TextEditingController(
      text: (patientData['contactUrgenceNom'] ?? '').toString(),
    );
    final contactTelCtrl = TextEditingController(
      text: (patientData['contactUrgenceTel'] ?? '').toString(),
    );

    final res = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Informations médicales'),
            content: _scrollableDialogContent(
              context,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: sexe,
                    decoration: const InputDecoration(labelText: 'Sexe'),
                    items: sexes
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.isEmpty ? 'Non renseigné' : s),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => sexe = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: groupeSanguin,
                    decoration: const InputDecoration(
                      labelText: 'Groupe sanguin',
                    ),
                    items: groupesSanguins
                        .map(
                          (g) => DropdownMenuItem(
                            value: g,
                            child: Text(g.isEmpty ? 'Non renseigné' : g),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => groupeSanguin = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: adresseCtrl,
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: allergiesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Allergies',
                      hintText: 'Ex : pénicilline, iode…',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactNomCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Contact urgence — nom',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactTelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Contact urgence — téléphone',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );

    if (res != true) {
      libererApresFermeture([
        adresseCtrl,
        allergiesCtrl,
        contactNomCtrl,
        contactTelCtrl,
      ]);
      return;
    }

    final updates = {
      'sexe': sexe,
      'groupeSanguin': groupeSanguin,
      'adresse': adresseCtrl.text.trim(),
      'allergies': allergiesCtrl.text.trim(),
      'contactUrgenceNom': contactNomCtrl.text.trim(),
      'contactUrgenceTel': contactTelCtrl.text.trim(),
    };
    libererApresFermeture([
      adresseCtrl,
      allergiesCtrl,
      contactNomCtrl,
      contactTelCtrl,
    ]);

    try {
      await _updatePatientCopies(patientData, updates);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informations médicales mises à jour')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    }
  }

  /// Enregistre une modification du dossier.
  ///
  /// Le batch ecrivait sur les trois copies — profil courant, medecin,
  /// assistant — parce que Firestore n'avait pas de document unique. Le nom
  /// reste le temps que ses appelants soient relus ; il n'y a plus qu'un
  /// dossier a mettre a jour.
  Future<void> _updatePatientCopies(
    Map<String, dynamic> patientData,
    Map<String, dynamic> updates,
  ) async {
    await ApiService.instance.majPatient(patientId, updates);
  }

  /// Reporte le forfait sur l'entree de salle d'attente ouverte.
  ///
  /// La methode ecrivait sur trois copies de chaque entree — profil,
  /// medecin principal, medecin — en sautant celles deja closes. Le forfait
  /// vit sur le dossier, que la file lit : il n'y a plus rien a recopier.
  Future<void> _updateWaitingSeances(int total) async {
    await ApiService.instance.majPatient(patientId, {'nombreSeances': total});
  }

  Future<void> _addForm(BuildContext context) async {
    final ctrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'Note');
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau formulaire'),
        content: _scrollableDialogContent(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeCtrl,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Contenu',
                  alignLabelWithHint: true,
                ),
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

    final data = <String, dynamic>{
      'type': typeCtrl.text.trim().isEmpty ? 'Note' : typeCtrl.text.trim(),
      'contenu': ctrl.text.trim(),
      'auteurProfileId': ownerProfileId,
      'patientId': patientId,
    };

    try {
      // Ce bloc verifiait l'existence du dossier, puis construisait une
      // liste de references — profil courant, medecin, assistant — pour
      // ecrire le meme formulaire sous chacune. Le backend refuse un
      // patient inconnu et n'ecrit qu'un document.
      final patientData = await ApiService.instance.patient(patientId);
      final auteurName = _resolveAuteurNameForCurrent(patientData);
      if (auteurName.isNotEmpty) {
        data['auteurName'] = auteurName;
      }

      await ApiService.instance.creerDocument(data);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Formulaire ajouté')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de l\'ajout du formulaire'),
          ),
        );
      }
    }
  }

  Future<void> _addDoctorForm(
    BuildContext context, {
    Map<String, dynamic>? patientData,
  }) async {
    final resolvedPatient = patientData ?? await _fetchPatientData();
    final prototypeFields = await resolveMotifPrototypeFields(resolvedPatient);
    final auteurName = _resolveAuteurNameForCurrent(resolvedPatient);
    if (prototypeFields.isNotEmpty) {
      await _addDoctorFormPrototype(
        context,
        prototypeFields,
        auteurName: auteurName,
      );
      return;
    }

    final pathologiesCtrl = TextEditingController();
    final allergiesCtrl = TextEditingController();
    final digestifsCtrl = TextEditingController();
    final sommeilCtrl = TextEditingController();
    final activiteCtrl = TextEditingController();
    final tabacCtrl = TextEditingController();
    final repasCtrl = TextEditingController();
    final organisationCtrl = TextEditingController();
    final goutsCtrl = TextEditingController();
    final hydratationCtrl = TextEditingController();
    final journeeCtrl = TextEditingController();
    final poidsActuelCtrl = TextEditingController();
    final tailleCtrl = TextEditingController();
    final imcCtrl = TextEditingController();
    final poidsSouhaiteCtrl = TextEditingController();
    final evolutionPoidsCtrl = TextEditingController();
    final tourTailleCtrl = TextEditingController();
    final imageCorpCtrl = TextEditingController();
    final stressCtrl = TextEditingController();
    final compAlimCtrl = TextEditingController();
    final grignotageCtrl = TextEditingController();
    final compulsionsCtrl = TextEditingController();
    final restrictionsCtrl = TextEditingController();
    final entourageCtrl = TextEditingController();
    final objCourtCtrl = TextEditingController();
    final objLongCtrl = TextEditingController();
    final attentesCtrl = TextEditingController();
    final complementCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Formulaire medecin'),
        content: SizedBox(
          width: AppTheme.dialogWidth(context, 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '3. Antecedents medicaux et chirurgicaux',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: pathologiesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pathologies chroniques',
                  ),
                ),
                TextField(
                  controller: allergiesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Allergies / intolerances',
                  ),
                ),
                TextField(
                  controller: digestifsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Antecedents digestifs',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '4. Habitudes de vie',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: sommeilCtrl,
                  decoration: const InputDecoration(labelText: 'Sommeil'),
                ),
                TextField(
                  controller: activiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Activite physique',
                  ),
                ),
                TextField(
                  controller: tabacCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tabac / alcool / cafeine',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '5. Habitudes alimentaires',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: repasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de repas / jour',
                  ),
                ),
                TextField(
                  controller: organisationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Organisation (lieu, rythme, vitesse)',
                  ),
                ),
                TextField(
                  controller: goutsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gouts / aversions',
                  ),
                ),
                TextField(
                  controller: hydratationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hydratation (quantite, type)',
                  ),
                ),
                TextField(
                  controller: journeeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Exemple journee type',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '6. Etat nutritionnel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                AppField.mesure(
                  controller: poidsActuelCtrl,
                  label: 'Poids actuel',
                  unite: 'kg',
                  icon: Icons.monitor_weight_outlined,
                  validator: v.poids,
                ),
                const SizedBox(height: 10),
                AppField.mesure(
                  controller: tailleCtrl,
                  label: 'Taille',
                  unite: 'cm',
                  icon: Icons.height,
                  validator: v.taille,
                ),
                const SizedBox(height: 10),
                // L'IMC n'est plus saisi : il se déduit des deux champs
                // ci-dessus. `imcCtrl` reste alimenté pour que le code
                // d'enregistrement plus bas continue de fonctionner.
                BmiField(
                  poidsCtrl: poidsActuelCtrl,
                  tailleCtrl: tailleCtrl,
                  syncTo: imcCtrl,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: poidsSouhaiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Poids souhaite (kg)',
                  ),
                ),
                TextField(
                  controller: evolutionPoidsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Evolution du poids',
                  ),
                ),
                TextField(
                  controller: tourTailleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tour de taille / hanche',
                  ),
                ),
                TextField(
                  controller: imageCorpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Image corporelle',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '7. Facteurs psycho-sociaux',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: stressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Stress / anxiete',
                  ),
                ),
                TextField(
                  controller: compAlimCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Comportement alimentaire',
                  ),
                ),
                TextField(
                  controller: grignotageCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Grignotage / compulsions',
                  ),
                ),
                TextField(
                  controller: compulsionsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Compulsions / restrictions',
                  ),
                ),
                TextField(
                  controller: restrictionsCtrl,
                  decoration: const InputDecoration(labelText: 'Restrictions'),
                ),
                TextField(
                  controller: entourageCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Influence entourage',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '8. Objectifs patient',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: objCourtCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Objectifs court terme',
                  ),
                ),
                TextField(
                  controller: objLongCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Objectifs long terme',
                  ),
                ),
                TextField(
                  controller: attentesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Attentes vis-a-vis de la consultation',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '9. Complement',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextField(
                  controller: complementCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'Ozone / acupuncture / cryolipolyse / auriculotherapie',
                  ),
                ),
              ],
            ),
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

    final sections = {
      'pathologies_chroniques': pathologiesCtrl.text.trim(),
      'allergies': allergiesCtrl.text.trim(),
      'antecedents_digestifs': digestifsCtrl.text.trim(),
      'sommeil': sommeilCtrl.text.trim(),
      'activite_physique': activiteCtrl.text.trim(),
      'tabac_alcool_cafeine': tabacCtrl.text.trim(),
      'repas_par_jour': repasCtrl.text.trim(),
      'organisation_repas': organisationCtrl.text.trim(),
      'gouts_aversions': goutsCtrl.text.trim(),
      'hydratation': hydratationCtrl.text.trim(),
      'journee_type': journeeCtrl.text.trim(),
      'poids_actuel': poidsActuelCtrl.text.trim(),
      'taille': tailleCtrl.text.trim(),
      'imc': imcCtrl.text.trim(),
      'poids_souhaite': poidsSouhaiteCtrl.text.trim(),
      'evolution_poids': evolutionPoidsCtrl.text.trim(),
      'tour_taille_hanche': tourTailleCtrl.text.trim(),
      'image_corporelle': imageCorpCtrl.text.trim(),
      'stress_anxiete': stressCtrl.text.trim(),
      'comportement_alimentaire': compAlimCtrl.text.trim(),
      'grignotage': grignotageCtrl.text.trim(),
      'compulsions': compulsionsCtrl.text.trim(),
      'restrictions': restrictionsCtrl.text.trim(),
      'influence_entourage': entourageCtrl.text.trim(),
      'objectifs_court_terme': objCourtCtrl.text.trim(),
      'objectifs_long_terme': objLongCtrl.text.trim(),
      'attentes_consultation': attentesCtrl.text.trim(),
      'complement': complementCtrl.text.trim(),
    };

    final data = <String, dynamic>{
      'type': 'Formulaire medecin',
      'sections': sections,
      'auteurProfileId': ownerProfileId,
      'patientId': patientId,
    };
    if (auteurName.isNotEmpty) {
      data['auteurName'] = auteurName;
    }

    try {
      await ApiService.instance.creerDocument(data);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formulaire medecin enregistre')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'enregistrement")),
        );
      }
    }
  }

  Future<void> _openEditFormDialog(
    BuildContext context,
    Map<String, dynamic> doc,
    Map<String, dynamic> data,
    Map<String, dynamic> patientData,
  ) async {
    final rawType = (data['type'] ?? '').toString();
    final typeCtrl = TextEditingController(text: rawType);
    final sections = (data['sections'] as Map?)?.cast<String, dynamic>();
    final hasSections = sections != null && sections.isNotEmpty;
    final contentCtrl = TextEditingController(
      text: (data['contenu'] ?? '').toString(),
    );
    final sectionCtrls = <String, TextEditingController>{};
    if (hasSections) {
      for (final entry in sections.entries) {
        sectionCtrls[entry.key] = TextEditingController(
          text: entry.value?.toString() ?? '',
        );
      }
    }

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier formulaire'),
        content: SizedBox(
          width: AppTheme.dialogWidth(context, 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                const SizedBox(height: 8),
                if (hasSections)
                  ...sectionCtrls.entries.map(
                    (e) => TextField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: formatLabelGlobal(e.key),
                      ),
                    ),
                  )
                else
                  TextField(
                    controller: contentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Contenu',
                      alignLabelWithHint: true,
                    ),
                  ),
              ],
            ),
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

    if (res != true) {
      libererApresFermeture([typeCtrl, contentCtrl, ...sectionCtrls.values]);
      return;
    }

    final newType = typeCtrl.text.trim().isEmpty
        ? rawType
        : typeCtrl.text.trim();
    // L'horodatage de modification est pose par le serveur.
    final updates = <String, dynamic>{'type': newType};

    if (hasSections) {
      final nextSections = <String, String>{};
      for (final entry in sectionCtrls.entries) {
        nextSections[entry.key] = entry.value.text.trim();
      }
      updates['sections'] = nextSections;
    } else {
      updates['contenu'] = contentCtrl.text.trim();
    }

    libererApresFermeture([typeCtrl, contentCtrl, ...sectionCtrls.values]);

    try {
      await _mettreAJourDocument(doc, updates);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Formulaire mis a jour')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise a jour')),
        );
      }
    }
  }

  /// Met a jour un document medical.
  ///
  /// Cette methode faisait cent lignes. Firestore ecrivait chaque formulaire
  /// sous chaque profil sans identite partagee : pour modifier « le meme »
  /// document, il fallait le retrouver dans les copies en comparant l'auteur,
  /// le type, le contenu et l'horodatage a deux minutes pres, puis ecrire
  /// dans toutes les references trouvees.
  ///
  /// Un document a maintenant un identifiant. Il n'y a plus rien a apparier.
  Future<void> _mettreAJourDocument(
    Map<String, dynamic> doc,
    Map<String, dynamic> updates,
  ) async {
    final id = (doc['id'] ?? '').toString();
    if (id.isEmpty) return;
    await ApiService.instance.majDocument(id, updates);
  }

  Future<Map<String, dynamic>> _fetchPatientData() async {
    try {
      return await ApiService.instance.patient(patientId);
    } catch (_) {
      return {};
    }
  }

  Future<void> _addDoctorFormPrototype(
    BuildContext context,
    List<String> fields, {
    String auteurName = '',
  }) async {
    final controllers = <String, TextEditingController>{};
    for (final f in fields) {
      controllers[f] = TextEditingController();
    }

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Formulaire medecin'),
        content: SizedBox(
          width: AppTheme.dialogWidth(context, 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fields.isEmpty)
                  const Text('Aucun champ defini pour ce motif'),
                ...fields.map(
                  (f) => TextField(
                    controller: controllers[f],
                    decoration: InputDecoration(labelText: f),
                  ),
                ),
              ],
            ),
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

    if (res != true) {
      libererApresFermeture(controllers.values);
      return;
    }

    final sections = <String, String>{};
    for (final f in fields) {
      final key = normalizeSectionKey(f);
      sections[key] = controllers[f]?.text.trim() ?? '';
    }

    libererApresFermeture(controllers.values);

    final data = <String, dynamic>{
      'type': 'Formulaire medecin',
      'sections': sections,
      'auteurProfileId': ownerProfileId,
      'patientId': patientId,
    };
    if (auteurName.isNotEmpty) {
      data['auteurName'] = auteurName;
    }

    try {
      await ApiService.instance.creerDocument(data);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formulaire medecin enregistre')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'enregistrement")),
        );
      }
    }
  }
}

Map<String, String> _fallbackFields(Map<String, dynamic> data) {
  final ignored = {
    'id',
    'type',
    'sections',
    'createdAt',
    'auteurProfileId',
    'patientId',
    'parentUid',
    'contenu',
    'prescriptions',
    'examens',
    'doctorName',
    'doctorNameAr',
    'doctorSubtitle',
    'doctorWilaya',
    'doctorAddress',
    'doctorPhone',
    'patientNom',
    'patientPrenom',
    'patientAge',
    'dateStr',
    'note_de_seance',
    'noteSeance',
  };
  final result = <String, String>{};
  data.forEach((key, value) {
    if (ignored.contains(key)) return;
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty) return;
    result[key] = v;
  });
  return result;
}

/// Carte des informations médicales du patient : allergies, groupe
/// sanguin, sexe, adresse, contact d'urgence.
///
/// Les allergies s'affichent à part, dans une bannière colorée — c'est une
/// information de sécurité, elle doit sauter aux yeux, pas se lire comme
/// une ligne parmi d'autres dans une grille grise.
class _InfosMedicalesCard extends StatelessWidget {
  final String sexe;
  final String groupeSanguin;
  final String adresse;
  final String allergies;
  final String contactUrgenceNom;
  final String contactUrgenceTel;
  final VoidCallback onModifier;

  const _InfosMedicalesCard({
    required this.sexe,
    required this.groupeSanguin,
    required this.adresse,
    required this.allergies,
    required this.contactUrgenceNom,
    required this.contactUrgenceTel,
    required this.onModifier,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final corail = AppTheme.corail(context);
    final contact = [
      contactUrgenceNom,
      contactUrgenceTel,
    ].where((s) => s.isNotEmpty).join(' · ');

    final infos = <InfoPair>[
      if (sexe.isNotEmpty) InfoPair(label: 'Sexe', value: sexe),
      if (groupeSanguin.isNotEmpty)
        InfoPair(
          label: 'Groupe sanguin',
          value: groupeSanguin,
          icon: Icons.bloodtype_outlined,
        ),
      if (adresse.isNotEmpty)
        InfoPair(label: 'Adresse', value: adresse, icon: Icons.home_outlined),
      if (contact.isNotEmpty)
        InfoPair(
          label: 'Contact urgence',
          value: contact,
          icon: Icons.emergency_outlined,
        ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.7)),
        boxShadow: AppTheme.shadow(context, strength: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Informations médicales',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onModifier,
              ),
            ],
          ),
          if (allergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: corail.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppTheme.rButton),
                border: Border.all(color: corail.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: corail, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALLERGIES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: corail,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          allergies,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color.lerp(corail, scheme.onSurface, 0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (infos.isNotEmpty) ...[
            const SizedBox(height: 14),
            InfoGrid(items: infos, minColumnWidth: 140),
          ],
          if (infos.isEmpty && allergies.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Aucune information médicale renseignée.',
              style: TextStyle(
                color: AppTheme.ink2(context),
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  final String name;
  final String prenom;
  final String tel;
  final String email;
  final String motif;
  final String origine;
  final String age;
  final String medecin;
  final String assistant;
  final double? prix;
  final double? versementsTotal;
  final int? seancesTotal;
  final int? seancesDone;
  final dynamic createdAt;

  const _PatientHeader({
    required this.name,
    required this.prenom,
    required this.tel,
    required this.email,
    required this.motif,
    required this.origine,
    required this.age,
    required this.medecin,
    required this.assistant,
    this.prix,
    this.versementsTotal,
    this.seancesTotal,
    this.seancesDone,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nomComplet = '$name $prenom'.trim();

    // Les montants et les seances ne figurent plus ici : ils ont leurs
    // propres cartes calculees juste en dessous. Les repeter en pastilles
    // dupliquait l'information et noyait l'identite du patient.
    final identite = <InfoPair>[
      if (age.isNotEmpty) InfoPair(label: 'Age', value: '$age ans'),
      if (medecin.isNotEmpty)
        InfoPair(
          label: 'Medecin',
          value: medecin,
          icon: Icons.medical_services_outlined,
        ),
      if (assistant.isNotEmpty)
        InfoPair(
          label: 'Assistant',
          value: assistant,
          icon: Icons.support_agent_outlined,
        ),
      if (origine.isNotEmpty)
        InfoPair(
          label: 'Origine',
          value: fmt.capitalize(fmt.humanize(origine)),
          icon: Icons.travel_explore_outlined,
        ),
      if (createdAt != null)
        InfoPair(
          label: 'Dossier cree',
          value: fmt.date(createdAt),
          icon: Icons.event_outlined,
        ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.7)),
        boxShadow: AppTheme.shadow(context, strength: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identite : pastille d'initiales, nom, motifs. Le motif qualifie
          // la venue, il monte au niveau du nom au lieu de flotter dans un
          // coin de la carte.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(nom: name, prenom: prenom, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomComplet.isEmpty ? 'Patient' : nomComplet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        height: 1.15,
                      ),
                    ),
                    if (motif.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: motif
                            .split(',')
                            .map((m) => m.trim())
                            .where((m) => m.isNotEmpty)
                            .map((m) => _MotifPill(motif: m))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Contacts cliquables plutot que decoratifs : un numero affiche
          // dans un cabinet sert a etre appele.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ContactPill(
                icon: Icons.call_outlined,
                label: tel.isEmpty ? 'Aucun telephone' : fmt.phone(tel),
                actif: tel.isNotEmpty,
                uri: tel.isEmpty ? null : Uri.parse('tel:$tel'),
              ),
              _ContactPill(
                icon: Icons.mail_outline,
                label: email.isEmpty ? 'Aucun e-mail' : email,
                actif: email.isNotEmpty,
                uri: email.isEmpty ? null : Uri.parse('mailto:$email'),
              ),
            ],
          ),
          if (identite.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(color: scheme.outline.withValues(alpha: 0.6), height: 1),
            const SizedBox(height: 16),
            InfoGrid(items: identite, minColumnWidth: 140),
          ],
        ],
      ),
    );
  }
}

/// Pastille de motif de consultation.
class _MotifPill extends StatelessWidget {
  final String motif;

  const _MotifPill({required this.motif});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final libelle = fmt.capitalize(
      fmt.humanize(motif.startsWith('autre:') ? motif.substring(6) : motif),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.secondary.withValues(alpha: 0.16),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Text(
        libelle,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Color.lerp(scheme.secondary, scheme.onSurface, 0.3),
        ),
      ),
    );
  }
}

/// Pastille de contact : affiche l'information et declenche l'action.
class _ContactPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool actif;
  final Uri? uri;

  const _ContactPill({
    required this.icon,
    required this.label,
    required this.actif,
    this.uri,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = actif
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.4);

    final contenu = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: actif
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.08),
                scheme.surface,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        border: Border.all(
          color: actif
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: couleur),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: actif ? FontWeight.w600 : FontWeight.w400,
              fontStyle: actif ? FontStyle.normal : FontStyle.italic,
              color: actif
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );

    final cible = uri;
    if (!actif || cible == null) return contenu;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(cible, mode: LaunchMode.externalApplication),
        child: contenu,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;

  /// Texte affiché quand [value] est vide. Évite de propager des
  /// « Non renseigne » en dur dans chaque appel.
  final String fallback;

  const _MetricCard({
    required this.label,
    required this.value,
    this.suffix,
    this.fallback = 'Non renseigné',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? scheme.surfaceVariant.withOpacity(0.5)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    final shadowColor = Colors.black.withOpacity(isDark ? 0.3 : 0.08);
    final labelColor = scheme.onSurface.withOpacity(0.65);

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.trim().isEmpty
                ? fallback
                : (suffix == null ? value : '$value $suffix'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateHeader(dynamic ts) {
  final d = asDateOrNull(ts);
  if (d == null) return ts?.toString() ?? '';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

Widget _renderFormGroups(
  List<Map<String, dynamic>> docs,
  TextStyle titleStyle,
  TextStyle contentStyle,
  Map<String, dynamic> patientData, {
  required BuildContext context,
  required String ownerProfileId,
  required String doctorId,
  required String assistantId,
  required String doctorLabel,
  required String assistantLabel,
  required String ownerLabel,
  required void Function(Map<String, dynamic> doc, Map<String, dynamic> data)
  onEdit,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textMuted = scheme.onSurface.withOpacity(0.6);
  final cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      scheme.surface,
      scheme.surfaceVariant.withOpacity(isDark ? 0.65 : 0.5),
    ],
  );
  final borderColor = isDark
      ? Colors.white.withOpacity(0.08)
      : Colors.black.withOpacity(0.08);
  final shadowColor = Colors.black.withOpacity(isDark ? 0.35 : 0.1);

  // asDateOrNull accepte l'ISO du backend comme les Timestamp encore
  // presents dans les donnees importees.
  final sorted = [...docs]
    ..sort((a, b) {
      final at =
          asDateOrNull(a['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bt =
          asDateOrNull(b['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });

  // La classification par type vivait ici — quatre listes, une par famille de
  // document. Le regroupement par visite l'a rendue inutile : `TypeDocument`
  // s'en charge, et il n'y a plus de liste a maintenir.

  final patientBasics = _patientBasics(
    patientData,
    doctorLabel: doctorLabel,
    assistantLabel: assistantLabel,
  );
  final patientDetails = _patientFullFields(
    patientData,
    doctorLabel: doctorLabel,
    assistantLabel: assistantLabel,
  );

  bool canEditForm(Map<String, dynamic> doc, Map<String, dynamic> data) {
    final auteur = (data['auteurProfileId'] ?? '').toString();
    if (auteur.isEmpty || auteur != ownerProfileId) return false;
    // Une ordonnance et un bilan sont des pieces remises au patient : les
    // rouvrir apres coup ferait diverger le papier et le dossier.
    final type = (data['type'] ?? '').toString().toLowerCase();
    if (type.contains('ordonnance') || type.contains('bilan')) return false;
    // Il y avait ici un second controle, sur le chemin Firestore du
    // document : il verifiait que la copie modifiee etait bien celle du
    // profil courant. Sans duplication, ce chemin n'existe plus, et
    // l'appartenance se lit deja dans `auteurProfileId` ci-dessus.
    return true;
  }

  String resolveAuteurLabel(Map<String, dynamic> data) {
    final stored = (data['auteurName'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    final auteurId = (data['auteurProfileId'] ?? '').toString();
    if (auteurId.isEmpty) return '';
    if (auteurId == ownerProfileId && ownerLabel.isNotEmpty) return ownerLabel;
    if (auteurId == doctorId && doctorLabel.isNotEmpty) return doctorLabel;
    if (auteurId == assistantId && assistantLabel.isNotEmpty)
      return assistantLabel;
    if (auteurId == 'medecin_principal') return 'Medecin principal';
    return auteurId;
  }

  int? _formSeanceNumero(Map<String, dynamic> data) {
    final candidates = [
      data['seanceNumero'],
      data['seance_numero'],
      data['numeroSeance'],
      data['seanceNumber'],
    ];
    for (final raw in candidates) {
      if (raw == null) continue;
      if (raw is num) return raw.toInt();
      final parsed = int.tryParse(raw.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  String _formDateLabel(Map<String, dynamic> data) {
    final dateStr = (data['dateStr'] ?? '').toString().trim();
    if (dateStr.isNotEmpty) return dateStr;
    final created = data['createdAt'];
    final fallback = _formatDateHeader(created);
    return fallback;
  }

  String _formMetaLine(Map<String, dynamic> data) {
    final dateLabel = _formDateLabel(data);
    final seanceNum = _formSeanceNumero(data);
    final seanceLabel = seanceNum?.toString() ?? '';
    if (dateLabel.isEmpty && seanceLabel.isEmpty) return '';
    if (seanceLabel.isEmpty) return 'Date: $dateLabel';
    if (dateLabel.isEmpty) return 'Seance: $seanceLabel';
    return 'Date: $dateLabel | Seance: $seanceLabel';
  }

  Widget buildFormCard(
    Map<String, dynamic> doc, {
    required String title,
    required Map<String, String> fallbackFields,
    required String emptyLabel,
    bool allowEdit = true,
    String? metaLine,
  }) {
    final data = doc;
    final formType = (data['type'] ?? '').toString().toLowerCase();
    final noteDeSeance = (data['note_de_seance'] ?? data['noteSeance'] ?? '')
        .toString()
        .trim();
    final hasOrdonnanceNote =
        formType.contains('ordonnance') && noteDeSeance.isNotEmpty;
    final sections = (data['sections'] as Map?)?.cast<String, dynamic>();
    final auteurLabel = resolveAuteurLabel(data);
    final extra = _fallbackFields(data);
    final meta = metaLine?.trim() ?? '';
    final canEdit = allowEdit && canEditForm(doc, data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        title: Text(title, style: titleStyle.copyWith(fontSize: 17)),
        subtitle: sections != null && sections.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (auteurLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Auteur : $auteurLabel',
                        style: TextStyle(fontSize: 13, color: textMuted),
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        meta,
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ),
                  if (hasOrdonnanceNote)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, top: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.secondary.withOpacity(
                          isDark ? 0.22 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.secondary.withOpacity(
                            isDark ? 0.55 : 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: scheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Note de seance: $noteDeSeance',
                              style: contentStyle.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...sections.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${formatLabelGlobal(e.key)} : ${e.value ?? ''}',
                        style: contentStyle,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (auteurLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Auteur : $auteurLabel',
                        style: TextStyle(fontSize: 13, color: textMuted),
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        meta,
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ),
                  if (hasOrdonnanceNote)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, top: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.secondary.withOpacity(
                          isDark ? 0.22 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.secondary.withOpacity(
                            isDark ? 0.55 : 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: scheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Note de seance: $noteDeSeance',
                              style: contentStyle.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((data['contenu'] ?? '').toString().isNotEmpty)
                    Text(data['contenu'], style: contentStyle),
                  if (extra.isNotEmpty)
                    ...extra.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${formatLabelGlobal(e.key)} : ${e.value}',
                          style: contentStyle,
                        ),
                      ),
                    ),
                  if (extra.isEmpty &&
                      (data['contenu'] ?? '').toString().isEmpty &&
                      fallbackFields.isNotEmpty)
                    ...fallbackFields.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${formatLabelGlobal(e.key)} : ${e.value}',
                          style: contentStyle,
                        ),
                      ),
                    ),
                  if ((data['contenu'] ?? '').toString().isEmpty &&
                      extra.isEmpty)
                    Text(emptyLabel, style: contentStyle),
                ],
              ),
        trailing: canEdit
            ? IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit),
                onPressed: () => onEdit(doc, data),
              )
            : null,
      ),
    );
  }

  // Le dossier groupait par type : les ordonnances derriere un bouton
  // « Afficher ordonnances (3) », les formulaires medecin dans une liste, les
  // notes dans une autre. Repondre a « qu'ai-je fait le 3 mars ? » demandait
  // de parcourir quatre listes et de recouper les dates de tete.
  //
  // Un dossier medical se lit par visite. `buildFormCard` est conserve tel
  // quel : seule l'organisation change, pas l'affichage d'un document.
  final visites = grouperEnVisites(sorted);

  if (visites.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          'Aucun document pour ce patient.',
          style: TextStyle(fontStyle: FontStyle.italic, color: textMuted),
        ),
      ),
    );
  }

  Widget carteDe(Map<String, dynamic> data) {
    final type = TypeDocument.depuis(data['type']);
    return buildFormCard(
      data,
      title: type == TypeDocument.note
          ? ((data['type'] ?? 'Note').toString().trim().isEmpty
                ? 'Note'
                : (data['type']).toString())
          : type.libelle,
      fallbackFields: type == TypeDocument.formulaire
          ? patientBasics
          : patientDetails,
      emptyLabel: type.libelle,
      // Une ordonnance et un bilan sont des pieces remises au patient : les
      // rouvrir apres coup ferait diverger le papier et le dossier.
      allowEdit: type != TypeDocument.ordonnance && type != TypeDocument.bilan,
      metaLine: _formMetaLine(data),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < visites.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: cardGradient,
              borderRadius: BorderRadius.circular(AppTheme.rCard),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rCard),
              child: Theme(
                // ExpansionTile trace ses propres lignes de separation, qui
                // doublent la bordure de la carte.
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  // La visite la plus recente est ouverte : c'est celle qu'on
                  // vient chercher neuf fois sur dix.
                  initiallyExpanded: i == 0,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: _EnteteVisite(visite: visites[i]),
                  children: [for (final d in visites[i].documents) carteDe(d)],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// L'en-tete d'une visite : quand, laquelle, et ce qu'elle a produit.
///
/// Le resume permet de lire une journee sans la deplier — c'est ce qui evite
/// d'ouvrir six visites pour retrouver une ordonnance.
class _EnteteVisite extends StatelessWidget {
  final Visite visite;

  const _EnteteVisite({required this.visite});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (visite.numero > 0)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.14),
                    scheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'Visite ${visite.numero}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: Color.lerp(scheme.primary, scheme.onSurface, 0.25),
                  ),
                ),
              ),
            Expanded(
              child: Text(
                visite.sansDate
                    ? 'Date inconnue'
                    : fmt.capitalize(fmt.relativeDay(visite.date)),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (!visite.sansDate)
              Text(
                fmt.date(visite.date),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
          ],
        ),
        if (visite.resume.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            visite.resume.join('  ·  '),
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );
  }
}

String formatLabelGlobal(String raw) {
  if (raw.isEmpty) return '';
  final cleaned = raw.replaceAll('_', ' ');
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

Map<String, String> _patientFullFields(
  Map<String, dynamic> patientData, {
  String? doctorLabel,
  String? assistantLabel,
}) {
  final resolvedDoctor = (doctorLabel != null && doctorLabel.trim().isNotEmpty)
      ? doctorLabel
      : (patientData['assignedMedecinName'] ?? patientData['doctorId']);
  final doctorDisplay =
      (resolvedDoctor?.toString().trim() ?? '') == 'medecin_principal'
      ? 'Medecin principal'
      : (resolvedDoctor?.toString() ?? '');
  final resolvedAssistant =
      (assistantLabel != null && assistantLabel.trim().isNotEmpty)
      ? assistantLabel
      : (patientData['assistantName'] ?? patientData['assistantId']);
  final fields = <String, dynamic>{
    'nom': patientData['nom'],
    'prenom': patientData['prenom'],
    'age': patientData['age'],
    'telephone': patientData['tel'],
    'email': patientData['email'],
    'motif': patientData['motif'],
    'origine': patientData['origine'],
    'medecin': doctorDisplay,
    'assistant': resolvedAssistant,
  };
  final result = <String, String>{};
  fields.forEach((k, v) {
    final val = v?.toString().trim() ?? '';
    if (val.isEmpty) return;
    result[k] = val;
  });
  return result;
}

Map<String, String> _patientBasics(
  Map<String, dynamic> patientData, {
  String? doctorLabel,
  String? assistantLabel,
}) {
  final result = <String, String>{};
  void add(String key, dynamic value) {
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty) return;
    result[key] = v;
  }

  final resolvedDoctor = (doctorLabel != null && doctorLabel.trim().isNotEmpty)
      ? doctorLabel
      : (patientData['assignedMedecinName'] ?? patientData['doctorId']);
  final doctorDisplay =
      (resolvedDoctor?.toString().trim() ?? '') == 'medecin_principal'
      ? 'Medecin principal'
      : (resolvedDoctor?.toString() ?? '');
  final resolvedAssistant =
      (assistantLabel != null && assistantLabel.trim().isNotEmpty)
      ? assistantLabel
      : (patientData['assistantName'] ?? patientData['assistantId']);

  add('telephone', patientData['tel']);
  add('email', patientData['email']);
  add('motif', patientData['motif']);
  add('origine', patientData['origine']);
  add('age', patientData['age']);
  add('medecin', doctorDisplay);
  add('assistant', resolvedAssistant);
  return result;
}

class _DossierTab {
  final IconData icon;
  final String label;
  const _DossierTab(this.icon, this.label);
}

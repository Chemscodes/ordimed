import '../ui/app_theme.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../ui/fluent_button.dart';
import 'consultation_page.dart';
import '../core/coerce.dart';
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

  const PatientDetailsPage({
    Key? key,
    required this.patientId,
    required this.patientName,
    required this.parentUid,
    required this.ownerProfileId,
    this.canAddForm = true,
    this.canAddDoctorForm = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.surface,
        scheme.surfaceVariant.withOpacity(isDark ? 0.22 : 0.6),
      ],
    );
    Color tone(Color color, double amount) {
      final hsl = HSLColor.fromColor(color);
      final l = (hsl.lightness + amount).clamp(0.0, 1.0);
      return hsl.withLightness(l).toColor();
    }

    final appBarStart = tone(scheme.primary, isDark ? -0.12 : -0.06);
    final appBarMid = tone(scheme.primary, isDark ? -0.02 : 0.06);
    final appBarEnd = tone(scheme.primary, isDark ? 0.06 : 0.16);
    final appBarAccent = Color.lerp(
      appBarEnd,
      scheme.secondary,
      isDark ? 0.12 : 0.2,
    )!;
    final appBarGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [appBarStart, appBarMid, appBarAccent],
    );
    final appBarBorder = Colors.white.withOpacity(isDark ? 0.1 : 0.18);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        toolbarHeight: 84,
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.14 : 0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(isDark ? 0.18 : 0.35),
                ),
              ),
              child: const Center(
                child: Icon(Icons.arrow_back, color: Colors.white),
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
                color: Colors.white.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              patientName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            gradient: appBarGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: appBarBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(
                  right: -40,
                  top: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(isDark ? 0.08 : 0.18),
                    ),
                  ),
                ),
                Positioned(
                  left: -30,
                  bottom: -40,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(isDark ? 0.06 : 0.14),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

          return Container(
            decoration: BoxDecoration(gradient: pageGradient),
            child: SingleChildScrollView(
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
                  // La salle d'attente n'est pas le seul chemin vers une
                  // consultation, et c'est un chemin que le medecin ne
                  // controle pas : il depend de l'assistant. Depuis le
                  // dossier, il lance le parcours guide lui-meme.
                  if (canAddDoctorForm) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FluentButton(
                          label: 'Demarrer la consultation guidee',
                          icon: Icons.play_circle_outline,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConsultationPage.depuisDossier(
                                parentUid: parentUid,
                                profileId: ownerProfileId,
                                patientId: patientId,
                                patient: patientData,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Les documents ci-dessous melangent ordonnances, bilans et
                  // consultations. L'historique isole le fil des seances, qui
                  // est ce qu'on relit avant de recevoir un patient.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CarteHistoriqueSeances(
                      parentUid: parentUid,
                      profileId: ownerProfileId,
                      patientId: patientId,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: FirestoreService().patientForms(
                      parentUid: parentUid,
                      profileId: ownerProfileId,
                      patientId: patientId,
                    ),
                    builder: (context, snapshot) {
                      // Ce bloc fusionnait trois sources : les documents du
                      // profil courant, ceux de la copie assistant, et une
                      // requete collectionGroup pour rattraper le reste.
                      // Firestore ecrivait chaque formulaire sous chaque
                      // profil, et il fallait recoller les morceaux en
                      // dedoublonnant sur le chemin du document.
                      //
                      // Il n'y a plus qu'un document par formulaire : la
                      // fusion n'a plus d'objet.
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final merged = snapshot.data!;

                          if (merged.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('Aucun formulaire')),
                            );
                          }

                          Map<String, dynamic>? latestMedSections;
                          for (final data in merged.reversed) {
                            final type = (data['type'] ?? '')
                                .toString()
                                .toLowerCase();
                            if (type.contains('medecin')) {
                              final sec = (data['sections'] as Map?)
                                  ?.cast<String, dynamic>();
                              if (sec != null && sec.isNotEmpty) {
                                latestMedSections = sec;
                                break;
                              }
                            }
                          }

                          String _fromSections(List<String> keys) {
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
                              _fromSections([
                                'poids_actuel',
                                'poids',
                                'Poids',
                              ]).isNotEmpty
                              ? _fromSections([
                                  'poids_actuel',
                                  'poids',
                                  'Poids',
                                ])
                              : (patientData['poids']?.toString() ?? '-');
                          String metricTaille =
                              _fromSections(['taille', 'Taille']).isNotEmpty
                              ? _fromSections(['taille', 'Taille'])
                              : (patientData['taille']?.toString() ?? '-');
                          String metricImc =
                              _fromSections(['imc', 'IMC']).isNotEmpty
                              ? _fromSections(['imc', 'IMC'])
                              : (patientData['imc']?.toString() ?? '-');

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

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Wrap(
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
                                    // Les motifs et origines sont stockés en
                                    // clé technique. Sans espaces, Flutter
                                    // coupait « famille_amis_bouche_a_oreille »
                                    // en plein milieu d'un mot.
                                    _MetricCard(
                                      label: 'Motif',
                                      value: fmt.capitalize(
                                        fmt.humanize(patientData['motif']),
                                      ),
                                      fallback: 'Non renseigné',
                                    ),
                                    _MetricCard(
                                      label: 'Origine',
                                      value: fmt.capitalize(
                                        fmt.humanize(patientData['origine']),
                                      ),
                                      fallback: 'Non renseignée',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Valeurs déduites : ni l'une ni l'autre n'est
                              // saisie, toutes deux se recalculent à chaque
                              // versement et à chaque séance clôturée.
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final reglement = ReglementSummary(
                                      reglement: Reglement.fromPatient(
                                        patientData,
                                      ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: reglement),
                                        const SizedBox(width: 12),
                                        Expanded(child: seances),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                // Le tableau du document ne garde plus que
                                // les versements recents : la sous-collection
                                // porte l'historique complet. Sans cette
                                // lecture, les anciens disparaitraient de
                                // l'ecran alors qu'ils existent toujours.
                                child: StreamBuilder<Map<String, dynamic>>(
                                  stream: ApiService.instance.dossierFlux(
                                    patientId,
                                  ),
                                  builder: (context, versSnap) {
                                    final sous =
                                        ((versSnap.data?['versements']
                                                    as List?) ??
                                                const [])
                                        .map(
                                          (d) => Versement.fromMap(
                                            Map<String, dynamic>.from(d as Map),
                                            id: (d['id'] ?? '').toString(),
                                          ),
                                        )
                                        .toList();
                                    final tous = fusionnerVersements(
                                      sousCollection: sous,
                                      tableauHerite:
                                          patientData['versements'],
                                    );
                                    return _buildVersementsCard(
                                  context: context,
                                  versements: tous
                                      .map(
                                        (v) => <String, dynamic>{
                                          'montant': v.montant,
                                          if (v.date != null)
                                            'createdAt': v.date,
                                          'auteurProfileId':
                                              v.auteurProfileId,
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
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _pillAction(
                                      context,
                                      Icons.receipt_long,
                                      'Ordonnance',
                                      onPressed: () => _openOrdonnanceDialog(
                                        context,
                                        patientData,
                                      ),
                                    ),
                                    _pillAction(
                                      context,
                                      Icons.article_outlined,
                                      'Bilan',
                                      onPressed: () => _openBilanDialog(
                                        context,
                                        patientData,
                                      ),
                                    ),
                                    _pillAction(
                                      context,
                                      Icons.payment,
                                      'Reglement',
                                      onPressed: () => _openReglementDialog(
                                        context,
                                        patientData,
                                      ),
                                    ),
                                    _pillAction(
                                      context,
                                      Icons.local_hospital,
                                      'Seance',
                                      onPressed: () => _openSeanceDialog(
                                        context,
                                        patientData,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: _renderFormGroups(
                                  merged,
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
                                  onEdit: (doc, data) => _openEditFormDialog(
                                    context,
                                    doc,
                                    data,
                                    patientData,
                                  ),
                                ),
                              ),
                            ],
                          );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: (canAddForm || canAddDoctorForm)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canAddDoctorForm) ...[
                  FloatingActionButton.extended(
                    heroTag: 'doctor_form',
                    icon: const Icon(Icons.medical_services_outlined),
                    label: const Text('Formulaire medecin'),
                    onPressed: () => _addDoctorForm(context),
                  ),
                  const SizedBox(height: 12),
                ],
                if (canAddForm)
                  FloatingActionButton.extended(
                    heroTag: 'assistant_form',
                    icon: const Icon(Icons.note_add),
                    label: const Text('Ajouter un formulaire'),
                    onPressed: () => _addForm(context),
                  ),
              ],
            )
          : null,
    );
  }

  double? _parseDouble(dynamic value) => asDoubleOrNull(value);

  int? _parseInt(dynamic value) => asIntOrNull(value);

  int? _computeSeanceNumero(Map<String, dynamic> patientData) {
    final done = _parseInt(patientData['seancesEffectuees']);
    if (done == null) return 1;
    if (done <= 0) return 1;
    return done;
  }

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

  bool _isDoctorOrPrincipalForPatient(Map<String, dynamic> patientData) {
    if (ownerProfileId == 'medecin_principal') return true;
    final doctorId = (patientData['doctorId'] ?? '').toString().trim();
    return doctorId.isNotEmpty && ownerProfileId == doctorId;
  }

  List<String> _normalizeCabinetItems(dynamic raw) {
    if (raw is! List) return const [];
    final normalized = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final value = item.toString().trim();
      if (value.isEmpty) continue;
      final lower = value.toLowerCase();
      if (seen.add(lower)) {
        normalized.add(value);
      }
    }
    normalized.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return normalized;
  }

  Future<List<String>> _loadCabinetReferenceList({
    required String fieldName,
  }) async {
    try {
      final cabinet = await ApiService.instance.cabinet();
      final listes = cabinet['listesReference'];
      final brut = listes is Map ? listes[fieldName] : null;
      return _normalizeCabinetItems(brut);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _appendCabinetReferenceList({
    required String fieldName,
    required Iterable<String> values,
  }) async {
    final incoming = _normalizeCabinetItems(values.toList());
    if (incoming.isEmpty) return;

    try {
      // `arrayUnion` devient `$addToSet` cote serveur : meme resultat, sans
      // doublons.
      await ApiService.instance.ajouterListe(fieldName, incoming);
    } catch (_) {
      // Ne jamais bloquer l'enregistrement d'une ordonnance/bilan
      // si la mise a jour de la base cabinet echoue.
    }
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

  Future<void> _openOrdonnanceDialog(
    BuildContext context,
    Map<String, dynamic> patientData,
  ) async {
    Map<String, dynamic> profileData = {};
    try {
      final profils = await ApiService.instance.profils();
      profileData = profils.firstWhere(
        (p) => p['id'] == ownerProfileId,
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    final nameCtrl = TextEditingController(
      text: (profileData['name'] ?? '').toString(),
    );
    final existingNameAr =
        (profileData['nameAr'] ?? profileData['name_ar'] ?? '')
            .toString()
            .trim();
    final existingSubtitle =
        (profileData['subtitle'] ?? profileData['specialite'] ?? '')
            .toString()
            .trim();
    final existingWilaya = (profileData['wilaya'] ?? '').toString().trim();
    final existingAddress =
        (profileData['address'] ?? profileData['adresse'] ?? '')
            .toString()
            .trim();
    final existingPhone = (profileData['tel'] ?? profileData['phone'] ?? '')
        .toString()
        .trim();
    final nameArCtrl = TextEditingController(text: existingNameAr);
    final subtitleCtrl = TextEditingController(
      text: (profileData['subtitle'] ?? profileData['specialite'] ?? '')
          .toString(),
    );
    final wilayaCtrl = TextEditingController(
      text: (profileData['wilaya'] ?? '').toString(),
    );
    final addressCtrl = TextEditingController(
      text: (profileData['address'] ?? profileData['adresse'] ?? '').toString(),
    );
    final phoneCtrl = TextEditingController(
      text: (profileData['tel'] ?? profileData['phone'] ?? '').toString(),
    );
    final noteCtrl = TextEditingController();
    final currentCounter = _parseInt(profileData['ordonnanceCounter']) ?? 0;
    final ordNumberCtrl = TextEditingController(text: '${currentCounter + 1}');
    final canUpdateCabinetMedicaments = _isDoctorOrPrincipalForPatient(
      patientData,
    );
    final cabinetMedicaments = await _loadCabinetReferenceList(
      fieldName: 'cabinetMedicaments',
    );

    final lines = <_OrdonnanceLine>[_OrdonnanceLine()];
    final dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final seanceNumeroStr = '';
    var showOrdonnanceInfo = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Ordonnance medecin'),
              content: SizedBox(
                width: AppTheme.dialogWidth(context, 700),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: const Text(
                            'Infos ordonnance',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            showOrdonnanceInfo
                                ? 'Masquer les champs'
                                : 'Afficher les champs modifiables',
                          ),
                          trailing: Icon(
                            showOrdonnanceInfo
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          onTap: () => setState(
                            () => showOrdonnanceInfo = !showOrdonnanceInfo,
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 180),
                        firstCurve: Curves.easeOut,
                        secondCurve: Curves.easeIn,
                        crossFadeState: showOrdonnanceInfo
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox.shrink(),
                        secondChild: Column(
                          children: [
                            const SizedBox(height: 8),
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nom medecin',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: nameArCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nom medecin (arabe)',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: subtitleCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Sous-titre (optionnel)',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: wilayaCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Wilaya (optionnel)',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Adresse (optionnel)',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: phoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Telephone (optionnel)',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextField(
                              controller: ordNumberCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Numero ordonnance',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Note de seance (interne)',
                          prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Prescription',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(lines.length, (index) {
                        final line = lines[index];
                        final currentName = line.nameCtrl.text.trim();
                        final filteredMedicaments = cabinetMedicaments
                            .where(
                              (e) =>
                                  currentName.isEmpty ||
                                  e.toLowerCase().contains(
                                    currentName.toLowerCase(),
                                  ),
                            )
                            .take(currentName.isEmpty ? 8 : 6)
                            .toList();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: line.checked,
                                onChanged: (v) =>
                                    setState(() => line.checked = v ?? true),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: line.nameCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Medicament',
                                        prefixIcon: Icon(
                                          Icons.medication_outlined,
                                        ),
                                      ),
                                      style: TextStyle(
                                        fontWeight: canUpdateCabinetMedicaments
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                      onTapOutside: (_) => FocusScope.of(
                                        dialogContext,
                                      ).unfocus(),
                                    ),
                                    if (cabinetMedicaments.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          ...filteredMedicaments.map(
                                            (m) => ActionChip(
                                              label: Text(
                                                m,
                                                style: TextStyle(
                                                  fontWeight:
                                                      canUpdateCabinetMedicaments
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              onPressed: () => setState(
                                                () => line.nameCtrl.text = m,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Base medicaments',
                                            onSelected: (value) {
                                              setState(
                                                () =>
                                                    line.nameCtrl.text = value,
                                              );
                                            },
                                            itemBuilder: (_) => cabinetMedicaments
                                                .map(
                                                  (m) => PopupMenuItem<String>(
                                                    value: m,
                                                    child: Text(
                                                      m,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            canUpdateCabinetMedicaments
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            child: const Chip(
                                              label: Text('Voir toute la base'),
                                              avatar: Icon(
                                                Icons.arrow_drop_down,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: line.qteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Qte',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: lines.length > 1
                                    ? () =>
                                          setState(() => lines.removeAt(index))
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => lines.add(_OrdonnanceLine())),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter ligne'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Apercu',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _buildOrdonnancePreview(
                        doctorName: nameCtrl.text.trim(),
                        doctorNameAr: nameArCtrl.text.trim(),
                        doctorSubtitle: subtitleCtrl.text.trim(),
                        wilaya: wilayaCtrl.text.trim(),
                        address: addressCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        patientNom: (patientData['nom'] ?? '').toString(),
                        patientPrenom: (patientData['prenom'] ?? '').toString(),
                        patientAge: (patientData['age'] ?? '').toString(),
                        dateStr: dateStr,
                        seanceNumero: '',
                        ordonnanceNumero: ordNumberCtrl.text.trim(),
                        lines: lines,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final items = lines
                        .where((l) => l.nameCtrl.text.trim().isNotEmpty)
                        .map((l) => l.toMap())
                        .toList();
                    if (items.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Ajoute au moins une ligne'),
                        ),
                      );
                      return;
                    }
                    final ordRaw = ordNumberCtrl.text.trim();
                    final ordNumber = int.tryParse(ordRaw);
                    if (ordNumber == null || ordNumber <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Numero ordonnance invalide'),
                        ),
                      );
                      return;
                    }

                    final contenu = items
                        .map((e) {
                          final name = (e['name'] ?? '').toString().trim();
                          final qte = (e['qte'] ?? '').toString().trim();
                          return qte.isEmpty ? name : '$name (Qte: $qte)';
                        })
                        .where((e) => e.isNotEmpty)
                        .join('\n');

                    final data = {
                      'type': 'Ordonnance medecin',
                      'contenu': contenu,
                      'prescriptions': items,
                      'doctorName': nameCtrl.text.trim(),
                      'doctorNameAr': nameArCtrl.text.trim(),
                      'doctorSubtitle': subtitleCtrl.text.trim(),
                      'doctorWilaya': wilayaCtrl.text.trim(),
                      'doctorAddress': addressCtrl.text.trim(),
                      'doctorPhone': phoneCtrl.text.trim(),
                      'patientNom': (patientData['nom'] ?? '').toString(),
                      'patientPrenom': (patientData['prenom'] ?? '').toString(),
                      'patientAge': (patientData['age'] ?? '').toString(),
                      'dateStr': dateStr,
                      'ordonnanceNumero': ordNumber,
                      // seanceNumero intentionally omitted for ordonnance
                      'note_de_seance': noteCtrl.text.trim(),
                                      'auteurProfileId': ownerProfileId,
                      'patientId': patientId,
                                    };

                    try {
                      await ApiService.instance.creerDocument(data);

                      if (canUpdateCabinetMedicaments) {
                        unawaited(
                          _appendCabinetReferenceList(
                            fieldName: 'cabinetMedicaments',
                            values: items
                                .map((e) => (e['name'] ?? '').toString().trim())
                                .where((e) => e.isNotEmpty),
                          ),
                        );
                      }

                      final updates = <String, dynamic>{};
                      final newNameAr = nameArCtrl.text.trim();
                      if (newNameAr.isNotEmpty && newNameAr != existingNameAr) {
                        updates['nameAr'] = newNameAr;
                      }
                      final newSubtitle = subtitleCtrl.text.trim();
                      if (newSubtitle.isNotEmpty &&
                          newSubtitle != existingSubtitle) {
                        updates['subtitle'] = newSubtitle;
                      }
                      final newWilaya = wilayaCtrl.text.trim();
                      if (newWilaya.isNotEmpty && newWilaya != existingWilaya) {
                        updates['wilaya'] = newWilaya;
                      }
                      final newAddress = addressCtrl.text.trim();
                      if (newAddress.isNotEmpty &&
                          newAddress != existingAddress) {
                        updates['address'] = newAddress;
                      }
                      final newPhone = phoneCtrl.text.trim();
                      if (newPhone.isNotEmpty && newPhone != existingPhone) {
                        updates['tel'] = newPhone;
                      }
                      if (ordNumber > currentCounter) {
                        updates['ordonnanceCounter'] = ordNumber;
                      }
                      if (updates.isNotEmpty) {
                        await ApiService.instance.majProfil(
                          ownerProfileId,
                          updates,
                        );
                      }
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      unawaited(
                        Future<void>.delayed(
                          const Duration(milliseconds: 300),
                          () async {
                            if (!context.mounted) return;
                            await _printOrdonnancePdf(
                              context: context,
                              doctorName: nameCtrl.text.trim(),
                              doctorNameAr: nameArCtrl.text.trim(),
                              doctorSubtitle: subtitleCtrl.text.trim(),
                              wilaya: wilayaCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              patientNom: (patientData['nom'] ?? '').toString(),
                              patientPrenom: (patientData['prenom'] ?? '')
                                  .toString(),
                              patientAge: (patientData['age'] ?? '').toString(),
                              dateStr: dateStr,
                              seanceNumero: '',
                              ordonnanceNumero: ordNumber.toString(),
                              items: items,
                            );
                          },
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Ordonnance enregistree, ouverture PDF...',
                          ),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Erreur lors de l\'enregistrement'),
                        ),
                      );
                    }
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    libererApresFermeture([
      nameCtrl,
      nameArCtrl,
      subtitleCtrl,
      wilayaCtrl,
      addressCtrl,
      phoneCtrl,
      noteCtrl,
      ordNumberCtrl,
    ]);
    apresFermeture(() {
      for (final line in lines) {
        line.dispose();
      }
    });
  }

  Future<void> _openBilanDialog(
    BuildContext context,
    Map<String, dynamic> patientData,
  ) async {
    Map<String, dynamic> profileData = {};
    try {
      final profils = await ApiService.instance.profils();
      profileData = profils.firstWhere(
        (p) => p['id'] == ownerProfileId,
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    final nameCtrl = TextEditingController(
      text: (profileData['name'] ?? '').toString(),
    );
    final existingNameAr =
        (profileData['nameAr'] ?? profileData['name_ar'] ?? '')
            .toString()
            .trim();
    final existingSubtitle =
        (profileData['subtitle'] ?? profileData['specialite'] ?? '')
            .toString()
            .trim();
    final existingWilaya = (profileData['wilaya'] ?? '').toString().trim();
    final existingAddress =
        (profileData['address'] ?? profileData['adresse'] ?? '')
            .toString()
            .trim();
    final existingPhone = (profileData['tel'] ?? profileData['phone'] ?? '')
        .toString()
        .trim();
    final nameArCtrl = TextEditingController(text: existingNameAr);
    final subtitleCtrl = TextEditingController(
      text: (profileData['subtitle'] ?? profileData['specialite'] ?? '')
          .toString(),
    );
    final wilayaCtrl = TextEditingController(
      text: (profileData['wilaya'] ?? '').toString(),
    );
    final addressCtrl = TextEditingController(
      text: (profileData['address'] ?? profileData['adresse'] ?? '').toString(),
    );
    final phoneCtrl = TextEditingController(
      text: (profileData['tel'] ?? profileData['phone'] ?? '').toString(),
    );
    final canUpdateCabinetBilans = _isDoctorOrPrincipalForPatient(patientData);
    final cabinetBilans = await _loadCabinetReferenceList(
      fieldName: 'cabinetBilans',
    );

    final lines = <_BilanLine>[_BilanLine()];
    final dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final seanceNumero = _computeSeanceNumero(patientData);
    final seanceNumeroStr = seanceNumero?.toString() ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Demande de bilan'),
              content: SizedBox(
                width: AppTheme.dialogWidth(context, 700),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Infos medecin',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom medecin',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: nameArCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom medecin (arabe)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: subtitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Sous-titre (optionnel)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: wilayaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Wilaya (optionnel)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Adresse (optionnel)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Telephone (optionnel)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Examens demandes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(lines.length, (index) {
                        final line = lines[index];
                        final currentName = line.nameCtrl.text.trim();
                        final filteredBilans = cabinetBilans
                            .where(
                              (e) =>
                                  currentName.isEmpty ||
                                  e.toLowerCase().contains(
                                    currentName.toLowerCase(),
                                  ),
                            )
                            .take(currentName.isEmpty ? 8 : 6)
                            .toList();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: line.checked,
                                onChanged: (v) =>
                                    setState(() => line.checked = v ?? true),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: line.nameCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Examen / Bilan',
                                        prefixIcon: Icon(
                                          Icons.science_outlined,
                                        ),
                                      ),
                                      style: TextStyle(
                                        fontWeight: canUpdateCabinetBilans
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                      onTapOutside: (_) => FocusScope.of(
                                        dialogContext,
                                      ).unfocus(),
                                    ),
                                    if (cabinetBilans.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          ...filteredBilans.map(
                                            (b) => ActionChip(
                                              label: Text(
                                                b,
                                                style: TextStyle(
                                                  fontWeight:
                                                      canUpdateCabinetBilans
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              onPressed: () => setState(
                                                () => line.nameCtrl.text = b,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Base bilans',
                                            onSelected: (value) {
                                              setState(
                                                () =>
                                                    line.nameCtrl.text = value,
                                              );
                                            },
                                            itemBuilder: (_) => cabinetBilans
                                                .map(
                                                  (b) => PopupMenuItem<String>(
                                                    value: b,
                                                    child: Text(
                                                      b,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            canUpdateCabinetBilans
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            child: const Chip(
                                              label: Text('Voir toute la base'),
                                              avatar: Icon(
                                                Icons.arrow_drop_down,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: lines.length > 1
                                    ? () =>
                                          setState(() => lines.removeAt(index))
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => lines.add(_BilanLine())),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter ligne'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Apercu',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _buildBilanPreview(
                        doctorName: nameCtrl.text.trim(),
                        doctorNameAr: nameArCtrl.text.trim(),
                        doctorSubtitle: subtitleCtrl.text.trim(),
                        wilaya: wilayaCtrl.text.trim(),
                        address: addressCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        patientNom: (patientData['nom'] ?? '').toString(),
                        patientPrenom: (patientData['prenom'] ?? '').toString(),
                        patientAge: (patientData['age'] ?? '').toString(),
                        dateStr: dateStr,
                        seanceNumero: seanceNumeroStr,
                        lines: lines,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final items = lines
                        .where((l) => l.nameCtrl.text.trim().isNotEmpty)
                        .map((l) => l.toMap())
                        .toList();
                    if (items.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Ajoute au moins une ligne'),
                        ),
                      );
                      return;
                    }

                    final contenu = items
                        .map((e) => (e['name'] ?? '').toString().trim())
                        .where((e) => e.isNotEmpty)
                        .join('\n');

                    final data = {
                      'type': 'Demande de bilan',
                      'contenu': contenu,
                      'examens': items,
                      'doctorName': nameCtrl.text.trim(),
                      'doctorNameAr': nameArCtrl.text.trim(),
                      'doctorSubtitle': subtitleCtrl.text.trim(),
                      'doctorWilaya': wilayaCtrl.text.trim(),
                      'doctorAddress': addressCtrl.text.trim(),
                      'doctorPhone': phoneCtrl.text.trim(),
                      'patientNom': (patientData['nom'] ?? '').toString(),
                      'patientPrenom': (patientData['prenom'] ?? '').toString(),
                      'patientAge': (patientData['age'] ?? '').toString(),
                      'dateStr': dateStr,
                      if (seanceNumero != null) 'seanceNumero': seanceNumero,
                                      'auteurProfileId': ownerProfileId,
                      'patientId': patientId,
                                    };

                    try {
                      await ApiService.instance.creerDocument(data);

                      if (canUpdateCabinetBilans) {
                        unawaited(
                          _appendCabinetReferenceList(
                            fieldName: 'cabinetBilans',
                            values: items
                                .map((e) => (e['name'] ?? '').toString().trim())
                                .where((e) => e.isNotEmpty),
                          ),
                        );
                      }

                      final updates = <String, dynamic>{};
                      final newNameAr = nameArCtrl.text.trim();
                      if (newNameAr.isNotEmpty && newNameAr != existingNameAr) {
                        updates['nameAr'] = newNameAr;
                      }
                      final newSubtitle = subtitleCtrl.text.trim();
                      if (newSubtitle.isNotEmpty &&
                          newSubtitle != existingSubtitle) {
                        updates['subtitle'] = newSubtitle;
                      }
                      final newWilaya = wilayaCtrl.text.trim();
                      if (newWilaya.isNotEmpty && newWilaya != existingWilaya) {
                        updates['wilaya'] = newWilaya;
                      }
                      final newAddress = addressCtrl.text.trim();
                      if (newAddress.isNotEmpty &&
                          newAddress != existingAddress) {
                        updates['address'] = newAddress;
                      }
                      final newPhone = phoneCtrl.text.trim();
                      if (newPhone.isNotEmpty && newPhone != existingPhone) {
                        updates['tel'] = newPhone;
                      }
                      if (updates.isNotEmpty) {
                        await ApiService.instance.majProfil(
                          ownerProfileId,
                          updates,
                        );
                      }
                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Demande de bilan enregistree'),
                          action: SnackBarAction(
                            label: 'Ouvrir PDF',
                            onPressed: () {
                              unawaited(
                                _printBilanPdf(
                                  context: context,
                                  doctorName: nameCtrl.text.trim(),
                                  doctorNameAr: nameArCtrl.text.trim(),
                                  doctorSubtitle: subtitleCtrl.text.trim(),
                                  wilaya: wilayaCtrl.text.trim(),
                                  address: addressCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim(),
                                  patientNom: (patientData['nom'] ?? '')
                                      .toString(),
                                  patientPrenom: (patientData['prenom'] ?? '')
                                      .toString(),
                                  patientAge: (patientData['age'] ?? '')
                                      .toString(),
                                  dateStr: dateStr,
                                  seanceNumero: seanceNumeroStr,
                                  items: items,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Erreur lors de l\'enregistrement'),
                        ),
                      );
                    }
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    libererApresFermeture([
      nameCtrl,
      nameArCtrl,
      subtitleCtrl,
      wilayaCtrl,
      addressCtrl,
      phoneCtrl,
    ]);
    apresFermeture(() {
      for (final line in lines) {
        line.dispose();
      }
    });
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

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reglement'),
        content: _scrollableDialogContent(context, Column(
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
              ),
            ),
          ],
        )),
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
      libererApresFermeture([prixCtrl]);
      return;
    }

    final raw = prixCtrl.text.replaceAll(',', '.').trim();
    final montant = double.tryParse(raw);
    libererApresFermeture([prixCtrl]);
    if (montant == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Montant invalide')));
      }
      return;
    }

    try {
      await _updatePatientCopies(patientData, {'prix': montant});
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Total mis a jour')));
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
        content: _scrollableDialogContent(context, Column(
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
              decoration: const InputDecoration(labelText: 'Nombre de seances'),
            ),
          ],
        )),
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

  Widget _buildBilanPreview({
    required String doctorName,
    required String doctorNameAr,
    required String doctorSubtitle,
    required String wilaya,
    required String address,
    required String phone,
    required String patientNom,
    required String patientPrenom,
    required String patientAge,
    required String dateStr,
    required String seanceNumero,
    required List<_BilanLine> lines,
  }) {
    final visibleLines = lines
        .where((l) => l.checked && l.nameCtrl.text.trim().isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorName.isEmpty ? ' ' : doctorName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (doctorSubtitle.isNotEmpty) Text(doctorSubtitle),
                    if (wilaya.isNotEmpty) Text('Wilaya : $wilaya'),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (doctorNameAr.isNotEmpty)
                      Directionality(
                        textDirection: ui.TextDirection.rtl,
                        child: Text(
                          doctorNameAr,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    Text('Date : $dateStr'),
                    if (seanceNumero.isNotEmpty) Text('Seance : $seanceNumero'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'DEMANDE DE BILAN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              Text('Nom : $patientNom'),
              Text('Prenom : $patientPrenom'),
              Text('Age : $patientAge'),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(thickness: 1),
          const SizedBox(height: 6),
          const Text(
            'Examens demandes',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (visibleLines.isEmpty)
            const Text('Aucun examen')
          else
            ...visibleLines.map((line) {
              final name = line.nameCtrl.text.trim();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      line.checked
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name)),
                  ],
                ),
              );
            }).toList(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address.isNotEmpty) Text(address),
                    if (phone.isNotEmpty) Text(phone),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Signature'),
                  const SizedBox(height: 6),
                  Container(height: 1, width: 160, color: Colors.black),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrdonnancePreview({
    required String doctorName,
    required String doctorNameAr,
    required String doctorSubtitle,
    required String wilaya,
    required String address,
    required String phone,
    required String patientNom,
    required String patientPrenom,
    required String patientAge,
    required String dateStr,
    required String seanceNumero,
    required String ordonnanceNumero,
    required List<_OrdonnanceLine> lines,
  }) {
    final visibleLines = lines
        .where((l) => l.checked && l.nameCtrl.text.trim().isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorName.isEmpty ? ' ' : doctorName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (doctorSubtitle.isNotEmpty) Text(doctorSubtitle),
                    if (wilaya.isNotEmpty) Text('Wilaya : $wilaya'),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (doctorNameAr.isNotEmpty)
                      Directionality(
                        textDirection: ui.TextDirection.rtl,
                        child: Text(
                          doctorNameAr,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (ordonnanceNumero.isNotEmpty)
                      Text('Ordonnance N°: $ordonnanceNumero'),
                    Text('Date : $dateStr'),
                    if (seanceNumero.isNotEmpty) Text('Seance : $seanceNumero'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'ORDONNANCE MEDECIN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              Text('Nom : $patientNom'),
              Text('Prenom : $patientPrenom'),
              Text('Age : $patientAge'),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(thickness: 1),
          const SizedBox(height: 6),
          const Text(
            'Prescription',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (visibleLines.isEmpty)
            const Text('Aucune prescription')
          else
            ...visibleLines.map((line) {
              final name = line.nameCtrl.text.trim();
              final qte = line.qteCtrl.text.trim();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      line.checked
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name),
                          if (qte.isNotEmpty) Text('Qte : $qte'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (address.isNotEmpty) Text(address),
                    if (phone.isNotEmpty) Text(phone),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Signature'),
                  const SizedBox(height: 6),
                  Container(height: 1, width: 160, color: Colors.black),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<_PdfFonts> _resolvePdfFonts() async {
    pw.Font base = pw.Font.helvetica();
    pw.Font bold = pw.Font.helveticaBold();
    pw.Font arabic = base;
    try {
      base = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {}
    try {
      arabic = await PdfGoogleFonts.notoNaskhArabicRegular();
    } catch (_) {
      arabic = base;
    }
    return _PdfFonts(base: base, bold: bold, arabic: arabic);
  }

  Future<Uint8List> _buildMedicalPdfBytes({
    required String title,
    required String sectionTitle,
    required List<String> entries,
    required String emptyLabel,
    required String doctorName,
    required String doctorNameAr,
    required String doctorSubtitle,
    required String wilaya,
    required String address,
    required String phone,
    required String patientNom,
    required String patientPrenom,
    required String patientAge,
    required String dateStr,
    required String seanceNumero,
    String documentNumberLabel = '',
    String documentNumber = '',
  }) async {
    final fonts = await _resolvePdfFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
    );

    final titleStyle = pw.TextStyle(
      font: fonts.bold,
      fontSize: 16,
      letterSpacing: 1,
    );
    final labelStyle = pw.TextStyle(font: fonts.bold, fontSize: 11);
    final smallStyle = pw.TextStyle(fontSize: 10);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      doctorName.isEmpty ? ' ' : doctorName,
                      style: labelStyle,
                    ),
                    if (doctorSubtitle.isNotEmpty)
                      pw.Text(doctorSubtitle, style: smallStyle),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (doctorNameAr.isNotEmpty)
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Text(
                          doctorNameAr,
                          style: pw.TextStyle(font: fonts.arabic, fontSize: 12),
                        ),
                      ),
                    if (wilaya.isNotEmpty)
                      pw.Text('Wilaya : $wilaya', style: smallStyle),
                    if (documentNumber.isNotEmpty)
                      pw.Text(
                        '$documentNumberLabel : $documentNumber',
                        style: smallStyle,
                      ),
                    pw.Text('Date : $dateStr', style: smallStyle),
                    if (seanceNumero.isNotEmpty)
                      pw.Text('Seance : $seanceNumero', style: smallStyle),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text(title, style: titleStyle)),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              pw.Text('Nom : $patientNom'),
              pw.Text('Prenom : $patientPrenom'),
              pw.Text('Age : $patientAge'),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 6),
          pw.Text(sectionTitle, style: labelStyle),
          pw.SizedBox(height: 6),
          if (entries.isEmpty)
            pw.Text(emptyLabel, style: smallStyle)
          else
            pw.Column(
              children: entries
                  .map(
                    (entry) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('- '),
                          pw.Expanded(child: pw.Text(entry)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
        footer: (context) {
          if (address.isEmpty && phone.isEmpty) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Signature', style: smallStyle),
                  pw.SizedBox(height: 6),
                  pw.Container(height: 1, width: 160, color: PdfColors.black),
                ],
              ),
            );
          }
          return pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (address.isNotEmpty) pw.Text(address, style: smallStyle),
                    if (phone.isNotEmpty) pw.Text(phone, style: smallStyle),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Signature', style: smallStyle),
                  pw.SizedBox(height: 6),
                  pw.Container(height: 1, width: 160, color: PdfColors.black),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  String _sanitizeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ascii = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return ascii.isEmpty ? 'document' : ascii;
  }

  Future<File> _writePdfTemp(Uint8List bytes, String baseName) async {
    final dir = Directory.systemTemp;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safe = _sanitizeFileName(baseName);
    final file = File('${dir.path}\\${safe}_$stamp.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _openPdfInBrowser(File file) async {
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
        await request.response.addStream(file.openRead());
        await request.response.close();
      });

      final url = Uri.parse('http://127.0.0.1:$port/document.pdf');
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && Platform.isWindows) {
        try {
          await Process.start('cmd', ['/c', 'start', '', url.toString()]);
        } catch (_) {}
      }
      Future.delayed(const Duration(minutes: 2), () {
        try {
          server?.close(force: true);
        } catch (_) {}
      });
    } catch (_) {
      if (Platform.isWindows) {
        try {
          await Process.start('cmd', ['/c', 'start', '', file.path]);
        } catch (_) {}
      }
    }
  }

  Future<void> _printOrdonnancePdf({
    required BuildContext context,
    required String doctorName,
    required String doctorNameAr,
    required String doctorSubtitle,
    required String wilaya,
    required String address,
    required String phone,
    required String patientNom,
    required String patientPrenom,
    required String patientAge,
    required String dateStr,
    required String seanceNumero,
    required String ordonnanceNumero,
    required List<Map<String, dynamic>> items,
  }) async {
    final entries = items
        .where((e) => (e['checked'] as bool?) ?? true)
        .map((e) {
          final name = (e['name'] ?? '').toString().trim();
          if (name.isEmpty) return '';
          final qte = (e['qte'] ?? '').toString().trim();
          return qte.isEmpty ? name : '$name (Qte: $qte)';
        })
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final bytes = await _buildMedicalPdfBytes(
        title: 'ORDONNANCE MEDECIN',
        sectionTitle: 'Prescription',
        entries: entries,
        emptyLabel: 'Aucune prescription',
        doctorName: doctorName,
        doctorNameAr: doctorNameAr,
        doctorSubtitle: doctorSubtitle,
        wilaya: wilaya,
        address: address,
        phone: phone,
        patientNom: patientNom,
        patientPrenom: patientPrenom,
        patientAge: patientAge,
        dateStr: dateStr,
        seanceNumero: seanceNumero,
        documentNumberLabel: 'Ordonnance N°',
        documentNumber: ordonnanceNumero,
      );
      final file = await _writePdfTemp(
        bytes,
        'Ordonnance_${patientNom}_${ordonnanceNumero}_$dateStr',
      );
      await _openPdfInBrowser(file);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la generation du PDF')),
        );
      }
    }
  }

  Future<void> _printBilanPdf({
    required BuildContext context,
    required String doctorName,
    required String doctorNameAr,
    required String doctorSubtitle,
    required String wilaya,
    required String address,
    required String phone,
    required String patientNom,
    required String patientPrenom,
    required String patientAge,
    required String dateStr,
    required String seanceNumero,
    required List<Map<String, dynamic>> items,
  }) async {
    final entries = items
        .where((e) => (e['checked'] as bool?) ?? true)
        .map((e) => (e['name'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final bytes = await _buildMedicalPdfBytes(
        title: 'DEMANDE DE BILAN',
        sectionTitle: 'Examens demandes',
        entries: entries,
        emptyLabel: 'Aucun examen',
        doctorName: doctorName,
        doctorNameAr: doctorNameAr,
        doctorSubtitle: doctorSubtitle,
        wilaya: wilaya,
        address: address,
        phone: phone,
        patientNom: patientNom,
        patientPrenom: patientPrenom,
        patientAge: patientAge,
        dateStr: dateStr,
        seanceNumero: seanceNumero,
      );
      final file = await _writePdfTemp(bytes, 'Bilan_${patientNom}_$dateStr');
      await _openPdfInBrowser(file);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la generation du PDF')),
        );
      }
    }
  }

  Future<void> _addForm(BuildContext context) async {
    final ctrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'Note');
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau formulaire'),
        content: _scrollableDialogContent(context, Column(
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
        )),
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
    final prototypeFields = await _resolveDoctorPrototypeFields(
      resolvedPatient,
    );
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

  Future<List<String>> _resolveDoctorPrototypeFields(
    Map<String, dynamic> patientData,
  ) async {
    final motif = _pickMotif(patientData);
    if (motif.isEmpty) return [];

    try {
      // Le repli sur le profil disparait : les prototypes vivaient a deux
      // endroits, le backend n'en a plus qu'un.
      final cabinet = await ApiService.instance.cabinet();
      final dynamic raw = cabinet['motifPrototypes'];
      if (raw is! Map) return [];
      final map = <String, List<String>>{};
      raw.forEach((key, value) {
        final k = key.toString().trim();
        if (k.isEmpty) return;
        if (value is List) {
          final list = value
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (list.isNotEmpty) map[k] = list;
        }
      });
      if (map.isEmpty) return [];
      String? match;
      for (final k in map.keys) {
        if (k.toLowerCase() == motif.toLowerCase()) {
          match = k;
          break;
        }
      }
      if (match == null) return [];
      final fields = map[match] ?? [];
      final unique = <String>[];
      for (final f in fields) {
        final cleaned = f.trim();
        if (cleaned.isEmpty) continue;
        if (!unique.contains(cleaned)) unique.add(cleaned);
      }
      return unique;
    } catch (_) {
      return [];
    }
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
      final key = _normalizeSectionKey(f);
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

  String _pickMotif(Map<String, dynamic> patientData) {
    final candidates = <String>[];
    final rawList = patientData['motifs'];
    if (rawList is List) {
      for (final v in rawList) {
        final s = v.toString().trim();
        if (s.isNotEmpty) candidates.add(s);
      }
    }
    if (candidates.isEmpty) {
      final raw = (patientData['motif'] ?? '').toString();
      if (raw.isNotEmpty) {
        candidates.addAll(
          raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      }
    }
    for (final c in candidates) {
      final lower = c.toLowerCase();
      if (lower.startsWith('autre:')) continue;
      return c;
    }
    if (candidates.isNotEmpty) return candidates.first;
    return '';
  }

  String _normalizeSectionKey(String label) {
    final raw = label.trim().toLowerCase();
    if (raw == 'poids' || raw == 'poids actuel' || raw == 'poids_actuel') {
      return 'poids';
    }
    if (raw == 'taille') return 'taille';
    if (raw == 'imc') return 'imc';
    final buffer = StringBuffer();
    for (final r in raw.runes) {
      final ch = String.fromCharCode(r);
      final isLetter = (r >= 48 && r <= 57) || (r >= 97 && r <= 122);
      if (isLetter) {
        buffer.write(ch);
      } else {
        buffer.write('_');
      }
    }
    final cleaned = buffer.toString().replaceAll(RegExp('_+'), '_');
    return cleaned.startsWith('_') ? cleaned.substring(1) : cleaned;
  }
}

Map<String, String> _fallbackFields(Map<String, dynamic> data) {
  final ignored = {
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
      final at = asDateOrNull(a['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bt = asDateOrNull(b['createdAt']) ??
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
      allowEdit:
          type != TypeDocument.ordonnance && type != TypeDocument.bilan,
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
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
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
                  children: [
                    for (final d in visites[i].documents) carteDe(d),
                  ],
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

class _OrdonnanceLine {
  final TextEditingController nameCtrl;
  final TextEditingController qteCtrl;
  bool checked;

  _OrdonnanceLine({String name = '', String qte = '', this.checked = true})
    : nameCtrl = TextEditingController(text: name),
      qteCtrl = TextEditingController(text: qte);

  Map<String, dynamic> toMap() {
    return {
      'name': nameCtrl.text.trim(),
      'qte': qteCtrl.text.trim(),
      'checked': checked,
    };
  }

  void dispose() {
    nameCtrl.dispose();
    qteCtrl.dispose();
  }
}

class _BilanLine {
  final TextEditingController nameCtrl;
  bool checked;

  _BilanLine({String name = '', this.checked = true})
    : nameCtrl = TextEditingController(text: name);

  Map<String, dynamic> toMap() {
    return {'name': nameCtrl.text.trim(), 'checked': checked};
  }

  void dispose() {
    nameCtrl.dispose();
  }
}

class _PdfFonts {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font arabic;

  const _PdfFonts({
    required this.base,
    required this.bold,
    required this.arabic,
  });
}

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/coerce.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';
import '../ui/app_theme.dart';

/// Page pleine ecran de redaction de demande de bilan.
///
/// Remplace l'ancien `AlertDialog` de `PatientDetailsPage` : formulaire a
/// gauche, apercu PDF live a droite. La logique metier (enregistrement,
/// mise a jour du profil medecin, impression) est inchangee.
class BilanPage extends StatefulWidget {
  final String ownerProfileId;
  final String patientId;
  final Map<String, dynamic> patientData;

  const BilanPage({
    super.key,
    required this.ownerProfileId,
    required this.patientId,
    required this.patientData,
  });

  @override
  State<BilanPage> createState() => _BilanPageState();
}

class _BilanPageState extends State<BilanPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _wilayaCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final String _dateStr;
  late final int? _seanceNumero;
  late final String _seanceNumeroStr;

  String _existingNameAr = '';
  String _existingSubtitle = '';
  String _existingWilaya = '';
  String _existingAddress = '';
  String _existingPhone = '';
  bool _canUpdateCabinetBilans = false;
  List<String> _cabinetBilans = const [];
  final List<_BilanLine> _lines = [_BilanLine()];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _seanceNumero = _computeSeanceNumero(widget.patientData);
    _seanceNumeroStr = _seanceNumero?.toString() ?? '';
    _nameCtrl = TextEditingController();
    _nameArCtrl = TextEditingController();
    _subtitleCtrl = TextEditingController();
    _wilayaCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _subtitleCtrl.dispose();
    _wilayaCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  int? _computeSeanceNumero(Map<String, dynamic> patientData) {
    final done = asIntOrNull(patientData['seancesEffectuees']);
    if (done == null) return 1;
    if (done <= 0) return 1;
    return done;
  }

  Future<void> _load() async {
    Map<String, dynamic> profileData = {};
    try {
      final profils = await ApiService.instance.profils();
      profileData = profils.firstWhere(
        (p) => p['id'] == widget.ownerProfileId,
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    final cabinetBilans = await _loadCabinetReferenceList(
      fieldName: 'cabinetBilans',
    );

    if (!mounted) return;
    setState(() {
      _nameCtrl.text = (profileData['name'] ?? '').toString();
      _existingNameAr = (profileData['nameAr'] ?? profileData['name_ar'] ?? '')
          .toString()
          .trim();
      _existingSubtitle =
          (profileData['subtitle'] ?? profileData['specialite'] ?? '')
              .toString()
              .trim();
      _existingWilaya = (profileData['wilaya'] ?? '').toString().trim();
      _existingAddress =
          (profileData['address'] ?? profileData['adresse'] ?? '')
              .toString()
              .trim();
      _existingPhone = (profileData['tel'] ?? profileData['phone'] ?? '')
          .toString()
          .trim();
      _nameArCtrl.text = _existingNameAr;
      _subtitleCtrl.text = _existingSubtitle;
      _wilayaCtrl.text = _existingWilaya;
      _addressCtrl.text = _existingAddress;
      _phoneCtrl.text = _existingPhone;
      _canUpdateCabinetBilans = _isDoctorOrPrincipalForPatient(
        widget.patientData,
      );
      _cabinetBilans = cabinetBilans;
      _loading = false;
    });
  }

  bool _isDoctorOrPrincipalForPatient(Map<String, dynamic> patientData) {
    if (widget.ownerProfileId == 'medecin_principal') return true;
    final doctorId = (patientData['doctorId'] ?? '').toString().trim();
    return doctorId.isNotEmpty && widget.ownerProfileId == doctorId;
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
      await ApiService.instance.ajouterListe(fieldName, incoming);
    } catch (_) {
      // Ne jamais bloquer l'enregistrement d'une demande de bilan si la
      // mise a jour de la base cabinet echoue.
    }
  }

  Future<void> _save() async {
    final items = _lines
        .where((l) => l.nameCtrl.text.trim().isNotEmpty)
        .map((l) => l.toMap())
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute au moins une ligne')),
      );
      return;
    }

    final contenu = items
        .map((e) => (e['name'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .join('\n');

    final patientNom = (widget.patientData['nom'] ?? '').toString();
    final patientPrenom = (widget.patientData['prenom'] ?? '').toString();
    final patientAge = (widget.patientData['age'] ?? '').toString();
    final doctorName = _nameCtrl.text.trim();
    final doctorNameAr = _nameArCtrl.text.trim();
    final doctorSubtitle = _subtitleCtrl.text.trim();
    final wilaya = _wilayaCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    final data = {
      'type': 'Demande de bilan',
      'contenu': contenu,
      'examens': items,
      'doctorName': doctorName,
      'doctorNameAr': doctorNameAr,
      'doctorSubtitle': doctorSubtitle,
      'doctorWilaya': wilaya,
      'doctorAddress': address,
      'doctorPhone': phone,
      'patientNom': patientNom,
      'patientPrenom': patientPrenom,
      'patientAge': patientAge,
      'dateStr': _dateStr,
      if (_seanceNumero != null) 'seanceNumero': _seanceNumero,
      'auteurProfileId': widget.ownerProfileId,
      'patientId': widget.patientId,
    };

    setState(() => _saving = true);
    try {
      await ApiService.instance.creerDocument(data);

      if (_canUpdateCabinetBilans) {
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
      if (doctorNameAr.isNotEmpty && doctorNameAr != _existingNameAr) {
        updates['nameAr'] = doctorNameAr;
      }
      if (doctorSubtitle.isNotEmpty && doctorSubtitle != _existingSubtitle) {
        updates['subtitle'] = doctorSubtitle;
      }
      if (wilaya.isNotEmpty && wilaya != _existingWilaya) {
        updates['wilaya'] = wilaya;
      }
      if (address.isNotEmpty && address != _existingAddress) {
        updates['address'] = address;
      }
      if (phone.isNotEmpty && phone != _existingPhone) {
        updates['tel'] = phone;
      }
      if (updates.isNotEmpty) {
        await ApiService.instance.majProfil(widget.ownerProfileId, updates);
      }

      if (!mounted) return;
      await PdfService.instance.printBilanPdf(
        context: context,
        doctorName: doctorName,
        doctorNameAr: doctorNameAr,
        doctorSubtitle: doctorSubtitle,
        wilaya: wilaya,
        address: address,
        phone: phone,
        patientNom: patientNom,
        patientPrenom: patientPrenom,
        patientAge: patientAge,
        dateStr: _dateStr,
        seanceNumero: _seanceNumeroStr,
        items: items,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'enregistrement')),
      );
    }
  }

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
        title: Text(
          'Demande de bilan',
          style: TextStyle(
            color: ink1,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outline),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 900;
                final form = _buildForm(context);
                final preview = _buildPreviewColumn(context);
                if (narrow) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [form, const SizedBox(height: 24), preview],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: form,
                      ),
                    ),
                    VerticalDivider(width: 1, color: scheme.outline),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: preview,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Infos medecin',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom medecin'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _nameArCtrl,
          decoration: const InputDecoration(labelText: 'Nom medecin (arabe)'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _subtitleCtrl,
          decoration: const InputDecoration(
            labelText: 'Sous-titre (optionnel)',
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _wilayaCtrl,
          decoration: const InputDecoration(labelText: 'Wilaya (optionnel)'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(labelText: 'Adresse (optionnel)'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(labelText: 'Telephone (optionnel)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const Text(
          'Examens demandes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...List.generate(_lines.length, (index) {
          final line = _lines[index];
          final currentName = line.nameCtrl.text.trim();
          final filteredBilans = _cabinetBilans
              .where(
                (e) =>
                    currentName.isEmpty ||
                    e.toLowerCase().contains(currentName.toLowerCase()),
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
                  onChanged: (v) => setState(() => line.checked = v ?? true),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: line.nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Examen / Bilan',
                          prefixIcon: Icon(Icons.science_outlined),
                        ),
                        style: TextStyle(
                          fontWeight: _canUpdateCabinetBilans
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        onChanged: (_) => setState(() {}),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      ),
                      if (_cabinetBilans.isNotEmpty) ...[
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
                                    fontWeight: _canUpdateCabinetBilans
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                onPressed: () =>
                                    setState(() => line.nameCtrl.text = b),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Base bilans',
                              onSelected: (value) =>
                                  setState(() => line.nameCtrl.text = value),
                              itemBuilder: (_) => _cabinetBilans
                                  .map(
                                    (b) => PopupMenuItem<String>(
                                      value: b,
                                      child: Text(
                                        b,
                                        style: TextStyle(
                                          fontWeight: _canUpdateCabinetBilans
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              child: const Chip(
                                label: Text('Voir toute la base'),
                                avatar: Icon(Icons.arrow_drop_down),
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
                  onPressed: _lines.length > 1
                      ? () => setState(() => _lines.removeAt(index))
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
            onPressed: () => setState(() => _lines.add(_BilanLine())),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter ligne'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Apercu', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _buildBilanPreview(
          doctorName: _nameCtrl.text.trim(),
          doctorNameAr: _nameArCtrl.text.trim(),
          doctorSubtitle: _subtitleCtrl.text.trim(),
          wilaya: _wilayaCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          patientNom: (widget.patientData['nom'] ?? '').toString(),
          patientPrenom: (widget.patientData['prenom'] ?? '').toString(),
          patientAge: (widget.patientData['age'] ?? '').toString(),
          dateStr: _dateStr,
          seanceNumero: _seanceNumeroStr,
          lines: _lines,
        ),
      ],
    );
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

    const accent = Color(0xFF0E7C6B);
    const accentTint = Color(0xFFE6F2EF);
    const ink = Color(0xFF10171A);
    const muted = Color(0xFF5A686D);
    const borderLight = Color(0xFFD9E2E4);

    TextStyle label() => GoogleFonts.ibmPlexSans(
      color: muted,
      fontSize: 9.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      clipBehavior: Clip.antiAlias,
      // La feuille est toujours blanche, y compris en thème sombre — sans
      // ce texte forcé en encre foncée, les `Text` héritaient de la couleur
      // claire du thème et devenaient illisibles sur le fond blanc.
      child: DefaultTextStyle(
        style: GoogleFonts.ibmPlexSans(color: ink, fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                              style: GoogleFonts.ibmPlexSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: ink,
                              ),
                            ),
                            if (doctorSubtitle.isNotEmpty)
                              Text(
                                doctorSubtitle,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            if (wilaya.isNotEmpty)
                              Text(
                                'Wilaya : $wilaya',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
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
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: ink,
                                  ),
                                ),
                              ),
                            Text(
                              'Date : $dateStr',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                            if (seanceNumero.isNotEmpty)
                              Text(
                                'Seance : $seanceNumero',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      'DEMANDE DE BILAN',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PATIENT', style: label()),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 20,
                          runSpacing: 4,
                          children: [
                            Text(
                              '$patientNom $patientPrenom',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Age : $patientAge',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('EXAMENS DEMANDES', style: label()),
                  const SizedBox(height: 8),
                  if (visibleLines.isEmpty)
                    Text('Aucun examen', style: TextStyle(color: muted))
                  else
                    ...visibleLines.asMap().entries.map((entry) {
                      final numero = entry.key + 1;
                      final line = entry.value;
                      final name = line.nameCtrl.text.trim();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFBFB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border(
                            left: BorderSide(color: accent, width: 2.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accentTint,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$numero',
                                style: const TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  Container(height: 1, color: borderLight),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (address.isNotEmpty)
                              Text(
                                address,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            if (phone.isNotEmpty)
                              Text(
                                phone,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Signature', style: label()),
                          const SizedBox(height: 10),
                          Container(height: 1, width: 160, color: borderLight),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

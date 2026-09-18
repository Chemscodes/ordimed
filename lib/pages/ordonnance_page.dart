import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/coerce.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';
import '../ui/app_theme.dart';

/// Page pleine ecran de redaction d'ordonnance.
///
/// Remplace l'ancien `AlertDialog` de `PatientDetailsPage` : formulaire a
/// gauche, apercu PDF live a droite. La logique metier (enregistrement,
/// mise a jour du profil medecin, impression) est inchangee.
class OrdonnancePage extends StatefulWidget {
  final String ownerProfileId;
  final String patientId;
  final Map<String, dynamic> patientData;

  const OrdonnancePage({
    super.key,
    required this.ownerProfileId,
    required this.patientId,
    required this.patientData,
  });

  @override
  State<OrdonnancePage> createState() => _OrdonnancePageState();
}

class _OrdonnancePageState extends State<OrdonnancePage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _wilayaCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _ordNumberCtrl;
  late final String _dateStr;

  String _existingNameAr = '';
  String _existingSubtitle = '';
  String _existingWilaya = '';
  String _existingAddress = '';
  String _existingPhone = '';
  int _currentCounter = 0;
  bool _canUpdateCabinetMedicaments = false;
  List<String> _cabinetMedicaments = const [];
  final List<_OrdonnanceLine> _lines = [_OrdonnanceLine()];
  bool _showInfo = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _nameCtrl = TextEditingController();
    _nameArCtrl = TextEditingController();
    _subtitleCtrl = TextEditingController();
    _wilayaCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _ordNumberCtrl = TextEditingController();
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
    _noteCtrl.dispose();
    _ordNumberCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
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

    final cabinetMedicaments = await _loadCabinetReferenceList(
      fieldName: 'cabinetMedicaments',
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
      _currentCounter = asIntOrNull(profileData['ordonnanceCounter']) ?? 0;
      _ordNumberCtrl.text = '${_currentCounter + 1}';
      _canUpdateCabinetMedicaments = _isDoctorOrPrincipalForPatient(
        widget.patientData,
      );
      _cabinetMedicaments = cabinetMedicaments;
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
      // Ne jamais bloquer l'enregistrement d'une ordonnance si la mise a
      // jour de la base cabinet echoue.
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
    final ordRaw = _ordNumberCtrl.text.trim();
    final ordNumber = int.tryParse(ordRaw);
    if (ordNumber == null || ordNumber <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numero ordonnance invalide')),
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
      'type': 'Ordonnance medecin',
      'contenu': contenu,
      'prescriptions': items,
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
      'ordonnanceNumero': ordNumber,
      // seanceNumero intentionally omitted for ordonnance
      'note_de_seance': _noteCtrl.text.trim(),
      'auteurProfileId': widget.ownerProfileId,
      'patientId': widget.patientId,
    };

    setState(() => _saving = true);
    try {
      await ApiService.instance.creerDocument(data);

      if (_canUpdateCabinetMedicaments) {
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
      if (ordNumber > _currentCounter) {
        updates['ordonnanceCounter'] = ordNumber;
      }
      if (updates.isNotEmpty) {
        await ApiService.instance.majProfil(widget.ownerProfileId, updates);
      }

      if (!mounted) return;
      await PdfService.instance.printOrdonnancePdf(
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
        seanceNumero: '',
        ordonnanceNumero: ordNumber.toString(),
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
          'Ordonnance medecin',
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
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text(
              'Infos ordonnance',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _showInfo
                  ? 'Masquer les champs'
                  : 'Afficher les champs modifiables',
            ),
            trailing: Icon(
              _showInfo ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            onTap: () => setState(() => _showInfo = !_showInfo),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          crossFadeState: _showInfo
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom medecin'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _nameArCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom medecin (arabe)',
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Wilaya (optionnel)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adresse (optionnel)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Telephone (optionnel)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _ordNumberCtrl,
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
          controller: _noteCtrl,
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
        ...List.generate(_lines.length, (index) {
          final line = _lines[index];
          final currentName = line.nameCtrl.text.trim();
          final filteredMedicaments = _cabinetMedicaments
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
                          labelText: 'Medicament',
                          prefixIcon: Icon(Icons.medication_outlined),
                        ),
                        style: TextStyle(
                          fontWeight: _canUpdateCabinetMedicaments
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        onChanged: (_) => setState(() {}),
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      ),
                      if (_cabinetMedicaments.isNotEmpty) ...[
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
                                    fontWeight: _canUpdateCabinetMedicaments
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                onPressed: () =>
                                    setState(() => line.nameCtrl.text = m),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Base medicaments',
                              onSelected: (value) =>
                                  setState(() => line.nameCtrl.text = value),
                              itemBuilder: (_) => _cabinetMedicaments
                                  .map(
                                    (m) => PopupMenuItem<String>(
                                      value: m,
                                      child: Text(
                                        m,
                                        style: TextStyle(
                                          fontWeight:
                                              _canUpdateCabinetMedicaments
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
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: line.qteCtrl,
                    decoration: const InputDecoration(labelText: 'Qte'),
                    onChanged: (_) => setState(() {}),
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
            onPressed: () => setState(() => _lines.add(_OrdonnanceLine())),
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
        _buildOrdonnancePreview(
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
          seanceNumero: '',
          ordonnanceNumero: _ordNumberCtrl.text.trim(),
          lines: _lines,
        ),
      ],
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
                            if (ordonnanceNumero.isNotEmpty)
                              Text(
                                'Ordonnance N°: $ordonnanceNumero',
                                style: TextStyle(color: muted, fontSize: 12),
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
                      'ORDONNANCE MEDECIN',
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
                  Text('PRESCRIPTION', style: label()),
                  const SizedBox(height: 8),
                  if (visibleLines.isEmpty)
                    Text('Aucune prescription', style: TextStyle(color: muted))
                  else
                    ...visibleLines.asMap().entries.map((entry) {
                      final numero = entry.key + 1;
                      final line = entry.value;
                      final name = line.nameCtrl.text.trim();
                      final qte = line.qteCtrl.text.trim();
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  if (qte.isNotEmpty)
                                    Text(
                                      'Qte : $qte',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
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

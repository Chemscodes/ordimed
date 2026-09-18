import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

class PdfFonts {
  final pw.Font base;
  final pw.Font bold;
  final pw.Font medium;
  final pw.Font mono;
  final pw.Font arabic;

  const PdfFonts({
    required this.base,
    required this.bold,
    required this.medium,
    required this.mono,
    required this.arabic,
  });
}

/// Palette du document médical — reprise de la maquette `design/Ordonnance.dc.html`.
class _DocColors {
  static const accent = PdfColor.fromInt(0xFF0E7C6B);
  static const accentTint = PdfColor.fromInt(0xFFE6F2EF);
  static const ink = PdfColor.fromInt(0xFF10171A);
  static const muted = PdfColor.fromInt(0xFF5A686D);
  static const borderLight = PdfColor.fromInt(0xFFD9E2E4);
  static const borderLighter = PdfColor.fromInt(0xFFE8EEEF);
}

class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  /// IBM Plex — la même famille que le reste de l'app (`AppTheme`) — pour
  /// que le document imprimé ait l'air de venir du même logiciel que
  /// l'écran qui l'a produit, pas d'un générateur PDF générique.
  Future<PdfFonts> resolveFonts() async {
    pw.Font base = pw.Font.helvetica();
    pw.Font bold = pw.Font.helveticaBold();
    pw.Font medium = base;
    pw.Font mono = base;
    pw.Font arabic = base;
    try {
      base = await PdfGoogleFonts.iBMPlexSansRegular();
      medium = await PdfGoogleFonts.iBMPlexSansMedium();
      bold = await PdfGoogleFonts.iBMPlexSansBold();
      // IBM Plex Mono (Regular et Medium) fait planter le sous-échantillonnage
      // de glyphes du package `pdf` (RangeError dans TtfParser.readGlyph) —
      // Roboto Mono est la police mono la plus éprouvée avec ce package.
      mono = await PdfGoogleFonts.robotoMonoMedium();
    } catch (_) {}
    try {
      arabic = await PdfGoogleFonts.iBMPlexSansArabicMedium();
    } catch (_) {
      arabic = base;
    }
    return PdfFonts(
      base: base,
      bold: bold,
      medium: medium,
      mono: mono,
      arabic: arabic,
    );
  }

  Future<Uint8List> buildMedicalPdfBytes({
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
    final fonts = await resolveFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
    );

    final c = _DocColors.accent;
    final ink = _DocColors.ink;
    final muted = _DocColors.muted;
    final borderLight = _DocColors.borderLight;
    final borderLighter = _DocColors.borderLighter;
    final tint = _DocColors.accentTint;

    final nameStyle = pw.TextStyle(
      font: fonts.bold,
      fontSize: 14.5,
      color: ink,
    );
    final subtitleStyle = pw.TextStyle(
      font: fonts.medium,
      fontSize: 10.5,
      color: muted,
    );
    final mutedStyle = pw.TextStyle(
      font: fonts.base,
      fontSize: 9.5,
      color: muted,
    );
    final monoStyle = pw.TextStyle(
      font: fonts.mono,
      fontSize: 10,
      color: muted,
    );
    final labelStyle = pw.TextStyle(
      font: fonts.medium,
      fontSize: 8.5,
      letterSpacing: 0.4,
      color: muted,
    );
    final titleStyle = pw.TextStyle(
      font: fonts.bold,
      fontSize: 16,
      letterSpacing: 0.4,
      color: ink,
    );
    final sectionLabelStyle = pw.TextStyle(
      font: fonts.medium,
      fontSize: 9.5,
      letterSpacing: 0.3,
      color: muted,
    );
    final bodyStyle = pw.TextStyle(
      font: fonts.medium,
      fontSize: 13,
      color: ink,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 36),
        header: (context) => pw.Container(
          height: 4,
          margin: const pw.EdgeInsets.only(bottom: 18),
          color: c,
        ),
        build: (context) => [
          // ── En-tête bilingue ──────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      doctorName.isEmpty ? ' ' : doctorName,
                      style: nameStyle,
                    ),
                    if (doctorSubtitle.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(doctorSubtitle, style: subtitleStyle),
                      ),
                    if (address.isNotEmpty || wilaya.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 8),
                        child: pw.Text(
                          [
                            address,
                            wilaya,
                          ].where((s) => s.isNotEmpty).join(' — '),
                          style: mutedStyle,
                        ),
                      ),
                    if (phone.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text(
                          phone,
                          style: monoStyle.copyWith(
                            color: muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (doctorNameAr.isNotEmpty)
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Text(
                          doctorNameAr,
                          style: pw.TextStyle(
                            font: fonts.arabic,
                            fontSize: 13,
                            color: ink,
                          ),
                        ),
                      ),
                    if (documentNumber.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 5),
                        child: pw.Text(
                          '$documentNumberLabel : $documentNumber',
                          style: monoStyle.copyWith(color: c),
                        ),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text('Date : $dateStr', style: monoStyle),
                    ),
                    if (seanceNumero.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          'Seance : $seanceNumero',
                          style: monoStyle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: borderLight, thickness: 1.2),
          pw.SizedBox(height: 16),
          // ── Identité patient ──────────────────────────────
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PATIENT', style: labelStyle),
              pw.SizedBox(height: 5),
              pw.Text(
                '$patientNom $patientPrenom'.trim().isEmpty
                    ? '—'
                    : '$patientNom $patientPrenom'.trim(),
                style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: ink),
              ),
              if (patientAge.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text('$patientAge ans', style: mutedStyle),
                ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Center(child: pw.Text(title, style: titleStyle)),
          pw.SizedBox(height: 20),
          // ── Contenu ────────────────────────────────────────
          pw.Text(sectionTitle.toUpperCase(), style: sectionLabelStyle),
          pw.SizedBox(height: 10),
          if (entries.isEmpty)
            pw.Text(emptyLabel, style: mutedStyle)
          else
            pw.Column(
              children: entries.asMap().entries.map((e) {
                final numero = (e.key + 1).toString().padLeft(2, '0');
                // Le package `pdf` refuse un `borderRadius` avec une bordure
                // non uniforme (le filet coloré à gauche seul essayé
                // d'abord) — et une `Row` en `stretch` pour simuler cette
                // barre d'accent a fait boucler la pagination (hauteur non
                // bornée). Une bordure uniforme fine reste sûre avec le
                // package, la pastille numérotée porte déjà l'accent teal.
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFFAFBFB),
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: borderLighter, width: 1),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 22,
                        height: 22,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          color: tint,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          numero,
                          style: pw.TextStyle(
                            font: fonts.mono,
                            fontSize: 9,
                            color: c,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Text(
                          e.value,
                          style: bodyStyle.copyWith(
                            font: fonts.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
        footer: (context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (address.isNotEmpty)
                        pw.Text(address, style: mutedStyle),
                      if (phone.isNotEmpty) pw.Text(phone, style: mutedStyle),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Signature et cachet', style: mutedStyle),
                    pw.SizedBox(height: 24),
                    pw.Container(height: 1, width: 160, color: borderLight),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: borderLighter, thickness: 1),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  doctorName,
                  style: pw.TextStyle(
                    font: fonts.mono,
                    fontSize: 8.5,
                    color: muted,
                  ),
                ),
                pw.Text(
                  dateStr,
                  style: pw.TextStyle(
                    font: fonts.mono,
                    fontSize: 8.5,
                    color: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  String sanitizeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ascii = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return ascii.isEmpty ? 'document' : ascii;
  }

  Future<File> writePdfTemp(Uint8List bytes, String baseName) async {
    final dir = Directory.systemTemp;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safe = sanitizeFileName(baseName);
    final file = File('${dir.path}\\${safe}_$stamp.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> openPdfInBrowser(File file) async {
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
      debugPrint('openPdfInBrowser: launchUrl opened=$opened url=$url');
      if (!opened && Platform.isWindows) {
        try {
          await Process.start('cmd', ['/c', 'start', '', url.toString()]);
        } catch (e) {
          debugPrint('openPdfInBrowser: cmd start (url) failed: $e');
        }
      }
      Future.delayed(const Duration(minutes: 2), () {
        try {
          server?.close(force: true);
        } catch (_) {}
      });
    } catch (e, st) {
      debugPrint('openPdfInBrowser error: $e\n$st');
      if (Platform.isWindows) {
        try {
          await Process.start('cmd', ['/c', 'start', '', file.path]);
        } catch (e2) {
          debugPrint('openPdfInBrowser: cmd start (file) failed: $e2');
        }
      }
    }
  }

  Future<void> printOrdonnancePdf({
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
      final bytes = await buildMedicalPdfBytes(
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
      final file = await writePdfTemp(
        bytes,
        'Ordonnance_${patientNom}_${ordonnanceNumero}_$dateStr',
      );
      await openPdfInBrowser(file);
    } catch (e, st) {
      debugPrint('printOrdonnancePdf error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la generation du PDF')),
        );
      }
    }
  }

  Future<void> printBilanPdf({
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
      final bytes = await buildMedicalPdfBytes(
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
      final file = await writePdfTemp(bytes, 'Bilan_${patientNom}_$dateStr');
      await openPdfInBrowser(file);
    } catch (e, st) {
      debugPrint('printBilanPdf error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la generation du PDF')),
        );
      }
    }
  }
}

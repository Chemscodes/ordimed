import 'dart:io';

import 'package:flutter/services.dart' show Uint8List;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/clinical.dart';
import '../core/format.dart' as fmt;
import '../core/lettres.dart';

/// Reçu de versement.
///
/// Un versement était encaissé et rien n'était imprimé : le patient repartait
/// sans trace, et le cabinet non plus. Une contestation trois mois plus tard
/// ne se tranchait avec rien.
///
/// Le fichier est écrit sur le disque, pas dans un dossier temporaire : un
/// reçu est une pièce comptable, il se retrouve.
class RecuService {
  /// Données d'un reçu.
  ///
  /// Le numéro n'est pas une séquence : deux postes qui encaissent en même
  /// temps produiraient le même. Il dérive de l'horodatage, ce qui le rend
  /// unique et lisible sans coordination entre les postes.
  static String numeroPour(DateTime date) {
    String p(int v, [int n = 2]) => v.toString().padLeft(n, '0');
    return '${date.year}${p(date.month)}${p(date.day)}'
        '-${p(date.hour)}${p(date.minute)}${p(date.second)}';
  }

  static String dossierRecus() {
    final base =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return '$base${Platform.pathSeparator}Documents'
        '${Platform.pathSeparator}Ordimed'
        '${Platform.pathSeparator}recus';
  }

  static String _nomSur(String valeur) {
    final propre = valeur.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return propre.isEmpty ? 'patient' : propre.replaceAll(' ', '_');
  }

  /// Construit le PDF.
  Future<Uint8List> construire({
    required String cabinet,
    required String adresse,
    required String telephone,
    required String patient,
    required double montant,
    required DateTime date,
    required Reglement reglement,
    required String encaissePar,
    String motif = '',
    String? numero,
  }) async {
    pw.Font base = pw.Font.helvetica();
    pw.Font gras = pw.Font.helveticaBold();
    try {
      base = await PdfGoogleFonts.notoSansRegular();
      gras = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      // Sans réseau, les polices Google ne se chargent pas. Helvetica rend
      // un reçu moins joli mais parfaitement valide — refuser d'imprimer
      // parce qu'une police manque serait absurde.
    }

    final num = numero ?? numeroPour(date);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: base, bold: gras),
    );

    final petit = pw.TextStyle(font: base, fontSize: 9.5);
    final label = pw.TextStyle(font: gras, fontSize: 9);

    pw.Widget ligne(String etiquette, String valeur, {bool fort = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 130,
                child: pw.Text(etiquette, style: label),
              ),
              pw.Expanded(
                child: pw.Text(
                  valeur,
                  style: pw.TextStyle(
                    font: fort ? gras : base,
                    fontSize: fort ? 12 : 10.5,
                  ),
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        cabinet.isEmpty ? 'Cabinet médical' : cabinet,
                        style: pw.TextStyle(font: gras, fontSize: 13),
                      ),
                      if (adresse.isNotEmpty) pw.Text(adresse, style: petit),
                      if (telephone.isNotEmpty)
                        pw.Text('Tél. $telephone', style: petit),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('REÇU N° $num', style: label),
                    pw.Text(fmt.dateTime(date), style: petit),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(thickness: 0.8),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'REÇU DE VERSEMENT',
                style: pw.TextStyle(font: gras, fontSize: 15, letterSpacing: 2),
              ),
            ),
            pw.SizedBox(height: 16),
            ligne('Reçu de', patient),
            if (motif.isNotEmpty)
              ligne('Motif', fmt.capitalize(fmt.humanize(motif))),
            ligne('Montant versé', fmt.money(montant), fort: true),
            pw.SizedBox(height: 4),
            // La somme en lettres est ce qui empêche d'ajouter un zéro au
            // stylo sur le chiffre.
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.6),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(
                'Arrêté la présente quittance à la somme de : '
                '${montantEnLettres(montant)}.',
                style: pw.TextStyle(font: base, fontSize: 10, lineSpacing: 2),
              ),
            ),
            pw.SizedBox(height: 14),
            // L'état du dossier après ce versement : c'est la question que
            // le patient pose juste après avoir payé.
            if (reglement.prix != null) ...[
              ligne('Total dû', fmt.money(reglement.prix)),
              ligne('Total versé', fmt.money(reglement.verse)),
              ligne(
                reglement.solde ? 'Solde' : 'Reste à payer',
                reglement.solde ? 'Dossier soldé' : fmt.money(reglement.reste),
                fort: !reglement.solde,
              ),
            ] else
              ligne('Total versé', fmt.money(reglement.verse)),
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    encaissePar.isEmpty
                        ? ''
                        : 'Encaissé par : $encaissePar',
                    style: petit,
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Signature et cachet', style: petit),
                    pw.SizedBox(height: 34),
                    pw.Container(width: 130, height: 0.8, color: PdfColors.grey),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Construit le reçu, l'enregistre et l'ouvre.
  ///
  /// Renvoie le fichier écrit — l'appelant peut ainsi dire *où* il est, ce
  /// qui compte plus qu'on ne croit quand une imprimante refuse de répondre.
  Future<File> imprimer({
    required String cabinet,
    required String adresse,
    required String telephone,
    required String patient,
    required double montant,
    required DateTime date,
    required Reglement reglement,
    required String encaissePar,
    String motif = '',
  }) async {
    final numero = numeroPour(date);
    final bytes = await construire(
      cabinet: cabinet,
      adresse: adresse,
      telephone: telephone,
      patient: patient,
      montant: montant,
      date: date,
      reglement: reglement,
      encaissePar: encaissePar,
      motif: motif,
      numero: numero,
    );

    final dossier = Directory(dossierRecus());
    if (!dossier.existsSync()) dossier.createSync(recursive: true);

    final fichier = File(
      '${dossier.path}${Platform.pathSeparator}'
      'recu-$numero-${_nomSur(patient)}.pdf',
    );
    await fichier.writeAsBytes(bytes, flush: true);

    // Ouvre avec le lecteur PDF du poste : c'est de là qu'on imprime, et le
    // fichier reste sur le disque une fois la fenêtre fermée.
    await launchUrl(fichier.uri);
    return fichier;
  }
}

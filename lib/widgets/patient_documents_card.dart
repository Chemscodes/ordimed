import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';

/// Pièces jointes du dossier patient : résultats de labo, radios scannées.
///
/// Distinct des onglets Ordonnances/Bilans, qui couvrent les documents
/// cliniques texte déjà générés par l'app — ici ce sont des fichiers
/// externes (PDF, photo) apportés par le patient ou le cabinet.
class PatientDocumentsCard extends StatefulWidget {
  final String patientId;

  const PatientDocumentsCard({super.key, required this.patientId});

  @override
  State<PatientDocumentsCard> createState() => _PatientDocumentsCardState();
}

class _PatientDocumentsCardState extends State<PatientDocumentsCard> {
  final _service = StorageService();
  Future<List<PieceJointe>>? _futureListe;
  bool _envoiEnCours = false;

  @override
  void initState() {
    super.initState();
    _rafraichir();
  }

  void _rafraichir() {
    setState(() => _futureListe = _service.lister(widget.patientId));
  }

  Future<void> _ajouter() async {
    final resultat = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final fichier = resultat?.files.single;
    if (fichier == null) return;

    setState(() => _envoiEnCours = true);
    try {
      await _service.deposer(patientId: widget.patientId, fichier: fichier);
      _rafraichir();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'envoi du fichier')),
        );
      }
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  Future<void> _supprimer(PieceJointe piece) async {
    try {
      await _service.supprimer(
        patientId: widget.patientId,
        nomStockage: piece.nomStockage,
      );
      _rafraichir();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
      }
    }
  }

  Future<void> _ouvrir(PieceJointe piece) async {
    final uri = Uri.tryParse(piece.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  IconData _iconePour(String nom) {
    final ext = nom.toLowerCase().split('.').last;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['jpg', 'jpeg', 'png'].contains(ext)) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _tailleLisible(int octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) {
      return '${(octets / 1024).toStringAsFixed(0)} Ko';
    }
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _dateLisible(DateTime d) {
    final j = d.day.toString().padLeft(2, '0');
    final m = d.month.toString().padLeft(2, '0');
    return '$j/$m/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FluentButton(
              label: 'Ajouter un document',
              icon: Icons.upload_file_outlined,
              onPressed: _envoiEnCours ? null : _ajouter,
              isLoading: _envoiEnCours,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PieceJointe>>(
            future: _futureListe,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Impossible de charger les pièces jointes'),
                );
              }
              final pieces = snapshot.data ?? const [];
              if (pieces.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Aucune pièce jointe',
                      style: TextStyle(color: AppTheme.ink2(context)),
                    ),
                  ),
                );
              }
              return Column(
                children: pieces.map((p) {
                  return FluentCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    onTap: () => _ouvrir(p),
                    child: Row(
                      children: [
                        Icon(
                          _iconePour(p.nomAffiche),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.nomAffiche,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_tailleLisible(p.taille)} · ${_dateLisible(p.ajouteLe)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.ink2(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _supprimer(p),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

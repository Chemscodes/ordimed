import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart' as fmt;
import '../services/backup_service.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_button.dart';
import '../ui/fluent_card.dart';
import '../ui/info_display.dart';

/// Sauvegardes du cabinet.
///
/// Firestore n'a pas de corbeille. Un profil supprimé, un dossier vidé, un
/// mauvais clic : jusqu'ici rien ne se rattrapait. C'était le seul dégât
/// irréversible que l'app pouvait causer.
class SauvegardePage extends StatefulWidget {
  final String parentUid;

  const SauvegardePage({super.key, required this.parentUid});

  @override
  State<SauvegardePage> createState() => _SauvegardePageState();
}

class _SauvegardePageState extends State<SauvegardePage> {
  final _service = BackupService();

  bool _enCours = false;
  String _etape = '';
  BackupResult? _dernier;
  String? _erreur;
  List<File> _fichiers = const [];

  @override
  void initState() {
    super.initState();
    _rafraichir();
  }

  void _rafraichir() {
    setState(() => _fichiers = BackupService.sauvegardesExistantes());
  }

  Future<void> _sauvegarder() async {
    setState(() {
      _enCours = true;
      _erreur = null;
      _etape = 'Préparation…';
    });
    try {
      final res = await _service.exporter(
        parentUid: widget.parentUid,
        onProgress: (e) {
          if (mounted) setState(() => _etape = e);
        },
      );
      if (!mounted) return;
      setState(() => _dernier = res);
      _rafraichir();
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _restaurer(File fichier) async {
    final nom = fichier.path.split(Platform.pathSeparator).last;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nom, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'Les données du fichier seront réécrites par-dessus les '
              'données actuelles.\n\n'
              'Rien n\'est supprimé : ce qui a été créé depuis cette '
              'sauvegarde reste en place. En revanche, un dossier modifié '
              'depuis retrouvera son ancienne version.',
              style: TextStyle(height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() {
      _enCours = true;
      _erreur = null;
      _etape = 'Restauration…';
    });
    try {
      final rapport = await _service.restaurer(
        parentUid: widget.parentUid,
        fichier: fichier,
        onProgress: (e) {
          if (mounted) setState(() => _etape = e);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${rapport.documents} documents restaurés'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _ouvrirDossier() async {
    final dossier = Directory(BackupService.dossierParDefaut());
    if (!dossier.existsSync()) dossier.createSync(recursive: true);
    await launchUrl(dossier.uri);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegardes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FluentCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  titre: 'Sauvegarder maintenant',
                  icone: Icons.shield_outlined,
                ),
                const SizedBox(height: 12),
                Text(
                  'Copie tous les profils, dossiers patients, documents, '
                  'rendez-vous et versements dans un fichier sur ce PC. '
                  'Le fichier ne dépend plus d\'Internet ni de Firebase.',
                  style: TextStyle(
                    height: 1.5,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FluentButton(
                      label: _enCours ? 'En cours…' : 'Sauvegarder',
                      icon: Icons.download_outlined,
                      onPressed: _enCours ? null : _sauvegarder,
                    ),
                    const SizedBox(width: 10),
                    FluentButton(
                      label: 'Ouvrir le dossier',
                      icon: Icons.folder_open_outlined,
                      onPressed: _enCours ? null : _ouvrirDossier,
                    ),
                  ],
                ),
                if (_enCours) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _etape,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (_erreur != null) ...[
                  const SizedBox(height: 16),
                  _Alerte(texte: _erreur!, couleur: scheme.error),
                ],
                if (_dernier != null && !_enCours) ...[
                  const SizedBox(height: 16),
                  _Alerte(
                    texte:
                        '${_dernier!.documents} documents · '
                        '${_dernier!.profils} profils · ${_dernier!.taille}\n'
                        '${_dernier!.chemin}',
                    couleur: const Color(0xFF16A34A),
                    icone: Icons.check_circle_outline,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FluentCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  titre: 'Sauvegardes sur ce PC',
                  icone: Icons.history,
                  compteur: _fichiers.isEmpty ? null : _fichiers.length,
                  action: IconButton(
                    tooltip: 'Actualiser',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _rafraichir,
                  ),
                ),
                const SizedBox(height: 8),
                if (_fichiers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucune sauvegarde. Rien n\'est protégé pour l\'instant.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                else
                  for (final f in _fichiers)
                    _LigneFichier(
                      fichier: f,
                      actif: !_enCours,
                      onRestaurer: () => _restaurer(f),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FluentCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  titre: 'Ce qu\'il faut savoir',
                  icone: Icons.info_outline,
                ),
                const SizedBox(height: 12),
                const _Point(
                  'Une sauvegarde sur le même disque que rien d\'autre ne '
                  'protège pas d\'un disque en panne. Copie le fichier sur '
                  'une clé USB ou un cloud de temps en temps.',
                ),
                const _Point(
                  'La restauration réécrit sans supprimer : elle ne peut pas '
                  'faire disparaître un dossier créé après la sauvegarde.',
                ),
                const _Point(
                  'Le fichier contient des données médicales en clair. '
                  'Il vaut ce que vaut l\'accès à ce PC.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneFichier extends StatelessWidget {
  final File fichier;
  final bool actif;
  final VoidCallback onRestaurer;

  const _LigneFichier({
    required this.fichier,
    required this.actif,
    required this.onRestaurer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stat = fichier.statSync();
    final nom = fichier.path.split(Platform.pathSeparator).last;
    final ko = stat.size / 1024;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmt.capitalize(fmt.relativeDay(stat.modified))} · '
                  '${ko < 1024 ? '${ko.toStringAsFixed(0)} Ko' : '${(ko / 1024).toStringAsFixed(1)} Mo'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FluentButton(
            label: 'Restaurer',
            icon: Icons.restore,
            compact: true,
            onPressed: actif ? onRestaurer : null,
          ),
        ],
      ),
    );
  }
}

class _Alerte extends StatelessWidget {
  final String texte;
  final Color couleur;
  final IconData icone;

  const _Alerte({
    required this.texte,
    required this.couleur,
    this.icone = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          couleur.withValues(alpha: 0.1),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              texte,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final String texte;

  const _Point(this.texte);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

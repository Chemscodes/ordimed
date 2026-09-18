import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/backend_config.dart';
import 'reglage_serveur.dart';

/// Le choix de la base, depuis l'écran de connexion.
///
/// C'est là qu'il doit être : on découvre qu'une base ne répond pas en
/// essayant de se connecter, pas dans un menu qui n'est accessible qu'une
/// fois entré.
///
/// Changer de base demande un redémarrage, et c'est dit franchement plutôt
/// que masqué : les écrans gardent des abonnements ouverts sur la base
/// active, les rebrancher à chaud demanderait de tous les fermer
/// proprement. Le redémarrage est aussi le moment où l'on vérifie que
/// l'autre base répond.
class ChoixBase extends StatefulWidget {
  const ChoixBase({super.key});

  /// Rend `true` si quelque chose a changé et que l'écran appelant doit se
  /// redessiner.
  static Future<bool> ouvrir(BuildContext context) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => const ChoixBase(),
    );
    return r ?? false;
  }

  @override
  State<ChoixBase> createState() => _ChoixBaseState();
}

class _ChoixBaseState extends State<ChoixBase> {
  late Backend _choix = BackendConfig.actif;
  bool _change = false;

  /// La bascule est-elle demandée ?
  bool get _bascule => _choix != BackendConfig.actif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Où sont les données du cabinet'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Option(
              valeur: Backend.firebase,
              groupe: _choix,
              titre: 'Firebase',
              detail:
                  'Rien à installer. Les postes se synchronisent entre eux, '
                  'et le cabinet continue de travailler pendant une coupure '
                  'internet.',
              onChange: (v) => setState(() => _choix = v),
            ),
            const SizedBox(height: 8),
            _Option(
              valeur: Backend.mongo,
              groupe: _choix,
              titre: 'Serveur du cabinet',
              detail:
                  'Les données restent chez vous. Demande qu\'un poste fasse '
                  'tourner le serveur et reste allumé.',
              onChange: (v) => setState(() => _choix = v),
            ),

            // L'adresse ne se règle que pour le serveur local, et seulement
            // une fois qu'il est choisi : la proposer sous Firebase ferait
            // croire qu'elle y sert à quelque chose.
            if (_choix == Backend.mongo) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Adresse : ${ApiClient.instance.baseUrl}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await ReglageServeur.ouvrir(context)) {
                        if (mounted) setState(() => _change = true);
                      }
                    },
                    child: const Text('Modifier'),
                  ),
                ],
              ),
            ],

            if (_bascule) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Le changement prendra effet au prochain démarrage '
                        'd\'Ordimed.\n\nLes deux bases sont distinctes : ce '
                        'qui a été saisi dans l\'une ne se trouve pas dans '
                        'l\'autre.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _change),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () async {
            if (_bascule) await BackendConfig.definir(_choix);
            if (context.mounted) {
              Navigator.pop(context, _change || _bascule);
            }
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.valeur,
    required this.groupe,
    required this.titre,
    required this.detail,
    required this.onChange,
  });

  final Backend valeur;
  final Backend groupe;
  final String titre;
  final String detail;
  final ValueChanged<Backend> onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choisi = valeur == groupe;

    return InkWell(
      onTap: () => onChange(valeur),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: choisi
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: choisi ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<Backend>(
              value: valeur,
              groupValue: groupe,
              onChanged: (v) => v == null ? null : onChange(v),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../ui/app_theme.dart';

/// Où se trouve le serveur du cabinet.
///
/// Un cabinet a plusieurs postes, et un seul fait tourner le serveur. Les
/// autres doivent savoir où le joindre.
///
/// Figer cette adresse à la compilation obligerait à produire un binaire par
/// cabinet, avec son IP en dur — et à en refaire un le jour où la box change
/// de plage d'adresses.
class ReglageServeur extends StatefulWidget {
  const ReglageServeur({super.key});

  /// Ouvre le réglage et indique si l'adresse a changé.
  static Future<bool> ouvrir(BuildContext context) async {
    final change = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520),
          child: ReglageServeur(),
        ),
      ),
    );
    return change ?? false;
  }

  @override
  State<ReglageServeur> createState() => _ReglageServeurState();
}

class _ReglageServeurState extends State<ReglageServeur> {
  late final TextEditingController _ctrl = TextEditingController(
    text: ApiClient.instance.baseUrl,
  );

  bool _test = false;

  /// `null` tant qu'aucun test n'a été fait.
  bool? _joignable;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tester() async {
    setState(() {
      _test = true;
      _joignable = null;
    });
    final ok = await ApiClient.instance.tester(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _test = false;
      _joignable = ok;
    });
  }

  Future<void> _enregistrer() async {
    await ApiClient.instance.definirServeur(_ctrl.text);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              const Text(
                'Serveur du cabinet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Un seul poste du cabinet fait tourner le serveur. Les autres '
            'indiquent ici son adresse sur le réseau local.',
            style: TextStyle(
              height: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Adresse du serveur',
              hintText: '192.168.1.20:4000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            onSubmitted: (_) => _tester(),
          ),
          const SizedBox(height: 8),
          Text(
            'Sur le poste serveur lui-même : localhost:4000',
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (_joignable != null) ...[
            const SizedBox(height: 14),
            _Verdict(joignable: _joignable!),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _test ? null : _tester,
                icon: _test
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check, size: 18),
                label: const Text('Tester'),
              ),
              const SizedBox(width: 10),
              // Enregistrer reste possible sans test concluant : le serveur
              // peut être momentanément éteint, et forcer un test réussi
              // empêcherait de configurer un poste avant d'allumer l'autre.
              FilledButton(
                onPressed: _test ? null : _enregistrer,
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  final bool joignable;

  const _Verdict({required this.joignable});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = joignable ? const Color(0xFF16A34A) : scheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
          Icon(
            joignable ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: couleur,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              joignable
                  ? 'Le serveur répond.'
                  : 'Aucune réponse. Vérifie que le poste serveur est '
                        'allumé, que Docker y tourne, et que le pare-feu '
                        'laisse passer le port 4000.',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

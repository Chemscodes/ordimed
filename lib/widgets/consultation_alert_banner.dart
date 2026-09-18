import 'package:flutter/material.dart';

import '../pages/consultation_page.dart';
import '../services/api_service.dart';
import '../ui/app_theme.dart';

/// Bandeau d'alerte : « un patient vous attend en consultation ».
///
/// L'assistant passe un patient en consultation depuis son propre écran,
/// mais rien ne le signalait côté médecin — il fallait qu'il pense lui-même
/// à regarder sa salle d'attente. Pour un médecin peu à l'aise avec
/// l'ordinateur, un changement d'état silencieux dans une liste ne suffit
/// pas : il faut quelque chose d'impossible à manquer, visible depuis
/// n'importe quel onglet du tableau de bord, et qui mène directement à la
/// séance guidée en un seul geste.
///
/// Reste affiché tant que le médecin n'a pas cliqué dessus — pas de
/// disparition automatique, qui risquerait de passer inaperçue.
class ConsultationAlertBanner extends StatefulWidget {
  final String parentUid;
  final String profileId;

  /// Valeurs de `doctorId` qui désignent ce médecin — au-delà de son propre
  /// `profileId`, un patient assigné au médecin principal porte parfois le
  /// littéral `'medecin_principal'` au lieu d'un identifiant de profil réel
  /// (même convention que `KpiRow`). Par défaut, seul `profileId`.
  final Set<String>? allowedDoctorIds;

  const ConsultationAlertBanner({
    super.key,
    required this.parentUid,
    required this.profileId,
    this.allowedDoctorIds,
  });

  @override
  State<ConsultationAlertBanner> createState() =>
      _ConsultationAlertBannerState();
}

class _ConsultationAlertBannerState extends State<ConsultationAlertBanner> {
  /// Alertes déjà ouvertes cette session — pas besoin qu'elles reviennent
  /// tant que le patient reste en consultation.
  final Set<String> _traitees = <String>{};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ApiService.instance.salleAttenteFlux(profileId: widget.profileId),
      builder: (context, snap) {
        final entries = snap.data ?? const <Map<String, dynamic>>[];
        final actives = entries.where((e) {
          final status = (e['status'] ?? '').toString();
          if (status != 'in_consultation') return false;
          if (e['closedAt'] != null) return false;
          final doctorId = (e['doctorId'] ?? '').toString();
          final autorises = widget.allowedDoctorIds ?? {widget.profileId};
          if (!autorises.contains(doctorId)) return false;
          final id = (e['id'] ?? '').toString();
          return id.isNotEmpty && !_traitees.contains(id);
        }).toList();

        if (actives.isEmpty) return const SizedBox.shrink();

        return Column(
          children: actives
              .map(
                (entry) => _Bandeau(
                  entry: entry,
                  onTap: () => _ouvrir(context, entry),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _ouvrir(BuildContext context, Map<String, dynamic> entry) async {
    setState(() => _traitees.add((entry['id'] ?? '').toString()));
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultationPage(
          parentUid: widget.parentUid,
          profileId: widget.profileId,
          waitingId: (entry['id'] ?? '').toString(),
          waitingData: entry,
        ),
      ),
    );
  }
}

class _Bandeau extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  const _Bandeau({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = (entry['patientNom'] ?? '').toString();
    final prenom = (entry['patientPrenom'] ?? '').toString();
    final nomComplet = '$nom $prenom'.trim();
    final menthe = AppTheme.menthe(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: menthe,
        borderRadius: BorderRadius.circular(AppTheme.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.black87),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nomComplet.isEmpty
                        ? 'Un patient vous attend en consultation'
                        : '$nomComplet vous attend en consultation',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Text(
                  'Commencer',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.black87),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

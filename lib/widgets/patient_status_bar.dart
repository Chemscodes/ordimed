import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../ui/app_theme.dart';

enum _VisitStatus { notInRoom, waiting, inConsultation, done }

/// Barre contextuelle affichee en haut du dossier patient.
///
/// Reflete l'etat courant du patient dans la salle d'attente du jour, sans
/// dupliquer de logique : elle lit le meme flux (`salleAttenteFlux`) que les
/// dashboards et applique les memes regles de statut (`status`, `closedAt`).
class PatientStatusBar extends StatelessWidget {
  final String patientId;

  const PatientStatusBar({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ApiService.instance.salleAttenteFlux(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <Map<String, dynamic>>[];
        Map<String, dynamic>? entry;
        for (final e in entries) {
          if ('${e['patientId']}' == patientId) {
            entry = e;
            break;
          }
        }
        final status = _statusFor(entry);
        final spec = _specFor(context, status);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: spec.color.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.10,
            ),
            border: Border(
              left: BorderSide(color: spec.color, width: 4),
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              Icon(spec.icon, size: 18, color: spec.color),
              const SizedBox(width: 8),
              Text(
                spec.label,
                style: TextStyle(
                  color: spec.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _VisitStatus _statusFor(Map<String, dynamic>? entry) {
    if (entry == null) return _VisitStatus.notInRoom;
    final status = (entry['status'] ?? '').toString();
    final closed = entry['closedAt'];
    if (status == 'done' || closed != null) return _VisitStatus.done;
    if (status == 'in_consultation') return _VisitStatus.inConsultation;
    return _VisitStatus.waiting;
  }

  _StatusSpec _specFor(BuildContext context, _VisitStatus status) {
    final ink2 = AppTheme.ink2(context);
    switch (status) {
      case _VisitStatus.notInRoom:
        return _StatusSpec(ink2, Icons.person_outline, 'Pas en salle');
      case _VisitStatus.waiting:
        return _StatusSpec(
          AppTheme.ambre(context),
          Icons.meeting_room_outlined,
          'En salle d\'attente',
        );
      case _VisitStatus.inConsultation:
        return _StatusSpec(
          AppTheme.menthe(context),
          Icons.monitor_heart,
          'En consultation',
        );
      case _VisitStatus.done:
        return _StatusSpec(ink2, Icons.check_circle_outline, 'Visite terminee');
    }
  }
}

class _StatusSpec {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusSpec(this.color, this.icon, this.label);
}

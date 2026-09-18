import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../services/stats_service.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_card.dart';
import 'daily_versements_card.dart'
    show sommeVersementsDuJour, sommeVersementsDuJourDepuisStats;

/// Rangee de 4 indicateurs temps reel pour les tableaux de bord.
///
/// Patients du jour / En attente / En consultation viennent de la meme
/// file (`salleAttenteFlux`) que la salle d'attente elle-meme — meme
/// decoupage que celui deja utilise dans les dashboards (`status`,
/// `closedAt`). Recettes du jour lit d'abord l'agregat `daily_stats` du
/// jour ([sommeVersementsDuJourDepuisStats]) — un seul petit document au
/// lieu de tous les patients du cabinet — et ne retombe sur
/// [sommeVersementsDuJour] (qui les parcourt) que si cet agregat ne
/// renseigne pas le detail par medecin dont la portee a besoin.
class KpiRow extends StatelessWidget {
  final String parentUid;
  final String profileId;
  final Set<String>? allowedDoctorIds;

  const KpiRow({
    super.key,
    required this.parentUid,
    required this.profileId,
    this.allowedDoctorIds,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ApiService.instance.salleAttenteFlux(profileId: profileId),
      builder: (context, salleSnap) {
        final entries = salleSnap.data ?? const <Map<String, dynamic>>[];
        var waiting = 0;
        var inConsultation = 0;
        for (final e in entries) {
          final status = (e['status'] ?? '').toString();
          final closed = e['closedAt'];
          final isDone = status == 'done' || closed != null;
          if (isDone) continue;
          if (status == 'in_consultation') {
            inConsultation++;
          } else {
            waiting++;
          }
        }
        final patientsToday = salleSnap.hasData ? entries.length : null;
        final todayKey = StatsService.dayKeyOf(DateTime.now());

        return StreamBuilder<Map<String, dynamic>?>(
          stream: StatsService().dailyStatsDoc(
            parentUid: parentUid,
            dayKey: todayKey,
          ),
          builder: (context, statsSnap) {
            final depuisStats =
                statsSnap.connectionState == ConnectionState.waiting
                ? null
                : sommeVersementsDuJourDepuisStats(
                    statsSnap.data,
                    allowedDoctorIds: allowedDoctorIds,
                  );

            if (depuisStats != null) {
              return _KpiTiles(
                patientsToday: patientsToday,
                waiting: salleSnap.hasData ? waiting : null,
                inConsultation: salleSnap.hasData ? inConsultation : null,
                recette: depuisStats.total,
              );
            }

            // L'agregat n'a pas le detail par medecin (backend qui ne le
            // renseigne pas encore) : seul ce cas retombe sur le parcours de
            // tous les patients.
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: FirestoreService().patientsStream(
                parentUid: parentUid,
                profileId: profileId,
              ),
              builder: (context, patientsSnap) {
                final patients =
                    patientsSnap.data ?? const <Map<String, dynamic>>[];
                final recette = patientsSnap.hasData
                    ? sommeVersementsDuJour(
                        patients,
                        allowedDoctorIds: allowedDoctorIds,
                      ).total
                    : null;

                return _KpiTiles(
                  patientsToday: patientsToday,
                  waiting: salleSnap.hasData ? waiting : null,
                  inConsultation: salleSnap.hasData ? inConsultation : null,
                  recette: recette,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _KpiTiles extends StatelessWidget {
  final int? patientsToday;
  final int? waiting;
  final int? inConsultation;
  final double? recette;

  const _KpiTiles({
    required this.patientsToday,
    required this.waiting,
    required this.inConsultation,
    required this.recette,
  });

  @override
  Widget build(BuildContext context) {
    final r = recette;
    final tiles = [
      _KpiTile(
        icon: Icons.people_alt_outlined,
        color: AppTheme.violet(context),
        label: 'Patients du jour',
        value: patientsToday?.toString() ?? '…',
      ),
      _KpiTile(
        icon: Icons.meeting_room_outlined,
        color: AppTheme.ambre(context),
        label: 'En attente',
        value: waiting == null ? '…' : '$waiting',
      ),
      _KpiTile(
        icon: Icons.monitor_heart,
        color: AppTheme.menthe(context),
        label: 'En consultation',
        value: inConsultation == null ? '…' : '$inConsultation',
      ),
      _KpiTile(
        icon: Icons.payments_outlined,
        color: const Color(0xFF16A34A),
        label: 'Recettes du jour',
        value: r == null ? '…' : 'DA ${_formatMoney(r)}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 12),
              Expanded(child: tiles[1]),
              const SizedBox(width: 12),
              Expanded(child: tiles[2]),
              const SizedBox(width: 12),
              Expanded(child: tiles[3]),
            ],
          );
        }
        if (constraints.maxWidth >= 500) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[3]),
                ],
              ),
            ],
          );
        }
        return Column(
          children: [
            tiles[0],
            const SizedBox(height: 12),
            tiles[1],
            const SizedBox(height: 12),
            tiles[2],
            const SizedBox(height: 12),
            tiles[3],
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textMuted = textPrimary.withOpacity(0.7);
    return FluentCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(double value) {
  final isInt = value.truncateToDouble() == value;
  return value.toStringAsFixed(isInt ? 0 : 2);
}

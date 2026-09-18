import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/stats_service.dart';
import '../ui/fluent_card.dart';
import '../core/coerce.dart';

class DailyVersementsCard extends StatelessWidget {
  final String parentUid;
  final String profileId;
  final Set<String>? allowedDoctorIds;

  const DailyVersementsCard({
    super.key,
    required this.parentUid,
    required this.profileId,
    this.allowedDoctorIds,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final todayKey = StatsService.dayKeyOf(DateTime.now());

    return StreamBuilder<Map<String, dynamic>?>(
      stream: StatsService().dailyStatsDoc(
        parentUid: parentUid,
        dayKey: todayKey,
      ),
      builder: (context, statsSnap) {
        if (statsSnap.connectionState == ConnectionState.waiting) {
          return FluentCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: const [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Calcul des versements...'),
              ],
            ),
          );
        }

        final depuisStats = sommeVersementsDuJourDepuisStats(
          statsSnap.data,
          allowedDoctorIds: allowedDoctorIds,
        );

        // `depuisStats` est `null` quand l'agregat n'a pas de detail par
        // medecin (backend qui ne le renseigne pas encore) : seul ce cas
        // retombe sur l'ancien calcul, qui lit tous les patients.
        if (depuisStats != null) {
          return _Carte(
            total: depuisStats.total,
            count: depuisStats.count,
            textPrimary: textPrimary,
            textMuted: textMuted,
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: FirestoreService().patientsStream(
            parentUid: parentUid,
            profileId: profileId,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return FluentCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Versements indisponibles',
                        style: TextStyle(color: textMuted),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData) {
              return FluentCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Calcul des versements...'),
                  ],
                ),
              );
            }

            final (total: total, count: count) = sommeVersementsDuJour(
              snapshot.data!,
              allowedDoctorIds: allowedDoctorIds,
            );

            return _Carte(
              total: total,
              count: count,
              textPrimary: textPrimary,
              textMuted: textMuted,
            );
          },
        );
      },
    );
  }
}

class _Carte extends StatelessWidget {
  final double total;
  final int count;
  final Color textPrimary;
  final Color textMuted;

  const _Carte({
    required this.total,
    required this.count,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    final amountText = 'DA ${_formatMoney(total)}';
    final subtitle = count == 1
        ? '1 versement aujourd\'hui'
        : '$count versements aujourd\'hui';

    return FluentCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF16A34A).withOpacity(0.12),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Versements du jour',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: textMuted)),
              ],
            ),
          ),
          Text(
            amountText,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Total et nombre des versements enregistres aujourd'hui.
///
/// Partagee entre [DailyVersementsCard] et `KpiRow` : les deux doivent
/// afficher le meme chiffre pour le meme cabinet, donc le meme calcul.
({double total, int count}) sommeVersementsDuJour(
  List<Map<String, dynamic>> patients, {
  Set<String>? allowedDoctorIds,
}) {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  double total = 0;
  int count = 0;

  for (final data in patients) {
    if (_shouldSkipPatient(data, allowedDoctorIds)) continue;
    final versements = data['versements'];
    if (versements is! List) continue;

    for (final v in versements) {
      if (v is! Map) continue;
      final createdAt = _asDate(v['createdAt']);
      if (!_isToday(createdAt, startOfDay, endOfDay)) continue;
      final montant = _asDouble(v['montant']);
      if (montant == null) continue;
      total += montant;
      count += 1;
    }
  }

  return (total: total, count: count);
}

/// Le meme total, lu depuis l'agregat `daily_stats/{jour}` plutot que
/// recalcule en parcourant tous les patients.
///
/// `null` quand l'agregat ne permet pas de repondre pour la portee demandee
/// — un `doctorVersements` absent, par exemple, si un backend ne le
/// renseigne pas encore. L'appelant doit alors se rabattre sur
/// [sommeVersementsDuJour] plutot que d'afficher un chiffre faux.
({double total, int count})? sommeVersementsDuJourDepuisStats(
  Map<String, dynamic>? statsDoc, {
  Set<String>? allowedDoctorIds,
}) {
  if (statsDoc == null) return (total: 0, count: 0);

  if (allowedDoctorIds == null || allowedDoctorIds.isEmpty) {
    return (
      total: asDoubleOrNull(statsDoc['versementsTotal']) ?? 0,
      count: (statsDoc['versementsCount'] as num?)?.toInt() ?? 0,
    );
  }

  final parDocteur = statsDoc['doctorVersements'];
  if (parDocteur is! Map) return null;

  double total = 0;
  int count = 0;
  for (final id in allowedDoctorIds) {
    final entree = parDocteur[id];
    if (entree is! Map) continue;
    total += asDoubleOrNull(entree['total']) ?? 0;
    count += (entree['count'] as num?)?.toInt() ?? 0;
  }
  return (total: total, count: count);
}

double? _asDouble(dynamic value) => asDoubleOrNull(value);

bool _shouldSkipPatient(
  Map<String, dynamic> patientData, [
  Set<String>? allowedDoctorIds,
]) {
  if (allowedDoctorIds == null || allowedDoctorIds.isEmpty) return false;
  final doctorId = (patientData['doctorId'] ?? '').toString();
  if (doctorId.isEmpty) return true;
  return !allowedDoctorIds.contains(doctorId);
}

bool _isToday(DateTime date, DateTime start, DateTime end) {
  return date.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
      date.isBefore(end);
}

DateTime _asDate(dynamic value) =>
    asDateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

String _formatMoney(double value) {
  final isInt = value.truncateToDouble() == value;
  return value.toStringAsFixed(isInt ? 0 : 2);
}

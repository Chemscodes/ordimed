import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
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

        final now = DateTime.now();
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));

        double total = 0;
        int count = 0;

        for (final data in snapshot.data!) {
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

        final amountText = 'DA ${_formatMoney(total)}';
        final subtitle =
            count == 1 ? '1 versement aujourd\'hui' : '$count versements aujourd\'hui';

        return FluentCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF16A34A).withOpacity(0.12),
                child: const Icon(Icons.payments_outlined, color: Color(0xFF16A34A)),
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
                    Text(
                      subtitle,
                      style: TextStyle(color: textMuted),
                    ),
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
      },
    );
  }
}

double? _asDouble(dynamic value) => asDoubleOrNull(value);

bool _shouldSkipPatient(Map<String, dynamic> patientData, [Set<String>? allowedDoctorIds]) {
  if (allowedDoctorIds == null || allowedDoctorIds.isEmpty) return false;
  final doctorId = (patientData['doctorId'] ?? '').toString();
  if (doctorId.isEmpty) return true;
  return !allowedDoctorIds.contains(doctorId);
}

bool _isToday(DateTime date, DateTime start, DateTime end) {
  return date.isAfter(start.subtract(const Duration(milliseconds: 1))) && date.isBefore(end);
}

DateTime _asDate(dynamic value) =>
    asDateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

String _formatMoney(double value) {
  final isInt = value.truncateToDouble() == value;
  return value.toStringAsFixed(isInt ? 0 : 2);
}

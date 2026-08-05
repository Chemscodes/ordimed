import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../ui/fluent_card.dart';
import '../ui/empty_state.dart';
import '../ui/error_state.dart';

class AppointmentsPage extends StatefulWidget {
  final String parentUid;
  final String profileId;
  AppointmentsPage({super.key, required this.parentUid, required this.profileId});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const int _pageSize = 60;
  int _limit = _pageSize;
  bool _showAll = false;
  final FirestoreService _service = FirestoreService();

  DateTime _recentCutoff() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 60));
  }

  @override
  Widget build(BuildContext context) {
    final fromDate = _showAll ? null : _recentCutoff();
    return StreamBuilder(
      stream: _service.rendezVousStream(
        parentUid: widget.parentUid,
        profileId: widget.profileId,
        limit: _limit,
        fromDate: fromDate,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return const ErrorState(message: 'Erreur de chargement des rendez-vous');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        final canLoadMore = docs.length >= _limit;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Text(
                    _showAll ? 'Tous les rendez-vous' : 'Rendez-vous (60 jours)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _showAll = !_showAll;
                      _limit = _pageSize;
                    }),
                    child: Text(_showAll ? 'Voir recents' : 'Voir tout'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const EmptyState(title: 'Aucun rendez-vous')
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length + (canLoadMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (canLoadMore && i >= docs.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _limit += _pageSize),
                                child: const Text('Charger plus'),
                              ),
                            ),
                          );
                        }
                        final d = docs[i].data() as Map<String, dynamic>;
                        final patient = d['patientNom'] ?? 'Patient';
                        final medecin = d['doctorId'] ?? '';
                        final motif = d['motif'] ?? '';
                        final dt =
                            d['datetime'] is Timestamp ? (d['datetime'] as Timestamp).toDate() : null;
                        final formatted = dt != null
                            ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                            : 'Date Çÿ dÇ¸finir';

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 220 + (i * 30)),
                          tween: Tween(begin: 20, end: 0),
                          builder: (context, offset, child) {
                            return Opacity(
                              opacity: 1 - (offset / 20).clamp(0, 1),
                              child: Transform.translate(
                                offset: Offset(0, offset),
                                child: child,
                              ),
                            );
                          },
                          child: FluentCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            child: ListTile(
                              leading: const Icon(Icons.event_available, color: Color(0xFF2563EB)),
                              title: Text(patient),
                              subtitle: Text('MÇ¸decin: $medecin\n$formatted'),
                              trailing: Text(motif),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

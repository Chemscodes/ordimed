import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'patient_details_page.dart';
import '../services/soft_delete.dart';

class PatientsPage extends StatefulWidget {
  final String parentUid;
  final String profileId;
  final bool canAddDoctorForm;

  PatientsPage({
    required this.parentUid,
    required this.profileId,
    this.canAddDoctorForm = false,
  });

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final ScrollController _listCtrl = ScrollController();
  static const int _pageSize = 60;
  int _limit = _pageSize;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = scheme.onSurface;
    final textMuted = scheme.onSurface.withOpacity(0.7);
    final textFaint = scheme.onSurface.withOpacity(0.5);
    final searchGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [scheme.surface, scheme.surfaceVariant]
          : [Colors.white.withOpacity(0.92), const Color(0xFFF1F5F9).withOpacity(0.9)],
    );
    // La limite s'applique a l'affichage et non a la requete : le tri par
    // createdAt cote serveur exclurait les dossiers qui n'ont pas ce champ,
    // et ce sont les plus anciens.
    final stream = ApiService.instance.patientsFlux(
      profileId: widget.profileId,
    );

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                gradient: searchGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(isDark ? 0.12 : 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: scheme.primary.withOpacity(0.85), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un patient',
                        hintStyle: TextStyle(color: textFaint),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? scheme.secondary.withOpacity(0.18) : const Color(0xFFE8EEF8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(isDark ? 0.12 : 0.65)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 16, color: scheme.primary),
                        SizedBox(width: 6),
                        Text('Filtres', style: TextStyle(color: scheme.primary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tous = snap.data!;
                final docs = tous.length > _limit
                    ? tous.sublist(0, _limit)
                    : tous;
                final canLoadMore = docs.length >= _limit;
                if (docs.isEmpty) return const Center(child: Text('Aucun patient'));

                final filtered = docs.where((data) {
                  if (isDeleted(data)) return false;
                  final nom = (data['nom'] ?? '').toString();
                  final prenom = (data['prenom'] ?? '').toString();
                  final full = '$nom $prenom'.toLowerCase();
                  if (_query.isEmpty) return true;
                  return full.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  if (canLoadMore && _query.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Aucun patient trouve dans cette page'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => setState(() => _limit += _pageSize),
                            child: const Text('Charger plus'),
                          ),
                        ],
                      ),
                    );
                  }
                  return const Center(child: Text('Aucun patient trouve'));
                }

                return Scrollbar(
                  controller: _listCtrl,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _listCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length + (canLoadMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (canLoadMore && i >= filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _limit += _pageSize),
                              child: const Text('Charger plus'),
                            ),
                          ),
                        );
                      }
                      final d = filtered[i];
                      final nom = d['nom'] ?? 'Patient';
                      final prenom = d['prenom'] ?? '';
                      final motif = d['motif'] ?? '';
                      final tel = d['tel'] ?? '';
                      final medecin = d['assignedMedecinName'] ?? d['doctorName'] ?? d['doctorId'] ?? '';
                      final assistant = d['assistantName'] ?? d['assistantId'] ?? '';
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
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.22)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PatientDetailsPage(
                                      patientId: filtered[i]['id'].toString(),
                                      patientName: nom,
                                      parentUid: widget.parentUid,
                                      ownerProfileId: widget.profileId,
                                      canAddForm: true,
                                      canAddDoctorForm: widget.canAddDoctorForm,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary.withOpacity(0.16),
                                      child: Icon(Icons.person_outline,
                                          color: Theme.of(context).colorScheme.primary),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$nom $prenom',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 17,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (motif.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: scheme.secondary.withOpacity(0.18),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    motif,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              if (tel.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  tel,
                                                  style: TextStyle(
                                                    color: textFaint,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (medecin.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              'Medecin : $medecin',
                                              style: TextStyle(
                                                color: textMuted,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          if (assistant.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Assistant : $assistant',
                                              style: TextStyle(
                                                color: textFaint,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, color: textFaint),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

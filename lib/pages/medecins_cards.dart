import 'package:flutter/material.dart';

import '../services/api_service.dart';

class MedecinsCards extends StatelessWidget {
  final String parentUid;
  final void Function(String docId, Map<String, dynamic> data) onTap;

  const MedecinsCards({required this.parentUid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Le filtrage par role se fait ici : la liste des profils d'un cabinet
    // tient en quelques elements, une route dediee serait du zele.
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ApiService.instance.profilsFlux(),
      builder: (context, snap) {
        if (!snap.hasData) return Center(child: CircularProgressIndicator());
        final docs = snap.data!
            .where((p) =>
                p['role'] == 'medecin' || p['role'] == 'medecin_principal')
            .toList();
        if (docs.isEmpty) return Center(child: Text('Aucun médecin.'));
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: docs.map((data) {
            return GestureDetector(
              onTap: () => onTap((data['id'] ?? '').toString(), data),
              child: Card(
                elevation: 3,
                child: Container(
                  width: 220,
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.medical_services, size: 36, color: Colors.blueGrey),
                      SizedBox(height: 8),
                      Text(data['name'] ?? 'Médecin', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text(data['role'] ?? ''),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

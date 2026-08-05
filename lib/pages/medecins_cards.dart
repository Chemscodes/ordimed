import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MedecinsCards extends StatelessWidget {
  final String parentUid;
  final void Function(String docId, Map<String, dynamic> data) onTap;

  const MedecinsCards({required this.parentUid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Inclure les rôles médecin et médecin principal
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(parentUid)
        .collection('comptes')
        .where('role', whereIn: ['medecin', 'medecin_principal'])
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Center(child: Text('Aucun médecin.'));
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return GestureDetector(
              onTap: () => onTap(d.id, data),
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

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dashboard_principale.dart';
import 'dashboard_medecin.dart';
import 'dashboard_assistant.dart';
import 'add_profile_page.dart';
import 'widget/card.dart';
import '../ui/app_shell.dart';
import '../ui/fluent_button.dart';

class ProfileSelectorPage extends StatelessWidget {
  final String uid;
  const ProfileSelectorPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final comptesRef =
        FirebaseFirestore.instance.collection('users').doc(uid).collection('comptes');

    return AppShell(
      title: 'Choisir un profil',
      currentIndex: 0,
      onNav: (i) {},
      topActions: [
        FluentButton(
          label: 'Ajouter profil',
          icon: Icons.person_add_alt_1,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddProfilePage(uid: uid),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          tooltip: 'Déconnexion',
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            }
          },
        ),
      ],
      child: StreamBuilder<QuerySnapshot>(
        stream: comptesRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun profil'));
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.15,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;

                  return ProfileCard(
                    name: data['name'],
                    role: data['role'],
                    onTap: () => _askPin(
                      context: context,
                      profileDoc: doc,
                      parentUid: uid,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _askPin({
    required BuildContext context,
    required QueryDocumentSnapshot profileDoc,
    required String parentUid,
  }) {
    final pinCtrl = TextEditingController();
    final data = profileDoc.data() as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('PIN pour ${data['name']}'),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Code PIN'),
        ),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text('Entrer'),
            onPressed: () {
              if (pinCtrl.text.trim() != data['pin']) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN incorrect')),
                );
                return;
              }

              Navigator.pop(context);

              final role = data['role'];
              final profileId = profileDoc.id;

              if (role == 'medecin_principal') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardPrincipal(
                      parentUid: parentUid,
                      profileId: profileId,
                      profileData: data,
                    ),
                  ),
                );
              } else if (role == 'medecin') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardMedecin(
                      parentUid: parentUid,
                      profileId: profileId,
                      profileData: data,
                    ),
                  ),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardAssistant(
                      parentUid: parentUid,
                      profileId: profileId,
                      profileData: data,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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
            await AuthService().signOut();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            }
          },
        ),
      ],
      child: StreamBuilder<List<Map<String, dynamic>>>(
        // Meme forme qu'avant : le flux se recharge quand un profil est
        // ajoute ou modifie, ici ou depuis un autre poste.
        stream: ApiService.instance.profilsFlux(),
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  e is ApiException ? e.message : 'Chargement impossible',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!;
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
                  final data = docs[i];

                  return ProfileCard(
                    name: data['name'],
                    role: data['role'],
                    onTap: () => _askPin(
                      context: context,
                      profil: data,
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
    required Map<String, dynamic> profil,
    required String parentUid,
  }) {
    final pinCtrl = TextEditingController();
    final data = profil;
    var verification = false;

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
          StatefulBuilder(
            builder: (context, setLocal) => ElevatedButton(
            // Le PIN etait compare ici meme, sur une valeur stockee en
            // clair : quiconque lisait la base voyait tous les PIN, et un
            // client modifie pouvait sauter la comparaison. Il ne quitte
            // plus jamais le serveur.
            onPressed: verification
                ? null
                : () async {
              setLocal(() => verification = true);
              final profileId = data['id'].toString();
              try {
                await ApiService.instance.verifierPin(
                  profileId,
                  pinCtrl.text.trim(),
                );
              } on ApiException catch (e) {
                if (!context.mounted) return;
                setLocal(() => verification = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
                return;
              }

              if (!context.mounted) return;
              Navigator.pop(context);

              final role = data['role'];

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
            child: verification
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Entrer'),
            ),
          ),
        ],
      ),
    );
  }
}

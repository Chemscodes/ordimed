import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_service.dart';
import '../ui/app_theme.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_button.dart';

class AddProfilePage extends StatefulWidget {
  final String uid;
  const AddProfilePage({super.key, required this.uid});

  @override
  State<AddProfilePage> createState() => _AddProfilePageState();
}

class _AddProfilePageState extends State<AddProfilePage> {
  final nameCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String role = 'assistant';
  bool _isSubmitting = false;

  Future<void> createProfile() async {
    if (_isSubmitting) return;
    if (nameCtrl.text.trim().isEmpty || pinCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom et PIN requis')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      // Le PIN est hache par le backend. Il n'est plus jamais stocke en
      // clair ni compare cote client.
      await ApiService.instance.creerProfil(
        name: nameCtrl.text.trim(),
        role: role,
        pin: pinCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : 'Erreur lors de la creation du profil',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      appBar: AppBar(
        title: const Text('Créer un profil'),
      ),
      body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FluentCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nom du profil'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'assistant', child: Text('Assistant')),
                      DropdownMenuItem(value: 'medecin', child: Text('Médecin')),
                      DropdownMenuItem(
                          value: 'medecin_principal', child: Text('Médecin principal')),
                    ],
                    onChanged: (v) => setState(() => role = v ?? 'assistant'),
                    decoration: const InputDecoration(labelText: 'Rôle'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinCtrl,
                    decoration: const InputDecoration(labelText: 'PIN'),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FluentButton(
                      label: 'Créer',
                      onPressed: _isSubmitting ? null : createProfile,
                      isLoading: _isSubmitting,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

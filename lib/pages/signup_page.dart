import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'profile_selector_page.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_text_field.dart';
import '../ui/fluent_button.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;

  Future<void> signup() async {
    if (_isSubmitting) return;
    try {
      if (email.text.trim().isEmpty || password.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email et mot de passe requis')),
        );
        return;
      }
      setState(() => _isSubmitting = true);
      // Le cabinet et son medecin principal sont crees ensemble par le
      // backend : ils partaient deja ensemble ici, et un cabinet sans
      // profil est inutilisable — on ne peut meme pas s'y connecter.
      final cabinetId = await AuthService().signUp(
        email.text.trim(),
        password.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ProfileSelectorPage(uid: cabinetId)),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Inscription impossible'),
          content: Text(
            e is ApiException ? e.message : 'Une erreur est survenue',
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withOpacity(0.08),
              scheme.secondary.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FluentCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 46,
                        width: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.secondary],
                          ),
                        ),
                        child: const Icon(Icons.medical_services, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Ordimed',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text('Créer un compte'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Inscription',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  FluentTextField(
                    controller: email,
                    label: 'Email professionnel',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : signup,
                      child: _isSubmitting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Inscription...'),
                              ],
                            )
                          : const Text("S'inscrire"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Retour à la connexion'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

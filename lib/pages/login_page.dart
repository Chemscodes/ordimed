import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/backend_config.dart';
import 'choix_base.dart';
import 'signup_page.dart';
import 'profile_selector_page.dart';
import '../ui/fluent_card.dart';
import '../ui/fluent_text_field.dart';
import '../ui/fluent_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;

  Future<void> login() async {
    if (_isSubmitting) return;
    try {
      if (email.text.trim().isEmpty || password.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email et mot de passe requis')),
        );
        return;
      }
      setState(() => _isSubmitting = true);
      final cabinetId = await AuthService().signIn(
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
          title: const Text('Connexion impossible'),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: FluentCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF2FE0BE),
                            const Color(0xFF1ABFA2),
                          ],
                        ),
                      ),
                      child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ordimed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Espace sécurisé',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.50),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Connexion',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                FluentTextField(
                  controller: email,
                  label: 'Email professionnel',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                FluentTextField(
                  controller: password,
                  label: 'Mot de passe',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      _obscure ? 'Afficher' : 'Masquer',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FluentButton(
                    label: _isSubmitting ? 'Connexion…' : 'Se connecter',
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : login,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignupPage()),
                    ),
                    child: const Text('Créer un compte'),
                  ),
                ),
                // C'est ici qu'on decouvre que la base ne repond pas : le
                // reglage doit etre a portee, pas enfoui dans un menu
                // accessible seulement une fois connecte.
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      final change = await ChoixBase.ouvrir(context);
                      if (change && mounted) setState(() {});
                    },
                    icon: Icon(
                      BackendConfig.surFirebase
                          ? Icons.cloud_outlined
                          : Icons.dns_outlined,
                      size: 14,
                    ),
                    label: Text(
                      BackendConfig.surFirebase
                          ? 'Base : Firebase'
                          : 'Serveur : ${ApiClient.instance.baseUrl}',
                      style: const TextStyle(fontSize: 11),
                    ),
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

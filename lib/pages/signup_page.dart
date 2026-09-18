import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'profile_selector_page.dart';
import '../ui/app_theme.dart';
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
      backgroundColor: AppTheme.pageBg(context),
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
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2FE0BE), Color(0xFF1ABFA2)],
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
                        ),
                        Text(
                          'Créer un compte',
                          style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.50)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Inscription',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FluentButton(
                    label: _isSubmitting ? 'Inscription…' : "S'inscrire",
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : signup,
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
    );
  }
}

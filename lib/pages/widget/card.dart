import 'package:flutter/material.dart';
import '../../ui/app_theme.dart';

/// Carte de profil de l'écran d'accueil.
///
/// Chaque rôle a sa couleur : menthe pour le médecin, orange pour
/// l'assistant, indigo pour le directeur. La carte se soulève au survol.
class ProfileCard extends StatefulWidget {
  final String name;
  final String role;
  final VoidCallback onTap;

  const ProfileCard({
    super.key,
    required this.name,
    required this.role,
    required this.onTap,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _hover = false;

  IconData get _icon {
    switch (widget.role) {
      case 'medecin_principal':
        return Icons.workspace_premium_rounded;
      case 'medecin':
        return Icons.medical_services_rounded;
      case 'assistant':
        return Icons.support_agent_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  String get _label {
    switch (widget.role) {
      case 'medecin_principal':
        return 'Médecin principal';
      case 'medecin':
        return 'Médecin';
      case 'assistant':
        return 'Assistant';
      default:
        return widget.role;
    }
  }

  Color _accent(ColorScheme s) {
    switch (widget.role) {
      case 'medecin_principal':
        return s.tertiary;
      case 'medecin':
        return s.primary;
      case 'assistant':
        return s.secondary;
      default:
        return s.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(scheme);

    // Les teintes sont fusionnées avec la surface plutôt que posées en
    // semi-transparence : sans ça, le fond sombre de l'AppShell transparaît
    // et délave la carte en beige.
    final tinted = Color.alphaBlend(
      accent.withValues(alpha: 0.10),
      scheme.surface,
    );
    final chipBg = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      scheme.surface,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.mid,
          curve: AppTheme.ease,
          transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rCard),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tinted, scheme.surface],
            ),
            border: Border.all(
              color: _hover
                  ? accent.withValues(alpha: 0.75)
                  : accent.withValues(alpha: 0.25),
              width: _hover ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: _hover ? 0.35 : 0.14),
                blurRadius: _hover ? 30 : 16,
                offset: Offset(0, _hover ? 14 : 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pastille de rôle : dégradé plein et halo coloré.
              AnimatedContainer(
                duration: AppTheme.mid,
                curve: AppTheme.ease,
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      Color.lerp(accent, Colors.black, 0.22)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: _hover ? 0.55 : 0.32),
                      blurRadius: _hover ? 20 : 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(_icon, size: 27, color: Colors.white),
              ),
              const Spacer(),
              Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              // Étiquette de rôle en pastille, pas en texte gris fade.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color.lerp(accent, scheme.onSurface, 0.30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

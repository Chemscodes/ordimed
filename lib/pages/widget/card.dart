import 'package:flutter/material.dart';

class ProfileCard extends StatelessWidget {
  final String name;
  final String role;
  final VoidCallback onTap;

  const ProfileCard({
    Key? key,
    required this.name,
    required this.role,
    required this.onTap,
  }) : super(key: key);

  IconData get _icon {
    switch (role) {
      case 'medecin_principal':
        return Icons.verified;
      case 'medecin':
        return Icons.local_hospital;
      case 'assistant':
        return Icons.support_agent;
      default:
        return Icons.person;
    }
  }

  Color _accent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (role) {
      case 'medecin_principal':
        return scheme.tertiary;
      case 'medecin':
        return scheme.primary;
      case 'assistant':
        return scheme.secondary;
      default:
        return scheme.primary;
    }
  }

  String get _label {
    switch (role) {
      case 'medecin_principal':
        return 'Médecin principal';
      case 'medecin':
        return 'Médecin';
      case 'assistant':
        return 'Assistant';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              accent.withOpacity(0.12),
              Theme.of(context).cardTheme.color ?? Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: accent.withOpacity(0.15)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(14),
              child: Icon(
                _icon,
                size: 32,
                color: accent,
              ),
            ),
            const Spacer(),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

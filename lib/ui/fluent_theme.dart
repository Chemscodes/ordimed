import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Ancien point d'entrée du style, conservé comme façade.
///
/// Le style vit désormais dans [AppTheme]. Cette classe redirige pour que le
/// code existant continue de fonctionner tout en adoptant le nouveau rendu.
/// À terme, remplacer les appels `FluentTheme.x` par `AppTheme.x`.
class FluentTheme {
  static const double cardRadius = AppTheme.rCard;
  static const double buttonRadius = AppTheme.rButton;
  static const double appBarRadius = AppTheme.rCard;
  static const Duration fastAnim = AppTheme.fast;
  static const Duration midAnim = AppTheme.mid;

  /// Conserve l'ancienne signature (une seule ombre) en piochant la couche
  /// principale de la nouvelle ombre à deux niveaux.
  static BoxShadow softShadow(BuildContext context) =>
      AppTheme.shadow(context).first;

  static LinearGradient appBarGradient(BuildContext context) =>
      AppTheme.brandGradient(context);

  static LinearGradient micaBackground(BuildContext context) =>
      AppTheme.pageGradient(context);
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Thème de l'application.
///
/// Tout l'aspect visuel d'Ordimed passe par ici : changer une couleur ou une
/// graisse dans ce fichier se répercute sur les quatorze écrans.
///
/// `ultraLite` (drapeau `--lite`) désactive les polices distantes et les
/// transitions, pour les postes anciens.
class AppTheme {
  // ---- Rythme d'animation ----
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration mid = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;

  // ---- Formes ----
  static const double rCard = 20;
  static const double rButton = 14;
  static const double rField = 14;
  static const double rPill = 999;

  // ---- Palette claire ----
  static const _lPrimary = Color(0xFF00B39F); // menthe clinique, vive
  static const _lAccent = Color(0xFFFF8A3D); // orange chaud
  static const _lTertiary = Color(0xFF6366F1); // indigo, usages secondaires
  static const _lBg = Color(0xFFF3F8F7);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lRaised = Color(0xFFF7FBFA);
  static const _lInk = Color(0xFF0A1F26);
  static const _lOutline = Color(0xFFD3E4E1);

  // ---- Palette sombre ----
  static const _dPrimary = Color(0xFF2DE0C8); // menthe lumineuse
  static const _dAccent = Color(0xFFFFA24D);
  static const _dTertiary = Color(0xFF8B8DF7);
  static const _dBg = Color(0xFF06141A);
  static const _dSurface = Color(0xFF0B1F26);
  static const _dRaised = Color(0xFF122B33);
  static const _dInk = Color(0xFFE4F4F1);
  static const _dOutline = Color(0xFF1E3B43);

  /// Ombre en deux couches : un halo large et diffus, plus un contact net.
  /// Bien plus proche d'une vraie ombre qu'un seul flou.
  static List<BoxShadow> shadow(BuildContext context, {double strength = 1}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: (dark ? 0.42 : 0.07) * strength),
        blurRadius: 28 * strength,
        offset: Offset(0, 12 * strength),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: (dark ? 0.26 : 0.04) * strength),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Largeur d'un dialogue : la valeur souhaitée, mais jamais plus que la
  /// fenêtre. Une largeur figée est la première cause de débordement
  /// horizontal quand l'utilisateur réduit l'application.
  static double dialogWidth(BuildContext context, double desired) {
    final available = MediaQuery.of(context).size.width - 96;
    if (desired <= available) return desired;
    return available > 280 ? available : 280;
  }

  /// Hauteur maximale d'un contenu de dialogue : au-delà, il doit défiler
  /// plutôt que dépasser de l'écran.
  static double dialogMaxHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.70;

  static LinearGradient brandGradient(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [s.primary, Color.lerp(s.primary, s.secondary, 0.55)!],
    );
  }

  /// Fond de page : dégradé très doux, jamais plat.
  static LinearGradient pageGradient(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        s.primary.withValues(alpha: dark ? 0.10 : 0.06),
        s.surface,
        s.secondary.withValues(alpha: dark ? 0.07 : 0.04),
      ],
    );
  }

  static TextTheme _text(TextTheme base, bool ultraLite, Color ink) {
    // Plus Jakarta Sans : géométrique, très lisible en petite taille, et des
    // chiffres nets — ce qui compte pour une app pleine de montants.
    final t = ultraLite ? base : GoogleFonts.plusJakartaSansTextTheme(base);
    return t
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          displayLarge: t.displayLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
          headlineMedium: t.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          titleLarge: t.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          bodyLarge: t.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: t.bodyMedium?.copyWith(height: 1.5),
          labelLarge: t.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        );
  }

  static ThemeData light({bool ultraLite = false}) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _lPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: _lPrimary,
          secondary: _lAccent,
          tertiary: _lTertiary,
          surface: _lSurface,
          surfaceContainerHighest: _lRaised,
          onSurface: _lInk,
          outline: _lOutline,
          outlineVariant: _lOutline.withValues(alpha: 0.6),
        );
    return _common(scheme, _lBg, _lInk, ultraLite);
  }

  static ThemeData dark({bool ultraLite = false}) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _dPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _dPrimary,
          secondary: _dAccent,
          tertiary: _dTertiary,
          surface: _dSurface,
          surfaceContainerHighest: _dRaised,
          onSurface: _dInk,
          onPrimary: const Color(0xFF00332C),
          outline: _dOutline,
          outlineVariant: _dOutline.withValues(alpha: 0.7),
        );
    return _common(scheme, _dBg, _dInk, ultraLite);
  }

  static ThemeData _common(
    ColorScheme scheme,
    Color bg,
    Color ink,
    bool ultraLite,
  ) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final dark = scheme.brightness == Brightness.dark;
    final text = _text(base.textTheme, ultraLite, ink);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: ultraLite
                ? const _NoTransition()
                : const _FadeThroughTransition(),
        },
      ),

      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: Colors.white),
      ),

      cardTheme: base.cardTheme.copyWith(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.55),
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(color: ink.withValues(alpha: 0.85), size: 20),

      listTileTheme: base.listTileTheme.copyWith(
        textColor: ink,
        iconColor: ink.withValues(alpha: 0.75),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rButton),
        ),
      ),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        labelStyle: text.labelLarge?.copyWith(
          color: ink.withValues(alpha: 0.9),
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rPill),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        ),
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 19),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: ink.withValues(alpha: 0.82),
        ),
      ),

      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? _dRaised : const Color(0xFF0A1F26),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rButton),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : scheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        // `isCollapsed: false` + labelStyle compact : évite que le libellé
        // flottant ne pousse le champ et ne déborde dans les dialogues denses.
        labelStyle: text.bodyMedium?.copyWith(
          color: ink.withValues(alpha: 0.65),
        ),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: text.bodyMedium?.copyWith(
          color: ink.withValues(alpha: 0.45),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: dark ? scheme.onPrimary : Colors.white,
          disabledBackgroundColor: scheme.outline.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          elevation: 0,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outline.withValues(alpha: 0.4),
        circularTrackColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? _dRaised : const Color(0xFF0A1F26),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rButton),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

/// Transition « fondu croisé » : la page sortante s'efface pendant que la
/// suivante monte légèrement. Plus moderne qu'un glissement, et sans risque
/// de débordement horizontal pendant l'animation.
class _FadeThroughTransition extends PageTransitionsBuilder {
  const _FadeThroughTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppTheme.ease);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.022),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

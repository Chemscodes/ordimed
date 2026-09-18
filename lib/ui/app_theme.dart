import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Système de design Ordimed — Raycast + Figma aesthetic, sombre par défaut.
///
/// Cinq plans de surface très proches, deux polices (Plex Sans + Plex Mono),
/// quatre accents d'interface, deux teintes de graphique. Tout l'aspect
/// visuel passe ici : changer un token se répercute sur les quatorze écrans.
class AppTheme {
  // ── Rythme d'animation ─────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration mid = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;

  // ── Formes ─────────────────────────────────────────────────────────────
  static const double rCard   = 9;    // sections, cartes
  static const double rButton = 6;    // contrôles, boutons, champs
  static const double rField  = 6;
  static const double rPill   = 999;  // puces

  // ── Surfaces sombres (cinq plans) ──────────────────────────────────────
  static const _dBg      = Color(0xFF0A0C0D); // la page
  static const _dPanel   = Color(0xFF101315); // rail, barres latérales
  static const _dCard    = Color(0xFF15191B); // sections
  static const _dRaised  = Color(0xFF1B2023); // lignes, champs
  static const _dHover   = Color(0xFF262D30); // états survol

  // ── Encres sombres ─────────────────────────────────────────────────────
  static const _dInk1 = Color(0xFFEAEFF1); // texte principal
  static const _dInk2 = Color(0xFF96A1A6); // texte secondaire
  static const _dInk3 = Color(0xFF667276); // labels, meta

  // ── Accents d'interface ────────────────────────────────────────────────
  static const _dMenthe = Color(0xFF2FE0BE); // action, actif
  static const _dAmbre  = Color(0xFFF0A93B); // argent dû, encaissement
  static const _dViolet = Color(0xFF9B8CFA); // ordonnances
  static const _dCorail = Color(0xFFFF6470); // danger, suppression

  // ── Teintes de graphique (validées ΔE 14,0 deutéranopie) ───────────────
  static const chartA = Color(0xFF1FA894);
  static const chartB = Color(0xFFC77F17);

  // ── Surfaces claires (version jour, moins utilisée) ─────────────────────
  static const _lBg      = Color(0xFFF4F6F7);
  static const _lPanel   = Color(0xFFE9ECEE);
  static const _lCard    = Color(0xFFFFFFFF);
  static const _lRaised  = Color(0xFFF0F2F3);
  static const _lOutline = Color(0xFFD5DADD);
  static const _lInk     = Color(0xFF0D1416);
  static const _lPrimary = Color(0xFF1B9C88); // menthe foncée sur blanc
  static const _lAmbre   = Color(0xFFB8760F);

  // ── Helpers d'ombres ───────────────────────────────────────────────────
  static List<BoxShadow> shadow(BuildContext context, {double strength = 1}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: (dark ? 0.50 : 0.07) * strength),
        blurRadius: 24 * strength,
        offset: Offset(0, 10 * strength),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: (dark ? 0.30 : 0.04) * strength),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static double dialogWidth(BuildContext context, double desired) {
    final available = MediaQuery.of(context).size.width - 96;
    if (desired <= available) return desired;
    return available > 280 ? available : 280;
  }

  static double dialogMaxHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.70;

  /// Dégradé de marque — utilisé pour avatars, boutons d'action importants.
  static LinearGradient brandGradient(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? [const Color(0xFF2FE0BE), const Color(0xFF1ABFA2)]
          : [const Color(0xFF1B9C88), const Color(0xFF14796A)],
    );
  }

  /// Fond de page : plat, pas de dégradé — les données doivent dominer.
  static Color pageBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dBg : _lBg;

  /// Compatibilité — anciens widgets qui appelaient un dégradé de fond.
  /// Retourne un dégradé neutre (surface identique des deux côtés).
  static LinearGradient pageGradient(BuildContext context) {
    final bg = pageBg(context);
    return LinearGradient(colors: [bg, bg]);
  }

  static TextTheme _text(TextTheme base, bool ultraLite, Color ink) {
    final sans = ultraLite
        ? base
        : GoogleFonts.ibmPlexSansTextTheme(base);
    return sans
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          // Chiffres : Plex Mono, chiffres tabulaires
          displayLarge: sans.displayLarge?.copyWith(
            fontFamily: ultraLite ? null : 'IBM Plex Mono',
            fontFamilyFallback: ['monospace'],
            fontWeight: FontWeight.w500,
            fontSize: 34,
            letterSpacing: -0.03 * 34,
          ),
          headlineMedium: sans.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 22,
            letterSpacing: -0.025 * 22,
          ),
          titleLarge: sans.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: -0.01 * 14,
          ),
          titleMedium: sans.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            letterSpacing: 0,
          ),
          bodyLarge: sans.bodyLarge?.copyWith(
            fontWeight: FontWeight.w400,
            fontSize: 13,
            height: 1.55,
          ),
          bodyMedium: sans.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
            fontSize: 12,
            height: 1.55,
          ),
          labelLarge: sans.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            letterSpacing: 0.2,
          ),
          labelSmall: sans.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            letterSpacing: 0.09 * 10.5,
          ),
        );
  }

  static ThemeData light({bool ultraLite = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _lPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: _lPrimary,
      onPrimary: Colors.white,
      secondary: _lAmbre,
      tertiary: const Color(0xFF7C6EF0),
      error: const Color(0xFFE0424E),
      surface: _lCard,
      surfaceContainerHighest: _lRaised,
      onSurface: _lInk,
      outline: _lOutline,
      outlineVariant: _lOutline.withValues(alpha: 0.6),
    );
    return _common(scheme, _lBg, _lInk, ultraLite);
  }

  static ThemeData dark({bool ultraLite = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _dMenthe,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _dMenthe,
      onPrimary: const Color(0xFF062B25),
      secondary: _dAmbre,
      onSecondary: const Color(0xFF2A1C05),
      tertiary: _dViolet,
      error: _dCorail,
      surface: _dCard,
      surfaceContainerHighest: _dRaised,
      onSurface: _dInk1,
      outline: const Color(0xFF2A3235),
      outlineVariant: const Color(0xFF1E2528),
    );
    return _common(scheme, _dBg, _dInk1, ultraLite);
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
    final ink2 = dark ? _dInk2 : ink.withValues(alpha: 0.60);
    final panelBg = dark ? _dPanel : _lPanel;
    final raised = dark ? _dRaised : _lRaised;

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text,
      splashFactory: ultraLite ? NoSplash.splashFactory : InkSparkle.splashFactory,

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: ultraLite
                ? const _NoTransition()
                : const _FadeThroughTransition(),
        },
      ),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: panelBg,
        foregroundColor: dark ? _dInk1 : ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(
          color: dark ? _dInk1 : ink,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: dark ? _dInk2 : ink.withValues(alpha: 0.75),
          size: 18,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: BorderSide(color: scheme.outline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(
        color: dark ? _dInk2 : ink.withValues(alpha: 0.75),
        size: 18,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: dark
            ? _dMenthe.withValues(alpha: 0.08)
            : scheme.primary.withValues(alpha: 0.07),
        textColor: ink,
        iconColor: ink2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rButton),
        ),
        minLeadingWidth: 0,
        dense: true,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: raised,
        side: BorderSide(color: scheme.outline),
        labelStyle: text.labelSmall?.copyWith(color: ink2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rPill),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: dark ? _dCard : _lCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: BorderSide(color: scheme.outline),
        ),
        titleTextStyle: text.headlineMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(color: ink2),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? _dRaised : const Color(0xFF0D1416),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rButton),
        ),
        insetPadding: const EdgeInsets.all(16),
        elevation: 0,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: text.bodyMedium?.copyWith(color: ink2),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: dark ? _dInk3 : ink.withValues(alpha: 0.40),
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
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rField),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.outline.withValues(alpha: 0.5),
          disabledForegroundColor: ink2,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          elevation: 0,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? _dInk1 : ink,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
          side: BorderSide(
            color: dark
                ? const Color(0x21FFFFFF)
                : scheme.outline,
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rButton),
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outline.withValues(alpha: 0.5),
        circularTrackColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? _dRaised : const Color(0xFF0D1416),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outline),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white, fontSize: 11.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: dark ? _dCard : _lCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rCard),
          side: BorderSide(color: scheme.outline),
        ),
        textStyle: text.bodyMedium?.copyWith(color: ink),
        labelTextStyle: WidgetStatePropertyAll(text.bodyMedium?.copyWith(color: ink)),
      ),
    );
  }

  // ── Couleurs sémantiques accessibles depuis n'importe quel widget ───────
  static Color ink1(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dInk1 : _lInk;
  }

  static Color ink2(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dInk2
        : _lInk.withValues(alpha: 0.60);
  }

  static Color ink3(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dInk3
        : _lInk.withValues(alpha: 0.40);
  }

  static Color surface(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dCard : _lCard;
  }

  static Color raised(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dRaised : _lRaised;
  }

  static Color panel(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dPanel : _lPanel;
  }

  static Color hover(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dHover
        : _lInk.withValues(alpha: 0.05);
  }

  static Color menthe(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dMenthe
        : _lPrimary;
  }

  static Color ambre(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? _dAmbre : _lAmbre;
  }

  static Color corail(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dCorail
        : const Color(0xFFD03540);
  }

  static Color violet(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? _dViolet
        : const Color(0xFF6B5CF0);
  }

  /// Style monospace pour montants, heures, numéros.
  static TextStyle mono(
    BuildContext context, {
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) {
    final c = color ?? ink1(context);
    return TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: const ['monospace'],
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: size,
      fontWeight: weight,
      color: c,
      height: 1.4,
    );
  }
}

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
          begin: const Offset(0, 0.018),
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

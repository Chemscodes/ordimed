import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'app_router.dart';
import 'pages/login_page.dart';
import 'pages/profile_selector_page.dart';
import 'theme_controller.dart';
import 'services/auth_service.dart';
import 'services/error_reporter.dart';
import 'services/firestore_service.dart';

const bool kUltraLite = bool.fromEnvironment('ULTRA_LITE', defaultValue: false);

/// Reportee dans chaque rapport d'erreur : permet de savoir quelle version
/// tourne chez un cabinet donne. A incrementer a chaque livraison.
const String kAppVersion = '1.0.0+1';

void main(List<String> args) async {
  final bool ultraLite = kUltraLite || args.contains('--lite');
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
  };

  await runZonedGuarded(
    () async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Cache local : le cabinet continue de travailler pendant une coupure
      // internet, et les ecritures sont rejouees au retour du reseau.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Installe apres Firebase : le rapporteur ecrit dans Firestore.
      ErrorReporter().install(appVersion: kAppVersion);

      runApp(MyApp(ultraLite: ultraLite));
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
      unawaited(
        ErrorReporter().report(
          error,
          stack,
          origin: 'zone',
          appVersion: kAppVersion,
        ),
      );
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.ultraLite});

  final bool ultraLite;

  ThemeData _buildLightTheme() {
    const seed = Color(0xFF0F766E);
    const accent = Color(0xFFF59E0B);
    const bg = Color(0xFFF7F4EE);
    const surface = Color(0xFFFCFCFD);
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        background: bg,
        surface: surface,
      ).copyWith(secondary: accent),
      useMaterial3: true,
    );
    final textTheme = ultraLite
        ? base.textTheme
        : GoogleFonts.soraTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: textTheme.apply(
        bodyColor: const Color(0xFF0F172A),
        displayColor: const Color(0xFF0F172A),
      ),
      pageTransitionsTheme: ultraLite
          ? const PageTransitionsTheme(
              builders: {TargetPlatform.windows: _NoTransitionsBuilder()},
            )
          : base.pageTransitionsTheme,
      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.08),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 1.4),
        ),
        filled: true,
        fillColor: surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const seed = Color(0xFF14B8A6);
    const accent = Color(0xFFFBBF24);
    const bg = Color(0xFF0B1324);
    const surface = Color(0xFF101A2C);
    const surfaceVariant = Color(0xFF19263E);
    const onSurface = Color(0xFFE2E8F0);
    const outline = Color(0xFF27354D);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          background: bg,
          surface: surface,
        ).copyWith(
          secondary: accent,
          surfaceVariant: surfaceVariant,
          onSurface: onSurface,
          onBackground: onSurface,
          outline: outline,
        );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final textTheme = ultraLite
        ? base.textTheme
        : GoogleFonts.soraTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: textTheme.apply(bodyColor: onSurface, displayColor: onSurface),
      pageTransitionsTheme: ultraLite
          ? const PageTransitionsTheme(
              builders: {TargetPlatform.windows: _NoTransitionsBuilder()},
            )
          : base.pageTransitionsTheme,
      iconTheme: IconThemeData(color: onSurface.withOpacity(0.9)),
      dividerTheme: DividerThemeData(color: outline.withOpacity(0.7)),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface.withOpacity(0.85),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: onSurface,
        iconColor: onSurface.withOpacity(0.8),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceVariant,
        labelStyle: TextStyle(color: onSurface.withOpacity(0.85)),
        side: BorderSide(color: outline.withOpacity(0.8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: ultraLite
            ? TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: onSurface,
              )
            : GoogleFonts.sora(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: onSurface,
              ),
        contentTextStyle: ultraLite
            ? TextStyle(color: onSurface.withOpacity(0.85))
            : GoogleFonts.sora(color: onSurface.withOpacity(0.85)),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.3),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline.withOpacity(0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: seed.withOpacity(0.8), width: 1.4),
        ),
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: onSurface.withOpacity(0.55)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: AuthService()),
        Provider<FirestoreService>.value(value: FirestoreService()),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, mode, _) {
          return TapGuard(
            cooldown: const Duration(milliseconds: 600),
            child: MaterialApp(
              title: 'Cabinet MÃ©dical',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: _buildLightTheme(),
              darkTheme: _buildDarkTheme(),
              onGenerateRoute: AppRouter.onGenerateRoute,
              home: StreamBuilder<User?>(
                stream: context.read<AuthService>().authChanges(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasData && snap.data != null) {
                    return ProfileSelectorPage(uid: snap.data!.uid);
                  }
                  return const LoginPage();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class TapGuard extends StatefulWidget {
  const TapGuard({
    super.key,
    required this.child,
    this.cooldown = const Duration(milliseconds: 600),
    this.enabled = true,
  });

  final Widget child;
  final Duration cooldown;
  final bool enabled;

  @override
  State<TapGuard> createState() => _TapGuardState();
}

class _TapGuardState extends State<TapGuard> {
  bool _absorbing = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    if (_absorbing) return;
    setState(() => _absorbing = true);
    _timer?.cancel();
    _timer = Timer(widget.cooldown, () {
      if (mounted) {
        setState(() => _absorbing = false);
      }
    });
  }

  bool _isTapFromUser(PointerEvent event) {
    return event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.touch;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (event) {
        if (_isTapFromUser(event)) {
          _startCooldown();
        }
      },
      child: AbsorbPointer(absorbing: _absorbing, child: widget.child),
    );
  }
}

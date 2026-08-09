import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_router.dart';
import 'pages/login_page.dart';
import 'pages/profile_selector_page.dart';
import 'theme_controller.dart';
import 'services/auth_service.dart';
import 'services/error_reporter.dart';
import 'services/firestore_service.dart';
import 'ui/app_theme.dart';

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
      // Rouvre la session enregistree avant de construire l'interface :
      // sans ca, l'ecran de connexion s'afficherait une fraction de seconde
      // avant d'etre remplace.
      //
      // Ce qui disparait avec Firestore : le cache local qui laissait le
      // cabinet travailler pendant une coupure internet. Le backend est
      // joignable ou il ne l'est pas — voir MIGRATION.md.
      await AuthService().restaurer();

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
              title: 'Ordimed — Cabinet médical',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: AppTheme.light(ultraLite: ultraLite),
              darkTheme: AppTheme.dark(ultraLite: ultraLite),
              onGenerateRoute: AppRouter.onGenerateRoute,
              // Garde-fou anti-débordement : un poste réglé à 150 % de taille
              // de texte ferait exploser les tableaux et les cartes denses.
              // On laisse respirer jusqu'à 1.15, pas au-delà.
              builder: (context, child) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: media.textScaler.clamp(
                      minScaleFactor: 0.9,
                      maxScaleFactor: 1.15,
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: StreamBuilder<String?>(
                stream: context.read<AuthService>().sessionChanges(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final cabinetId = snap.data;
                  if (cabinetId != null) {
                    return ProfileSelectorPage(uid: cabinetId);
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

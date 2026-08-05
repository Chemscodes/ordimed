import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/signup_page.dart';
import 'pages/profile_selector_page.dart';
import 'pages/dashboard_assistant.dart';
import 'pages/dashboard_medecin.dart';
import 'pages/dashboard_principale.dart';

class DashboardArgs {
  final String parentUid;
  final String profileId;
  final Map<String, dynamic> profileData;
  DashboardArgs(this.parentUid, this.profileId, this.profileData);
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case '/signup':
        return MaterialPageRoute(builder: (_) => const SignupPage());
      case '/profiles':
        final uid = settings.arguments as String;
        return MaterialPageRoute(builder: (_) => ProfileSelectorPage(uid: uid));
      case '/dashboard_assistant':
        final args = settings.arguments as DashboardArgs;
        return MaterialPageRoute(
          builder: (_) => DashboardAssistant(
            parentUid: args.parentUid,
            profileId: args.profileId,
            profileData: args.profileData,
          ),
        );
      case '/dashboard_medecin':
        final args = settings.arguments as DashboardArgs;
        return MaterialPageRoute(
          builder: (_) => DashboardMedecin(
            parentUid: args.parentUid,
            profileId: args.profileId,
            profileData: args.profileData,
          ),
        );
      case '/dashboard_principal':
        final args = settings.arguments as DashboardArgs;
        return MaterialPageRoute(
          builder: (_) => DashboardPrincipal(
            parentUid: args.parentUid,
            profileId: args.profileId,
            profileData: args.profileData,
          ),
        );
      default:
        return MaterialPageRoute(builder: (_) => const LoginPage());
    }
  }
}

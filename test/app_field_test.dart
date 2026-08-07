import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/ui/app_field.dart';
import 'package:ordimed/ui/app_theme.dart';

/// Enveloppe minimale : un formulaire réel, pour que la validation
/// se comporte comme en production.
Widget _host(Widget child, {GlobalKey<FormState>? formKey}) {
  return MaterialApp(
    theme: AppTheme.light(ultraLite: true),
    home: Scaffold(
      body: Form(
        key: formKey,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

void main() {
  group('AppField — filtres de frappe', () {
    testWidgets("le champ âge refuse les lettres", (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.age(controller: c)));

      await tester.enterText(find.byType(TextFormField), '4a2b');
      expect(c.text, '42', reason: 'seuls les chiffres passent');
    });

    testWidgets("le champ âge est borné à trois chiffres", (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.age(controller: c)));

      await tester.enterText(find.byType(TextFormField), '123456');
      expect(c.text, '123');
    });

    testWidgets('le champ montant accepte la virgule décimale', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.montant(controller: c)));

      await tester.enterText(find.byType(TextFormField), '12,50');
      expect(c.text, '12,50');
    });

    testWidgets("le champ e-mail refuse les espaces", (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.email(controller: c)));

      await tester.enterText(find.byType(TextFormField), 'nom @dom .com');
      expect(c.text, 'nom@dom.com');
    });

    testWidgets('le champ téléphone laisse passer le +213', (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.phone(controller: c)));

      await tester.enterText(find.byType(TextFormField), '+213551686212');
      expect(c.text, '+213551686212', reason: 'normalisé à la validation');
    });
  });

  group('AppField — validation dans un Form', () {
    testWidgets('un champ obligatoire vide bloque la validation',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final c = TextEditingController();
      await tester.pumpWidget(
        _host(AppField.nom(controller: c, label: 'Nom'), formKey: formKey),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('obligatoire'), findsOneWidget);
    });

    testWidgets('un champ correctement rempli passe', (tester) async {
      final formKey = GlobalKey<FormState>();
      final c = TextEditingController(text: 'Belkacem');
      await tester.pumpWidget(
        _host(AppField.nom(controller: c, label: 'Nom'), formKey: formKey),
      );

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('le message de taille rappelle les centimètres',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final c = TextEditingController(text: '1.75');
      await tester.pumpWidget(
        _host(
          AppField.mesure(
            controller: c,
            label: 'Taille',
            unite: 'cm',
            validator: (s) => s == '1.75'
                ? 'La taille est attendue en centimètres (ex. 175)'
                : null,
          ),
          formKey: formKey,
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('centimètres'), findsOneWidget);
    });

    testWidgets("le formulaire ne s'ouvre pas en rouge", (tester) async {
      // autovalidateMode.onUserInteraction : un formulaire vierge ne doit
      // afficher aucune erreur avant que l'utilisateur ait touché quoi que
      // ce soit.
      final c = TextEditingController();
      await tester.pumpWidget(_host(AppField.nom(controller: c, label: 'Nom')));
      await tester.pump();

      expect(find.textContaining('obligatoire'), findsNothing);
    });
  });

  group('AppField — mot de passe', () {
    testWidgets('la bascule de visibilité fonctionne', (tester) async {
      final c = TextEditingController(text: 'secret');
      await tester.pumpWidget(_host(AppField.password(controller: c)));

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('ComputedValue', () {
    testWidgets("affiche ce qui manque tant que la valeur n'est pas calculable",
        (tester) async {
      await tester.pumpWidget(
        _host(
          const ComputedValue(
            label: 'IMC',
            value: null,
            placeholder: 'Renseignez le poids et la taille',
          ),
        ),
      );

      expect(find.text('Renseignez le poids et la taille'), findsOneWidget);
    });

    testWidgets('affiche la valeur et sa note une fois calculée',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const ComputedValue(
            label: 'IMC',
            value: '22.9',
            note: 'Corpulence normale',
          ),
        ),
      );

      expect(find.text('22.9'), findsOneWidget);
      expect(find.text('Corpulence normale'), findsOneWidget);
    });
  });

  group('MontantsSuggeres', () {
    testWidgets('ignore les montants nuls ou négatifs', (tester) async {
      await tester.pumpWidget(
        _host(
          MontantsSuggeres(
            suggestions: const {'Reste': 6500, 'Vide': 0, 'Negatif': -100},
            onChoisi: (_) {},
          ),
        ),
      );

      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.textContaining('Reste'), findsOneWidget);
    });

    testWidgets('renvoie le montant choisi', (tester) async {
      double? choisi;
      await tester.pumpWidget(
        _host(
          MontantsSuggeres(
            suggestions: const {'Reste': 6500},
            onChoisi: (v) => choisi = v,
          ),
        ),
      );

      await tester.tap(find.byType(ActionChip));
      await tester.pump();
      expect(choisi, 6500);
    });
  });
}

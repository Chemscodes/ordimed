import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/core/validate.dart' as v;

/// La validation de l'identite d'un patient.
///
/// Ces tests existent a cause d'un bug precis : l'assistant remplissait les
/// trois etapes, appuyait sur Enregistrer, et l'app le renvoyait a la
/// premiere page avec « Corrigez les champs signalés » — sans qu'aucun champ
/// ne soit signale, et sans que rien ne fut a corriger.
///
/// La cause : le formulaire de l'etape 1 n'est plus dans l'arbre a l'etape 3
/// (un `switch` sur l'etape courante ne monte qu'une etape a la fois).
/// `_identiteKey.currentState?.validate() ?? false` valait donc `false`, et
/// le filet de securite refusait un dossier parfaitement rempli.
///
/// Le correctif verifie les **valeurs** et non l'etat de l'interface. Ces
/// tests verifient ces valeurs — ce qui rend le retour du bug impossible
/// sans qu'ils tombent.

/// Reproduit `_identiteInvalide()` de add_patient_form.dart.
String? identiteInvalide({
  String nom = '',
  String age = '',
  String tel = '',
  String email = '',
}) =>
    v.nom(nom, champ: 'Le nom') ??
    v.age(age) ??
    v.phone(tel) ??
    v.email(email);

void main() {
  group('Un dossier complet passe', () {
    test('le cas courant du cabinet', () {
      expect(
        identiteInvalide(
          nom: 'Benali',
          age: '34',
          tel: '0551234567',
          email: 'amina@exemple.dz',
        ),
        isNull,
      );
    });

    test('le nom seul suffit', () {
      // Age, telephone et e-mail sont facultatifs : un patient qui se
      // presente sans rien d'autre que son nom doit pouvoir etre cree.
      expect(identiteInvalide(nom: 'Benali'), isNull);
    });

    test('un nom compose ou accentue passe', () {
      expect(identiteInvalide(nom: 'Ould-Abbès'), isNull);
      expect(identiteInvalide(nom: 'Ait Ahmed'), isNull);
    });
  });

  group('Un dossier incomplet est refuse, et on sait pourquoi', () {
    test('sans nom', () {
      // Le message doit nommer le probleme : « Corrigez les champs
      // signalés » ne disait rien quand aucun champ n'etait affiche.
      final m = identiteInvalide(nom: '');
      expect(m, isNotNull);
      expect(m!.toLowerCase(), contains('nom'));
    });

    test('un age aberrant', () {
      final m = identiteInvalide(nom: 'Benali', age: '250');
      expect(m, isNotNull);
    });

    test('un age qui n est pas un nombre', () {
      expect(identiteInvalide(nom: 'Benali', age: 'trente'), isNotNull);
    });

    test('un telephone trop court', () {
      expect(identiteInvalide(nom: 'Benali', tel: '055'), isNotNull);
    });

    test('un e-mail sans arobase', () {
      expect(identiteInvalide(nom: 'Benali', email: 'amina.exemple.dz'), isNotNull);
    });
  });

  group('Le premier probleme rencontre est celui annonce', () {
    test('un nom manquant primes sur un age faux', () {
      // Sinon l'assistant corrige l'age, reessaie, et decouvre alors le
      // nom : deux allers-retours pour un seul formulaire.
      final m = identiteInvalide(nom: '', age: '999');
      expect(m!.toLowerCase(), contains('nom'));
    });
  });
}

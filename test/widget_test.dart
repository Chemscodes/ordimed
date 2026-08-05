import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/services/soft_delete.dart';

void main() {
  group('Suppression douce', () {
    test('un patient sans champ deletedAt est visible', () {
      // Cas majoritaire : tous les dossiers crees avant l'introduction de
      // la suppression douce n'ont pas ce champ du tout.
      expect(isDeleted({'nom': 'Amina', 'prenom': 'B.'}), isFalse);
    });

    test('un patient avec deletedAt a null est visible', () {
      expect(isDeleted({'nom': 'Amina', 'deletedAt': null}), isFalse);
    });

    test('un patient avec une date de suppression est masque', () {
      expect(
        isDeleted({'nom': 'Amina', 'deletedAt': DateTime(2026, 8, 5)}),
        isTrue,
      );
    });

    test('une donnee absente ne fait pas planter le filtre', () {
      expect(isDeleted(null), isFalse);
    });
  });
}

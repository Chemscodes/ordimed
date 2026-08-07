import 'package:flutter_test/flutter_test.dart';
import 'package:ordimed/widgets/patient_filters.dart';

Map<String, dynamic> patient({
  String nom = 'Belkacem',
  String prenom = 'Amina',
  String tel = '0551686212',
  String doctorId = 'medA',
  Object? prix,
  Object? verse,
  Object? forfait,
  Object? faites,
  Object? deletedAt,
}) {
  return {
    'nom': nom,
    'prenom': prenom,
    'tel': tel,
    'doctorId': doctorId,
    if (prix != null) 'prix': prix,
    if (verse != null) 'totalVersements': verse,
    if (forfait != null) 'nombreSeances': forfait,
    if (faites != null) 'seancesEffectuees': faites,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };
}

void main() {
  group('Filtres rapides', () {
    test('« reste à payer » ne retient que les dossiers non soldés', () {
      const q = PatientQuery(filtre: PatientFiltre.resteAPayer);
      expect(q.accepte(patient(prix: 10000, verse: 3000)), isTrue);
      expect(q.accepte(patient(prix: 10000, verse: 10000)), isFalse);
      expect(q.accepte(patient(prix: 10000, verse: 15000)), isFalse);
      // Sans prix fixé, on ne peut rien conclure : exclu.
      expect(q.accepte(patient(verse: 3000)), isFalse);
    });

    test('« soldés » est le complément exact', () {
      const q = PatientQuery(filtre: PatientFiltre.soldes);
      expect(q.accepte(patient(prix: 10000, verse: 10000)), isTrue);
      expect(q.accepte(patient(prix: 10000, verse: 12000)), isTrue);
      expect(q.accepte(patient(prix: 10000, verse: 3000)), isFalse);
    });

    test('« séances restantes » exclut les forfaits consommés', () {
      const q = PatientQuery(filtre: PatientFiltre.seancesRestantes);
      expect(q.accepte(patient(forfait: 10, faites: 3)), isTrue);
      expect(q.accepte(patient(forfait: 10, faites: 10)), isFalse);
      expect(q.accepte(patient(forfait: 10, faites: 12)), isFalse);
      expect(q.accepte(patient(faites: 3)), isFalse, reason: 'aucun forfait');
    });

    test('« tous » laisse tout passer', () {
      const q = PatientQuery();
      expect(q.accepte(patient()), isTrue);
    });
  });

  group('Recherche texte', () {
    test('trouve dans les deux ordres nom/prénom', () {
      expect(
        const PatientQuery(texte: 'amina bel').accepte(patient()),
        isTrue,
      );
      expect(
        const PatientQuery(texte: 'belkacem am').accepte(patient()),
        isTrue,
      );
    });

    test('trouve par téléphone', () {
      // À l'accueil, le numéro est souvent plus sûr que l'orthographe du nom.
      expect(const PatientQuery(texte: '686212').accepte(patient()), isTrue);
    });

    test('ne trouve pas ce qui ne correspond pas', () {
      expect(const PatientQuery(texte: 'zzz').accepte(patient()), isFalse);
    });
  });

  group('Combinaisons', () {
    test('les critères se cumulent', () {
      const q = PatientQuery(
        texte: 'amina',
        filtre: PatientFiltre.resteAPayer,
        doctorId: 'medA',
      );
      expect(q.accepte(patient(prix: 10000, verse: 2000)), isTrue);
      // Le bon patient, mais chez un autre médecin.
      expect(
        q.accepte(patient(prix: 10000, verse: 2000, doctorId: 'medB')),
        isFalse,
      );
      // Le bon médecin, mais soldé.
      expect(q.accepte(patient(prix: 10000, verse: 10000)), isFalse);
    });

    test('un patient supprimé reste invisible quel que soit le filtre', () {
      final supprime = patient(prix: 10000, verse: 0, deletedAt: DateTime.now());
      for (final f in PatientFiltre.values) {
        expect(
          PatientQuery(filtre: f).accepte(supprime),
          isFalse,
          reason: 'filtre ${f.libelle}',
        );
      }
    });
  });

  group('copyWith', () {
    test('remet le médecin à null sans effacer le reste', () {
      const base = PatientQuery(texte: 'ali', doctorId: 'medA');
      final sansMedecin = base.copyWith(doctorId: null);
      expect(sansMedecin.doctorId, isNull);
      expect(sansMedecin.texte, 'ali', reason: 'le texte est préservé');
    });

    test('ne touche pas au médecin quand il est omis', () {
      const base = PatientQuery(texte: 'ali', doctorId: 'medA');
      final autreTexte = base.copyWith(texte: 'zaki');
      expect(autreTexte.doctorId, 'medA');
      expect(autreTexte.texte, 'zaki');
    });
  });

  test('actif reflète la présence de critères', () {
    expect(const PatientQuery().actif, isFalse);
    expect(const PatientQuery(texte: 'a').actif, isTrue);
    expect(const PatientQuery(filtre: PatientFiltre.soldes).actif, isTrue);
    expect(const PatientQuery(doctorId: 'medA').actif, isTrue);
  });
}

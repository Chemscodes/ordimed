import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/coerce.dart';

class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key});

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  final _logs = <String>[];
  bool _running = false;
  bool _done = false;

  void _log(String msg) {
    setState(() => _logs.add(msg));
  }

  /// Copie un document s'il n'existe pas encore à destination. Relancer la
  /// migration ne duplique ni n'écrase rien.
  Future<bool> _copier(
    DocumentReference<Map<String, dynamic>> cible,
    Map<String, dynamic> donnees,
  ) async {
    if ((await cible.get()).exists) return false;
    await cible.set(donnees);
    return true;
  }

  Future<void> _migrer() async {
    setState(() {
      _running = true;
      _logs.clear();
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _log('ERREUR : pas de session Firebase active.');
        return;
      }
      _log('Cabinet UID : $uid');

      final db = FirebaseFirestore.instance;
      final ancienDoc = db.collection('users').doc(uid);
      final nouveauDoc = db.collection('cabinets').doc(uid);

      // 1. Lire les profils (anciens "comptes")
      final comptes = await ancienDoc.collection('comptes').get();
      _log('Profils trouvés : ${comptes.docs.length}');

      if (comptes.docs.isEmpty) {
        _log('Aucune donnée à migrer sous users/$uid/comptes.');
        _log('');
        _log('Vérification : est-ce que cabinets/$uid existe déjà ?');
        final cabinetSnap = await nouveauDoc.get();
        _log(cabinetSnap.exists ? 'Oui, le cabinet existe.' : 'Non plus.');

        final profilesSnap = await nouveauDoc.collection('profiles').get();
        _log('Profils dans cabinets : ${profilesSnap.docs.length}');

        final patientsSnap = await nouveauDoc.collection('patients').get();
        _log('Patients dans cabinets : ${patientsSnap.docs.length}');

        return;
      }

      // Compteurs
      var nbProfils = 0;
      var nbPatients = 0;
      var nbForms = 0;
      var nbRdv = 0;
      var nbVersements = 0;
      var nbAchats = 0;
      var nbFile = 0;
      var nbStats = 0;
      final patientsDejaMigres = <String>{};
      // Les entrées de salle d'attente et les achats étaient recopiés chez
      // chaque profil concerné (jusqu'à trois fois) sous le même identifiant.
      final fileDejaVue = <String>{};
      final achatsDejaVus = <String>{};

      // 2. Créer le document cabinet s'il n'existe pas
      final cabinetExiste = (await nouveauDoc.get()).exists;
      if (!cabinetExiste) {
        await nouveauDoc.set({
          'createdAt': FieldValue.serverTimestamp(),
          'migratedFrom': 'users/$uid',
        });
        _log('Document cabinet créé.');
      } else {
        _log('Document cabinet existe déjà.');
      }

      // 3. Migrer chaque profil
      for (final compte in comptes.docs) {
        final profileId = compte.id;
        final profileData = compte.data();
        _log('');
        _log('--- Profil: ${profileData['name'] ?? profileId} ---');

        // Écrire le profil sous cabinets/{uid}/profiles/{profileId}
        final profilExiste =
            (await nouveauDoc.collection('profiles').doc(profileId).get())
                .exists;
        if (!profilExiste) {
          await nouveauDoc.collection('profiles').doc(profileId).set({
            ...profileData,
            'migratedFrom': 'users/$uid/comptes/$profileId',
          });
          nbProfils++;
          _log('  Profil migré.');
        } else {
          _log('  Profil déjà présent, ignoré.');
        }

        // 4. Migrer les patients de ce profil
        final patients = await ancienDoc
            .collection('comptes')
            .doc(profileId)
            .collection('patients')
            .get();
        _log('  Patients : ${patients.docs.length}');

        for (final patient in patients.docs) {
          final patientId = patient.id;
          final patientData = patient.data();

          if (!patientsDejaMigres.contains(patientId)) {
            final existe =
                (await nouveauDoc.collection('patients').doc(patientId).get())
                    .exists;
            if (!existe) {
              await nouveauDoc.collection('patients').doc(patientId).set({
                ...patientData,
                'doctorId': profileId,
                'migratedFrom':
                    'users/$uid/comptes/$profileId/patients/$patientId',
              });
              nbPatients++;
            }
            patientsDejaMigres.add(patientId);
          }

          // 5. Migrer les forms de ce patient
          final forms = await ancienDoc
              .collection('comptes')
              .doc(profileId)
              .collection('patients')
              .doc(patientId)
              .collection('forms')
              .get();

          for (final form in forms.docs) {
            final formId = form.id;
            final existe =
                (await nouveauDoc.collection('forms').doc(formId).get()).exists;
            if (!existe) {
              await nouveauDoc.collection('forms').doc(formId).set({
                ...form.data(),
                'patientId': patientId,
                'doctorId': profileId,
                'migratedFrom':
                    'users/$uid/comptes/$profileId/patients/$patientId/forms/$formId',
              });
              nbForms++;
            }
          }
          if (forms.docs.isNotEmpty) {
            _log('    Patient $patientId : ${forms.docs.length} forms');
          }

          // 5b. Versements : la sous-collection (historique complet) et
          // l'ancien tableau du dossier (seul endroit où vivent les plus
          // anciens). Dédoublonnés sur montant + date, sinon le total double.
          final versementsSnap = await ancienDoc
              .collection('comptes')
              .doc(profileId)
              .collection('patients')
              .doc(patientId)
              .collection('versements')
              .get();
          final sources = <MapEntry<String, Map<String, dynamic>>>[
            for (final v in versementsSnap.docs) MapEntry(v.id, v.data()),
          ];
          final tableau = patientData['versements'];
          if (tableau is List) {
            for (final v in tableau) {
              if (v is Map) {
                sources.add(MapEntry('', Map<String, dynamic>.from(v)));
              }
            }
          }
          final vus = <String>{};
          for (final source in sources) {
            final v = source.value;
            final montant = asDouble(v['montant']);
            if (montant == 0) continue;
            final date = asDateOrNull(v['createdAt']);
            final cle =
                '$montant@${date?.millisecondsSinceEpoch ?? 'sans-date'}';
            if (!vus.add(cle)) continue;

            // Identifiant stable pour les entrées du tableau : relancer la
            // migration retombe sur le même document.
            final id = source.key.isNotEmpty
                ? source.key
                : 'legacy_${patientId}_${cle.replaceAll(RegExp(r'[^0-9A-Za-z]'), '_')}';
            final copie = await _copier(
              nouveauDoc.collection('versements').doc(id),
              {
                ...v,
                'parentUid': uid,
                'patientId': patientId,
                'doctorId':
                    v['doctorId'] ?? patientData['doctorId'] ?? profileId,
                'montant': montant,
                'dayKey':
                    asTextOrNull(v['dayKey']) ??
                    (date != null ? dayKeyOf(date) : ''),
                'createdAt': v['createdAt'] ?? FieldValue.serverTimestamp(),
                'migratedFrom': source.key.isNotEmpty
                    ? 'users/$uid/comptes/$profileId/patients/$patientId/versements/${source.key}'
                    : 'users/$uid/comptes/$profileId/patients/$patientId#versements',
              },
            );
            if (copie) nbVersements++;
          }
        }

        // 6. Migrer les rendez-vous de ce profil
        final rdvs = await ancienDoc
            .collection('comptes')
            .doc(profileId)
            .collection('rendezvous')
            .get();

        for (final rdv in rdvs.docs) {
          final rdvId = rdv.id;
          final existe =
              (await nouveauDoc.collection('rendezvous').doc(rdvId).get())
                  .exists;
          if (!existe) {
            await nouveauDoc.collection('rendezvous').doc(rdvId).set({
              ...rdv.data(),
              'doctorId': profileId,
              'migratedFrom': 'users/$uid/comptes/$profileId/rendezvous/$rdvId',
            });
            nbRdv++;
          }
        }
        if (rdvs.docs.isNotEmpty) {
          _log('  Rendez-vous : ${rdvs.docs.length}');
        }

        // 7. Achats de ce profil
        final achats = await ancienDoc
            .collection('comptes')
            .doc(profileId)
            .collection('purchases')
            .get();
        for (final achat in achats.docs) {
          if (!achatsDejaVus.add(achat.id)) continue;
          final d = achat.data();
          final date = asDateOrNull(d['createdAt']);
          final copie =
              await _copier(nouveauDoc.collection('purchases').doc(achat.id), {
                ...d,
                'parentUid': uid,
                'profileId': d['profileId'] ?? profileId,
                'montant': asDouble(d['montant']),
                'dayKey':
                    asTextOrNull(d['dayKey']) ??
                    (date != null ? dayKeyOf(date) : ''),
                'migratedFrom':
                    'users/$uid/comptes/$profileId/purchases/${achat.id}',
              });
          if (copie) nbAchats++;
        }
        if (achats.docs.isNotEmpty) {
          _log('  Achats : ${achats.docs.length}');
        }

        // 8. Salle d'attente de ce profil
        final file = await ancienDoc
            .collection('comptes')
            .doc(profileId)
            .collection('salle_attente')
            .get();
        for (final entree in file.docs) {
          if (!fileDejaVue.add(entree.id)) continue;
          final copie = await _copier(
            nouveauDoc.collection('salle_attente').doc(entree.id),
            {
              ...entree.data(),
              'parentUid': uid,
              'migratedFrom':
                  'users/$uid/comptes/$profileId/salle_attente/${entree.id}',
            },
          );
          if (copie) nbFile++;
        }
        if (file.docs.isNotEmpty) {
          _log('  Salle d’attente : ${file.docs.length}');
        }
      }

      // 9. Statistiques journalières (au niveau du cabinet, pas du profil).
      // L'identifiant est le jour ; la nouvelle version filtre sur le champ
      // dayKey, qu'on garantit présent.
      final stats = await ancienDoc.collection('daily_stats').get();
      for (final stat in stats.docs) {
        final copie =
            await _copier(nouveauDoc.collection('daily_stats').doc(stat.id), {
              ...stat.data(),
              'dayKey': asTextOrNull(stat.data()['dayKey']) ?? stat.id,
              'migratedFrom': 'users/$uid/daily_stats/${stat.id}',
            });
        if (copie) nbStats++;
      }
      _log('');
      _log('Statistiques journalières : ${stats.docs.length}');

      _log('');
      _log('=== Migration terminée ===');
      _log('Profils   : $nbProfils');
      _log('Patients  : $nbPatients');
      _log('Documents : $nbForms');
      _log('RDV       : $nbRdv');
      _log('Versements: $nbVersements');
      _log('Achats    : $nbAchats');
      _log('File      : $nbFile');
      _log('Stats/jour: $nbStats');
      _log('');
      _log('Les anciennes données (users/$uid) sont intactes.');
      _log('');
      _log('Redémarre l\'app pour voir tes données.');
    } catch (e, stack) {
      _log('');
      _log('ERREUR : $e');
      _log(stack.toString().split('\n').take(5).join('\n'));
    } finally {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Migration des données')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ce script copie les données de l\'ancien chemin '
              '(users/{uid}/comptes/...) vers le nouveau '
              '(cabinets/{uid}/...).',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Les données existantes ne sont pas écrasées.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _running ? null : _migrer,
              child: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lancer la migration'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _logs.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 13,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
            if (_done) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Retour'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

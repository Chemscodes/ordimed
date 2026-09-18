import '../services/api_service.dart';

/// Garantit que Poids/Taille/IMC figurent dans une liste de champs de
/// formulaire médecin, en tête de liste.
///
/// Partagé entre la configuration des prototypes par motif
/// (`dashboard_assistant.dart`) et leur résolution pour un patient donné
/// (`patient_details_page.dart`, `consultation_page.dart`) — les trois
/// doivent s'accorder sur ce qui est « toujours présent ».
List<String> ensureVitals(List<String> fields) {
  final result = List<String>.from(fields);
  bool has(String name) =>
      result.any((e) => e.toLowerCase() == name.toLowerCase());
  void addIfMissing(String name) {
    if (!has(name)) result.insert(0, name);
  }

  addIfMissing('IMC');
  addIfMissing('Taille');
  addIfMissing('Poids');
  return result;
}

/// Nom de section normalisé pour un champ de formulaire médecin.
///
/// Poids/Taille/IMC ont toujours la même clé quel que soit le libellé
/// exact saisi par l'assistant (« Poids », « poids actuel »…) — c'est ce
/// qui permet à l'historique des séances de les relire sans deviner.
String normalizeSectionKey(String label) {
  final raw = label.trim().toLowerCase();
  if (raw == 'poids' || raw == 'poids actuel' || raw == 'poids_actuel') {
    return 'poids';
  }
  if (raw == 'taille') return 'taille';
  if (raw == 'imc') return 'imc';
  final buffer = StringBuffer();
  for (final r in raw.runes) {
    final ch = String.fromCharCode(r);
    final isLetter = (r >= 48 && r <= 57) || (r >= 97 && r <= 122);
    if (isLetter) {
      buffer.write(ch);
    } else {
      buffer.write('_');
    }
  }
  final cleaned = buffer.toString().replaceAll(RegExp('_+'), '_');
  return cleaned.startsWith('_') ? cleaned.substring(1) : cleaned;
}

/// Le motif retenu pour un patient — le premier qui n'est pas « autre: ...».
String pickMotif(Map<String, dynamic> patientData) {
  final candidates = <String>[];
  final rawList = patientData['motifs'];
  if (rawList is List) {
    for (final v in rawList) {
      final s = v.toString().trim();
      if (s.isNotEmpty) candidates.add(s);
    }
  }
  if (candidates.isEmpty) {
    final raw = (patientData['motif'] ?? '').toString();
    if (raw.isNotEmpty) {
      candidates.addAll(
        raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }
  }
  for (final c in candidates) {
    final lower = c.toLowerCase();
    if (lower.startsWith('autre:')) continue;
    return c;
  }
  if (candidates.isNotEmpty) return candidates.first;
  return '';
}

/// Les champs de formulaire médecin configurés pour le motif du patient,
/// ou `[]` si aucun prototype n'existe pour ce motif.
///
/// Une liste vide n'est pas une erreur : c'est le signal que l'appelant
/// utilise pour décider quoi faire en son absence — `_addDoctorForm`
/// (patient_details_page.dart) s'en sert pour basculer sur son repli à 26
/// champs, `consultation_page.dart` pour se limiter aux trois vitaux.
Future<List<String>> resolveMotifPrototypeFields(
  Map<String, dynamic> patientData,
) async {
  final motif = pickMotif(patientData);
  if (motif.isEmpty) return [];

  try {
    final cabinet = await ApiService.instance.cabinet();
    final dynamic raw = cabinet['motifPrototypes'];
    if (raw is! Map) return [];
    final map = <String, List<String>>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      if (k.isEmpty) return;
      if (value is List) {
        final list = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isNotEmpty) map[k] = list;
      }
    });
    if (map.isEmpty) return [];
    String? match;
    for (final k in map.keys) {
      if (k.toLowerCase() == motif.toLowerCase()) {
        match = k;
        break;
      }
    }
    if (match == null) return [];
    final fields = map[match] ?? [];
    final unique = <String>[];
    for (final f in fields) {
      final cleaned = f.trim();
      if (cleaned.isEmpty) continue;
      if (!unique.contains(cleaned)) unique.add(cleaned);
    }
    return unique;
  } catch (_) {
    return [];
  }
}

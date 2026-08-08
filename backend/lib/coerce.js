'use strict';

/**
 * Conversions tolérantes.
 *
 * Portage de `lib/core/coerce.dart`. La base ne contient pas des types
 * propres : `age` est un entier depuis peu et une chaîne sur tous les
 * dossiers antérieurs, `prix` est tantôt `number` tantôt `string` selon
 * l'écran qui l'a saisi, `imc` est une chaîne à virgule décimale.
 *
 * Refuser ces valeurs à l'entrée casserait des dossiers existants. On les
 * accepte et on les normalise ici, à la frontière — une seule fois, au lieu
 * de disséminer des `parseFloat` dans les contrôleurs.
 */

function asNumberOrNull(value) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'boolean') return null;

  if (typeof value === 'string') {
    // « 12 500,50 » : espaces de milliers (y compris insécables) et virgule
    // décimale, tels que les saisit un clavier français.
    const propre = value
      .replace(/[\s  ]/g, '')
      .replace(',', '.')
      .trim();
    if (propre === '') return null;
    const n = Number(propre);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

const asNumber = (value, defaut = 0) => {
  const n = asNumberOrNull(value);
  return n === null ? defaut : n;
};

function asIntOrNull(value) {
  const n = asNumberOrNull(value);
  return n === null ? null : Math.trunc(n);
}

const asInt = (value, defaut = 0) => {
  const n = asIntOrNull(value);
  return n === null ? defaut : n;
};

/**
 * Accepte une date sous toutes les formes qu'a produites l'app :
 * `Date`, millisecondes, chaîne ISO, et le format étiqueté des
 * sauvegardes (`{__type:'timestamp', value:'…'}`).
 */
function asDateOrNull(value) {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;

  if (typeof value === 'number') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }

  if (typeof value === 'object') {
    // Sauvegarde JSON de l'app Flutter.
    if (value.__type === 'timestamp' && value.value) {
      return asDateOrNull(value.value);
    }
    // Export brut Firestore.
    if (typeof value._seconds === 'number') {
      return new Date(value._seconds * 1000);
    }
    return null;
  }

  if (typeof value === 'string') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

const asText = (value) => {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'object') return '';
  return String(value);
};

const asTextOrNull = (value) => {
  const s = asText(value).trim();
  return s === '' ? null : s;
};

/** `YYYY-MM-DD` en heure locale, comme le `dayKey` de l'app. */
function dayKeyOf(date) {
  const d = asDateOrNull(date) || new Date();
  const p = (v) => String(v).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/**
 * Retire les clés `undefined` d'un objet.
 *
 * Mongoose écrirait `null` là où l'app n'a rien envoyé, ce qui transforme
 * « champ non modifié » en « champ vidé » lors d'une mise à jour partielle.
 */
function sansIndefinis(objet) {
  const sortie = {};
  for (const [k, v] of Object.entries(objet)) {
    if (v !== undefined) sortie[k] = v;
  }
  return sortie;
}

module.exports = {
  asNumberOrNull,
  asNumber,
  asIntOrNull,
  asInt,
  asDateOrNull,
  asText,
  asTextOrNull,
  dayKeyOf,
  sansIndefinis,
};

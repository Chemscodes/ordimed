'use strict';

/**
 * Enrobe un contrôleur asynchrone.
 *
 * Express 4 n'attrape pas les rejets de promesse : une exception dans un
 * `async` laisse la requête ouverte jusqu'au délai d'expiration côté
 * Flutter, sans message ni trace. C'est le pire symptôme à diagnostiquer —
 * l'app semble lente, pas cassée.
 */
const asyncHandler = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

module.exports = { asyncHandler };

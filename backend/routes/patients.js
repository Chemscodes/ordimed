'use strict';

const express = require('express');

const ctrl = require('../controllers/patientController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/', asyncHandler(ctrl.lister));
router.post('/', asyncHandler(ctrl.creer));
router.get('/:id', asyncHandler(ctrl.lire));
// Le dossier complet en une requete : la page affiche documents et
// versements cote a cote.
router.get('/:id/detail', asyncHandler(ctrl.detail));
router.put('/:id', asyncHandler(ctrl.modifier));
// Suppression douce : le dossier reste, ses versements aussi.
router.delete('/:id', asyncHandler(ctrl.supprimer));
router.post('/:id/restaurer', asyncHandler(ctrl.restaurer));

module.exports = router;

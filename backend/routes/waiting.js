'use strict';

const express = require('express');

const ctrl = require('../controllers/waitingController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/', asyncHandler(ctrl.lister));
router.post('/', asyncHandler(ctrl.ajouter));
router.post('/:id/demarrer', asyncHandler(ctrl.demarrer));
// Decompte la seance, sort le patient, marque le rendez-vous honore.
router.post('/:id/cloturer', asyncHandler(ctrl.cloturer));
router.post('/:id/etape', asyncHandler(ctrl.changerEtape));

module.exports = router;

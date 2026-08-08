'use strict';

const express = require('express');

const ctrl = require('../controllers/rendezvousController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/', asyncHandler(ctrl.lister));
router.post('/', asyncHandler(ctrl.creer));
router.put('/:id', asyncHandler(ctrl.modifier));
router.post('/:id/etape', asyncHandler(ctrl.changerEtape));
// Le patient se presente : cree l'entree en salle ET marque le rendez-vous.
router.post('/:id/arrive', asyncHandler(ctrl.marquerArrive));
router.delete('/:id', asyncHandler(ctrl.supprimer));

module.exports = router;

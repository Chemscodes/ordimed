'use strict';

const express = require('express');

const ctrl = require('../controllers/profileController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/', asyncHandler(ctrl.lister));
router.post('/', asyncHandler(ctrl.creer));
router.get('/:id', asyncHandler(ctrl.lire));
router.put('/:id', asyncHandler(ctrl.modifier));
router.delete('/:id', asyncHandler(ctrl.supprimer));

module.exports = router;

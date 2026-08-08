'use strict';

const express = require('express');

const ctrl = require('../controllers/errorController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();

// Sans jeton : une erreur peut survenir avant toute connexion.
router.post('/', asyncHandler(ctrl.signaler));
router.get('/', exigeAuth, asyncHandler(ctrl.lister));

module.exports = router;

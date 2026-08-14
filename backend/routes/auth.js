'use strict';

const express = require('express');

const ctrl = require('../controllers/authController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();

// Firebase Auth : createUserWithEmailAndPassword / signInWithEmailAndPassword.
router.post('/register', asyncHandler(ctrl.register));
router.post('/login', asyncHandler(ctrl.login));
router.post('/logout', ctrl.logout);

// Le second niveau : le PIN de profil, desormais verifie cote serveur.
router.post('/pin', exigeAuth, asyncHandler(ctrl.verifierPin));

router.get('/me', exigeAuth, asyncHandler(ctrl.moi));
router.put('/cabinet', exigeAuth, asyncHandler(ctrl.majCabinet));
router.post('/cabinet/liste', exigeAuth, asyncHandler(ctrl.ajouterListe));

module.exports = router;

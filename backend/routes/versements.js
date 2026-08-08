'use strict';

const express = require('express');

const ctrl = require('../controllers/versementController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/', asyncHandler(ctrl.lister));
router.post('/', asyncHandler(ctrl.creer));

module.exports = router;

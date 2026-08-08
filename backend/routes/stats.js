'use strict';

const express = require('express');

const ctrl = require('../controllers/statsController');
const { exigeAuth } = require('../middleware/auth');
const { asyncHandler } = require('./index');

const router = express.Router();
router.use(exigeAuth);

router.get('/daily', asyncHandler(ctrl.journalier));
router.post('/recalculer', asyncHandler(ctrl.recalculer));

module.exports = router;

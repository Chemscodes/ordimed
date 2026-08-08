'use strict';

const path = require('path');

const cors = require('cors');
const express = require('express');
const mongoose = require('mongoose');

/**
 * L'application Express, séparée de son démarrage.
 *
 * `server.js` la branche sur un port et sur MongoDB ; les tests la branchent
 * sur une base éphémère sans ouvrir de port. Sans cette séparation, tester
 * une route imposerait de lancer le serveur complet — et donc de ne jamais
 * le faire.
 */
function creerApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '10mb' }));

  // Firebase Storage n'a jamais été utilisé par ce projet : rien n'y
  // transite aujourd'hui. Le dossier est posé pour un usage futur —
  // voir MIGRATION.md §1.5.
  app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

  app.get('/health', (_req, res) =>
    res.json({
      ok: true,
      mongo: mongoose.connection.readyState === 1 ? 'connecte' : 'deconnecte',
    })
  );

  app.use('/api/auth', require('./routes/auth'));
  app.use('/api/profiles', require('./routes/profiles'));
  app.use('/api/patients', require('./routes/patients'));
  app.use('/api/forms', require('./routes/forms'));
  app.use('/api/versements', require('./routes/versements'));
  app.use('/api/rendezvous', require('./routes/rendezvous'));
  app.use('/api/waiting', require('./routes/waiting'));
  app.use('/api/purchases', require('./routes/purchases'));
  app.use('/api/stats', require('./routes/stats'));
  app.use('/api/errors', require('./routes/errors'));

  app.use((_req, res) => res.status(404).json({ error: 'Route inconnue' }));

  // Sans ce gestionnaire, une exception dans un contrôleur async laisse la
  // requête pendre jusqu'au délai d'expiration côté Flutter, sans message.
  // C'est le pire symptôme à diagnostiquer : l'app semble lente, pas cassée.
  app.use((err, _req, res, _next) => {
    console.error('[erreur]', err.message);
    if (err.name === 'ValidationError') {
      return res.status(400).json({ error: err.message });
    }
    if (err.name === 'CastError') {
      return res.status(400).json({ error: 'Identifiant invalide' });
    }
    return res.status(500).json({ error: 'Erreur serveur' });
  });

  return app;
}

module.exports = { creerApp };

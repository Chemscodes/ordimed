'use strict';

require('dotenv').config();

const http = require('http');
const path = require('path');

const cors = require('cors');
const express = require('express');
const mongoose = require('mongoose');

const { initRealtime } = require('./realtime');

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Firebase Storage n'a jamais été utilisé par ce projet : rien n'y transite
// aujourd'hui. Le dossier et la route sont posés pour un usage futur — voir
// MIGRATION.md §1.5.
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

// Gestionnaire d'erreurs. Sans lui, une exception dans un contrôleur async
// laisse la requête pendre jusqu'au délai d'expiration côté Flutter, sans
// message — le pire des symptômes à diagnostiquer.
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

const PORT = Number(process.env.PORT || 4000);
const MONGO_URL =
  process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/ordimed?replicaSet=rs0';

async function demarrer() {
  await mongoose.connect(MONGO_URL, { serverSelectionTimeoutMS: 15000 });
  console.log('MongoDB connecté');

  // Vérifie que les transactions sont disponibles. L'app fait 21 écritures
  // atomiques ; sans replica set elles échoueraient à l'exécution, à moitié
  // écrites. Mieux vaut le savoir au démarrage.
  try {
    const session = await mongoose.startSession();
    session.startTransaction();
    await session.abortTransaction();
    await session.endSession();
  } catch {
    console.warn(
      'ATTENTION : transactions indisponibles. MongoDB doit tourner en ' +
        'replica set (--replSet rs0). Les écritures atomiques ne seront ' +
        'pas garanties.'
    );
  }

  const serveur = http.createServer(app);
  initRealtime(serveur);

  serveur.listen(PORT, () => console.log(`Ordimed API sur :${PORT}`));
}

demarrer().catch((e) => {
  console.error('Démarrage impossible :', e.message);
  process.exit(1);
});

'use strict';

require('dotenv').config();

const http = require('http');

const mongoose = require('mongoose');

const { creerApp } = require('./app');
const { initRealtime } = require('./realtime');

const PORT = Number(process.env.PORT || 4000);
const MONGO_URL =
  process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/ordimed?replicaSet=rs0';

async function demarrer() {
  await mongoose.connect(MONGO_URL, { serverSelectionTimeoutMS: 15000 });
  console.log('MongoDB connecté');

  // L'app fait 21 écritures atomiques. MongoDB n'autorise les transactions
  // que sur un replica set ; un `mongo:7` seul les refuse. Sans ce test,
  // l'échec surviendrait en production, à moitié écrit.
  try {
    const session = await mongoose.startSession();
    session.startTransaction();
    await session.abortTransaction();
    await session.endSession();
    console.log('Transactions disponibles');
  } catch {
    console.warn(
      'ATTENTION : transactions indisponibles. MongoDB doit tourner en ' +
        'replica set (--replSet rs0). Les écritures atomiques ne seront ' +
        'pas garanties.'
    );
  }

  const serveur = http.createServer(creerApp());
  initRealtime(serveur);

  serveur.listen(PORT, () => console.log(`Ordimed API sur :${PORT}`));
}

demarrer().catch((e) => {
  console.error('Démarrage impossible :', e.message);
  process.exit(1);
});
